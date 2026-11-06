import Foundation

/// Every call the verification flow makes with the hosted session token, and
/// no others. The token travels only in `Authorization: Bearer`, never in a
/// query string, and the client never sends `X-Management-Token`: the
/// orchestrator would then authenticate the request as the console.
package final class APIClient: Sendable {
    package let baseURL: URL
    private let sessionToken: String
    private let transport: HTTPTransport

    static let requestTimeout: TimeInterval = 30
    static let uploadTimeout: TimeInterval = 120

    package init(baseURL: URL, sessionToken: String, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.transport = transport
    }

    // MARK: Session

    package func currentSession() async throws -> HostedSession {
        try await perform(request("GET", "api/v1/sessions/current"))
    }

    package func saveMetadata(_ patch: MetadataPatch) async throws {
        let _: Ignored = try await perform(request("PATCH", "api/v1/sessions/metadata", json: patch))
    }

    package func recordConsent(scopes: [String]) async throws {
        let body = ConsentBody(version: ConsentVersion.current, scopes: scopes)
        let _: Ignored = try await perform(request("POST", "api/v1/sessions/consent", json: body))
    }

    // MARK: Case

    /// Get-or-create the session's case. The server takes identity and
    /// requirements from the session's profile; the body mirrors what the web
    /// sends so a session without a profile still gets the right case.
    package func getOrCreateCase(for session: HostedSession) async throws -> VerificationCase {
        let subjectId = session.subjectId.flatMap { $0.isEmpty ? nil : $0 } ?? session.subjectRef
        let body = CreateCaseBody(
            userId: session.id,
            subjectId: subjectId,
            requiredChecks: session.requiredChecks,
            requiredDocuments: session.requiredDocuments
        )
        return try await perform(request("POST", "api/verification/cases", json: body))
    }

    package func getCase(id: String) async throws -> VerificationCase {
        try await perform(request("GET", "api/verification/cases/\(id)"))
    }

    /// One document, as multipart. The response is not enveloped and the flow
    /// does not need it: the next `getCase` shows the document.
    package func uploadDocument(caseId: String, docType: String, captureRole: String?, data: Data, mimeType: String) async throws {
        var body = MultipartBody()
        body.addField("type", docType)
        if let captureRole { body.addField("capture_role", captureRole) }
        body.addFile("file", filename: MultipartBody.uploadFilename(docType: docType, mimeType: mimeType), mimeType: mimeType, data: data)

        var request = request("POST", "api/verification/cases/\(caseId)/documents", timeout: Self.uploadTimeout)
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.finalized()

        let (responseData, response) = try await exchange(request)
        if response.statusCode == 422 {
            let refusal = try? JSONDecoder.identified.decode(ErrorBody.self, from: responseData)
            throw APIError.documentRefused(
                message: refusal?.error ?? "We couldn't accept this document. Try a clearer photo, or a different document from the list.",
                exhausted: refusal?.exhausted ?? false
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode, message: Self.errorMessage(responseData, status: response.statusCode))
        }
    }

    /// Runs liveness and face match. Synchronous on the server despite its 202.
    package func runBiometricCheck(caseId: String) async throws -> VerificationCheck {
        let body = BiometricBody(checkType: CheckType.biometricFaceMatch)
        return try await perform(request("POST", "api/verification/cases/\(caseId)/checks/biometric", json: body))
    }

    package func submitCase(id: String) async throws -> SubmitResult {
        try await perform(request("POST", "api/verification/cases/\(id)/submit"))
    }

    // MARK: Address

    /// 400 invalid code, 404 not found, 503 lookup unavailable. On 503 the
    /// subject continues with the unresolved code.
    package func resolveDigitalAddress(code: String) async throws -> DigitalAddress {
        try await perform(request("GET", "api/v1/addresses/ghanapost/resolve", query: [URLQueryItem(name: "code", value: code)]))
    }

    /// 404 when there is no code at that point, 503 lookup unavailable.
    package func encodeDigitalAddress(latitude: Double, longitude: Double) async throws -> DigitalAddress {
        try await perform(request("GET", "api/v1/addresses/ghanapost/encode", query: [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
        ]))
    }

    // MARK: Plumbing

    func request(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = APIClient.requestTimeout
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func request(_ method: String, _ path: String, json body: some Encodable) throws -> URLRequest {
        var request = request(method, path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.identified.encode(body)
        return request
    }

    /// Sends a request and unwraps the `{"data": ...}` envelope.
    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await send(request)
        do {
            return try JSONDecoder.identified.decode(Envelope<T>.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a request and returns the body of a 2xx response.
    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await exchange(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode, message: Self.errorMessage(data, status: response.statusCode))
        }
        return data
    }

    func exchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let original = try await rawExchange(request)
        let casePath = baseURL.appendingPathComponent("api/verification/cases").path
        let path = request.url?.path ?? ""
        guard (path == casePath || path.hasPrefix(casePath + "/")),
              original.1.statusCode == 401,
              Self.errorMessage(original.0, status: 401) == "invalid management session"
        else { return original }

        // The combined case middleware masks an expired hosted token as a
        // management failure. Diagnose it once; never replay the case request.
        try Task.checkCancellation()
        do {
            let probe = try await rawExchange(self.request("GET", "api/v1/sessions/current"))
            if probe.1.statusCode == 401 { return probe }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A failed diagnostic request must preserve the original failure.
        }
        return original
    }

    private func rawExchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.transport(error.localizedDescription)
        }
    }

    static func errorMessage(_ data: Data, status: Int) -> String {
        (try? JSONDecoder.identified.decode(ErrorBody.self, from: data))?.error ?? "Request failed (\(status))"
    }
}

struct Envelope<T: Decodable>: Decodable {
    let data: T
}

struct ErrorBody: Decodable {
    let error: String?
    let exhausted: Bool?
}

/// A `data` object whose contents the flow does not need, but whose presence
/// confirms the call succeeded.
struct Ignored: Decodable {}

private struct ConsentBody: Encodable {
    let version: String
    let scopes: [String]
}

private struct CreateCaseBody: Encodable {
    let userId: String
    let subjectId: String
    let requiredChecks: [String]
    let requiredDocuments: [String]
}

private struct BiometricBody: Encodable {
    let checkType: String
}
