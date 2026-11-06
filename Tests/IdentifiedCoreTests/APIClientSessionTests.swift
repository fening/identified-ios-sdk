import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func fetchesTheCurrentSessionWithABearerToken() async throws {
    let transport = StubTransport(.data(Fixtures.sessionJSON()))
    let session = try await client(transport).currentSession()
    let request = try #require(transport.lastRequest)
    #expect(session.id == "sess-1")
    #expect(request.url?.absoluteString == "https://api.test/api/v1/sessions/current")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok_123")
    #expect(request.value(forHTTPHeaderField: "X-Management-Token") == nil)
    #expect(request.url?.query == nil)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func surfacesTheServersErrorMessage() async {
    let transport = StubTransport(.error(401, "session expired"))
    await #expect(throws: APIError.http(status: 401, message: "session expired")) {
        try await client(transport).currentSession()
    }
}

@Test func describesAnErrorWithNoBody() async {
    let transport = StubTransport(StubTransport.Reply(status: 502, body: Data()))
    await #expect(throws: APIError.http(status: 502, message: "Request failed (502)")) {
        try await client(transport).currentSession()
    }
}

@Test func reportsTransportFailures() async {
    let transport = StubTransport()
    transport.failure = URLError(.notConnectedToInternet)
    await #expect(throws: APIError.self) {
        try await client(transport).currentSession()
    }
}

@Test func savesMetadata() async throws {
    let transport = StubTransport(.data(["session_id": "sess-1", "metadata": ["first_name": "Ama"]]))
    try await client(transport).saveMetadata(.name(first: "Ama", middle: "", last: "Mensah"))
    let request = try #require(transport.lastRequest)
    #expect(request.httpMethod == "PATCH")
    #expect(request.url?.path == "/api/v1/sessions/metadata")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.bodyString == #"{"metadata":{"first_name":"Ama","last_name":"Mensah","middle_name":""}}"#)
}

@Test func recordsConsentWithThePinnedVersion() async throws {
    let transport = StubTransport(.json(201, ["data": ["id": "consent-1"]]))
    try await client(transport).recordConsent(scopes: ["identity", "biometric"])
    let request = try #require(transport.lastRequest)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/v1/sessions/consent")
    #expect(request.bodyString == #"{"scopes":["identity","biometric"],"version":"2026-09-04"}"#)
}

@Test func classifiesSessionFailures() {
    #expect(APIError.http(status: 401, message: "session expired").sessionFailure == .expired)
    #expect(APIError.http(status: 401, message: "invalid session token").sessionFailure == .invalid)
    #expect(APIError.http(status: 401, message: "missing session token").sessionFailure == .invalid)
    #expect(APIError.http(status: 404, message: "not found").sessionFailure == nil)
    #expect(APIError.transport("offline").sessionFailure == nil)
}
