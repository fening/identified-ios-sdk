import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func caseAuthFallbackReportsTheHostedSessionsActualExpiry() async {
    let transport = StubTransport(.error(401, "invalid management session"), .error(401, "session expired"))
    await #expect(throws: APIError.http(status: 401, message: "session expired")) {
        _ = try await client(transport).getCase(id: "case-1")
    }
    #expect(transport.requests.map { $0.url?.path } == ["/api/verification/cases/case-1", "/api/v1/sessions/current"])
}

@Test func anUnavailableExpiryProbePreservesTheOriginalCaseFailure() async {
    let transport = StubTransport(.error(401, "invalid management session"), .error(503, "service unavailable"))
    await #expect(throws: APIError.http(status: 401, message: "invalid management session")) {
        _ = try await client(transport).getCase(id: "case-1")
    }
    #expect(transport.requests.count == 2)
}

@Test func sessionAuthFailuresAreNeverProbedRecursively() async {
    let transport = StubTransport(.error(401, "invalid management session"))
    await #expect(throws: APIError.http(status: 401, message: "invalid management session")) {
        _ = try await client(transport).currentSession()
    }
    #expect(transport.requests.count == 1)
}

@Test func expiryDisambiguationNeverResendsACaseMutation() async {
    let transport = StubTransport(.error(401, "invalid management session"), .error(401, "session expired"))
    await #expect(throws: APIError.http(status: 401, message: "session expired")) {
        _ = try await client(transport).submitCase(id: "case-1")
    }
    #expect(transport.requests.map(\.httpMethod) == ["POST", "GET"])
}

@Test func aStillValidSessionDoesNotHideTheOriginalCaseRefusal() async {
    let transport = StubTransport(.error(401, "invalid management session"), .data(Fixtures.sessionJSON()))
    await #expect(throws: APIError.http(status: 401, message: "invalid management session")) {
        _ = try await client(transport).getCase(id: "case-1")
    }
    #expect(transport.requests.count == 2)
}

@Test func ordinaryCaseAuthFailuresDoNotTriggerAProbe() async {
    let transport = StubTransport(.error(401, "invalid session token"))
    await #expect(throws: APIError.http(status: 401, message: "invalid session token")) {
        _ = try await client(transport).getCase(id: "case-1")
    }
    #expect(transport.requests.count == 1)
}

private struct CancellingExpiryProbe: HTTPTransport {
    let original = StubTransport(.error(401, "invalid management session"))

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path == "/api/v1/sessions/current" { throw URLError(.cancelled) }
        return try await original.send(request)
    }
}

@Test func cancellingAnExpiryProbeCancelsTheCaseRequest() async {
    let api = APIClient(baseURL: URL(string: "https://api.test")!, sessionToken: "synthetic-token", transport: CancellingExpiryProbe())
    await #expect(throws: CancellationError.self) { _ = try await api.getCase(id: "case-1") }
}

@Test func createsTheCaseWithTheSessionsRequirements() async throws {
    let transport = StubTransport(.data(Fixtures.caseJSON()))
    let c = try await client(transport).getOrCreateCase(for: Fixtures.session(["subject_id": "partner-7"]))
    let request = try #require(transport.lastRequest)
    #expect(c.id == "case-1")
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/verification/cases")
    #expect(request.bodyString == #"{"requiredChecks":["id_document","biometric_liveness","biometric_face_match"],"requiredDocuments":["license_front","license_back","selfie"],"subjectId":"partner-7","userId":"sess-1"}"#)
}

@Test func fallsBackToTheSubjectRefWithoutASubjectId() async throws {
    let transport = StubTransport(.data(Fixtures.caseJSON()), .data(Fixtures.caseJSON()))
    _ = try await client(transport).getOrCreateCase(for: Fixtures.session())
    #expect(transport.requests[0].bodyString.contains(#""subjectId":"driver-42""#))
    _ = try await client(transport).getOrCreateCase(for: Fixtures.session(["subject_id": ""]))
    #expect(transport.requests[1].bodyString.contains(#""subjectId":"driver-42""#))
}

@Test func fetchesACase() async throws {
    let transport = StubTransport(.data(Fixtures.caseJSON(status: "documents_pending")))
    let c = try await client(transport).getCase(id: "case-1")
    #expect(c.status == "documents_pending")
    #expect(transport.lastRequest?.url?.path == "/api/verification/cases/case-1")
    #expect(transport.lastRequest?.httpMethod == "GET")
}

@Test func uploadsADocumentAsMultipart() async throws {
    let transport = StubTransport(.json(201, ["success": true, "documentUrl": "https://files/x"]))
    try await client(transport).uploadDocument(caseId: "case-1", docType: "selfie", captureRole: "left", data: Data("JPEG".utf8), mimeType: "image/jpeg")
    let request = try #require(transport.lastRequest)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/verification/cases/case-1/documents")
    #expect(request.timeoutInterval == 120)
    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    let body = request.bodyString
    #expect(body.contains("name=\"type\"\r\n\r\nselfie\r\n"))
    #expect(body.contains("name=\"capture_role\"\r\n\r\nleft\r\n"))
    #expect(body.contains("filename=\"selfie.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG\r\n"))
    #expect(body.range(of: "name=\"type\"")!.lowerBound < body.range(of: "name=\"capture_role\"")!.lowerBound)
    #expect(body.range(of: "name=\"capture_role\"")!.lowerBound < body.range(of: "name=\"file\"")!.lowerBound)
}

@Test func omitsTheCaptureRoleWhenThereIsNone() async throws {
    let transport = StubTransport(.json(201, ["success": true, "documentUrl": "https://files/x"]))
    try await client(transport).uploadDocument(caseId: "case-1", docType: "proof_of_address", captureRole: nil, data: Data("%PDF".utf8), mimeType: "application/pdf")
    let body = try #require(transport.lastRequest).bodyString
    #expect(!body.contains("capture_role"))
    #expect(body.contains("filename=\"proof_of_address.pdf\""))
}

@Test func turnsAProofOfAddressRefusalIntoATypedError() async {
    let transport = StubTransport(.json(422, ["error": "This bill is older than 90 days.", "exhausted": true]))
    await #expect(throws: APIError.documentRefused(message: "This bill is older than 90 days.", exhausted: true)) {
        try await client(transport).uploadDocument(caseId: "case-1", docType: "proof_of_address", captureRole: nil, data: Data(), mimeType: "image/jpeg")
    }
}

@Test func refusalWithoutAMessageGetsTheWebsWording() async {
    let transport = StubTransport(StubTransport.Reply(status: 422, body: Data()))
    await #expect(throws: APIError.documentRefused(message: "We couldn't accept this document. Try a clearer photo, or a different document from the list.", exhausted: false)) {
        try await client(transport).uploadDocument(caseId: "case-1", docType: "proof_of_address", captureRole: nil, data: Data(), mimeType: "image/jpeg")
    }
}

@Test func reportsAnOversizedUpload() async {
    let transport = StubTransport(.error(413, "file too large"))
    await #expect(throws: APIError.http(status: 413, message: "file too large")) {
        try await client(transport).uploadDocument(caseId: "case-1", docType: "license_front", captureRole: nil, data: Data(), mimeType: "image/jpeg")
    }
}

@Test func runsTheBiometricCheck() async throws {
    let transport = StubTransport(.json(202, ["message": "Biometric check completed", "data": ["check_type": "biometric_face_match", "status": "passed"]]))
    let check = try await client(transport).runBiometricCheck(caseId: "case-1")
    #expect(check.status == "passed")
    #expect(transport.lastRequest?.url?.path == "/api/verification/cases/case-1/checks/biometric")
    #expect(transport.lastRequest?.bodyString == #"{"checkType":"biometric_face_match"}"#)
}

@Test func submitsTheCase() async throws {
    let transport = StubTransport(.json(200, ["message": "ID verification submitted", "data": ["case_id": "case-1", "status": "manual_review", "ready_for_review": true]]))
    let result = try await client(transport).submitCase(id: "case-1")
    #expect(result == SubmitResult(caseId: "case-1", status: "manual_review", readyForReview: true, closureReason: nil))
    #expect(transport.lastRequest?.httpMethod == "POST")
    #expect(transport.lastRequest?.url?.path == "/api/verification/cases/case-1/submit")
    #expect(transport.lastRequest?.httpBody == nil)
}
