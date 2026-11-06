import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func launchesAFirstRunAtConsent() async {
    let result = await Launch.load(using: client(StubTransport(.data(Fixtures.sessionJSON()))))
    let state = try! result.get()
    #expect(state.route == .entry(.consent))
    #expect(state.mode == .firstRun)
    #expect(state.session.id == "sess-1")
}

@Test func launchesAReturnVisitInResumeMode() async {
    let json = Fixtures.sessionJSON(["case_id": "case-1", "case_status": "documents_pending", "consent_recorded": true])
    let state = try! await Launch.load(using: client(StubTransport(.data(json)))).get()
    #expect(state.route == .entry(.checklist(caseId: "case-1")))
    #expect(state.mode == .resume)
}

@Test func endsTheFlowForAnExpiredSession() async {
    let result = await Launch.load(using: client(StubTransport(.error(401, "session expired"))))
    #expect(result == .failure(.sessionExpired))
}

@Test func endsTheFlowForAnInvalidOrMismatchedSession() async {
    #expect(await Launch.load(using: client(StubTransport(.error(401, "invalid session token")))) == .failure(.sessionInvalid))
    #expect(await Launch.load(using: client(StubTransport(.error(404, "session case not found")))) == .failure(.sessionInvalid))
}

@Test func offersARetryForAnythingElse() async {
    #expect(await Launch.load(using: client(StubTransport(.error(503, "upstream unavailable")))) == .failure(.unavailable("upstream unavailable")))
    let offline = StubTransport()
    offline.failure = URLError(.notConnectedToInternet)
    guard case .failure(.unavailable) = await Launch.load(using: client(offline)) else {
        Issue.record("expected unavailable")
        return
    }
}
