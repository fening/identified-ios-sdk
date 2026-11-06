import Foundation
import Testing
@testable import Identified
import IdentifiedCore
import IdentifiedTestSupport

@MainActor
private final class Results {
    var all: [IdentifiedResult] = []
}

@MainActor
private func makeModel(_ replies: StubTransport.Reply...) -> (FlowModel, StubTransport, Results) {
    let transport = StubTransport()
    transport.enqueue(replies)
    let results = Results()
    let model = FlowModel(client: client(transport)) { results.all.append($0) }
    return (model, transport, results)
}

private func resumeSession() -> [String: Any] {
    Fixtures.sessionJSON([
        "case_id": "case-1", "case_status": "draft", "consent_recorded": true,
        "identity_name_complete": true, "first_name": "Ama", "last_name": "Mensah",
    ])
}

@MainActor @Test func aNewSessionOpensOnEntryAndBeginsWithConsent() async {
    let (model, _, _) = makeModel(.data(Fixtures.sessionJSON()))
    await model.load()
    #expect(model.stage == .ready)
    #expect(model.path.isEmpty)
    model.begin()
    #expect(model.path == [.consent])
}

@MainActor @Test func aCasePastIntakeOpensOnStatus() async {
    let (model, _, _) = makeModel(.data(Fixtures.sessionJSON(["case_id": "case-1", "case_status": "submitted", "consent_recorded": true])))
    await model.load()
    #expect(model.path == [.status])
}

@MainActor @Test func anExpiredSessionEndsTheFlow() async {
    let (model, _, results) = makeModel(.error(401, "session expired"))
    await model.load()
    #expect(results.all == [.failed(.sessionExpired)])
}

@MainActor @Test func anUnreachableServiceOffersARetry() async {
    let (model, _, results) = makeModel(.error(503, "upstream unavailable"))
    await model.load()
    #expect(model.stage == .unavailable("upstream unavailable"))
    #expect(results.all.isEmpty)
}

@MainActor @Test func consentRecordsTheSessionsScopesThenCreatesTheCase() async throws {
    let (model, transport, _) = makeModel(.data(Fixtures.sessionJSON()), .data([:]), .data(Fixtures.caseJSON()))
    await model.load()
    model.begin()
    try await model.consent()
    #expect(model.path == [.checklist])
    #expect(model.caseId == "case-1")
    #expect(transport.requests[1].bodyString.contains(#""scopes":["identity","biometric"]"#))
    #expect(transport.requests[2].url?.path == "/api/verification/cases")
}

@MainActor @Test func onAFirstRunEachSaveMovesToTheNextScreen() async throws {
    let named = Fixtures.sessionJSON(["first_name": "Ama", "last_name": "Mensah", "identity_name_complete": true])
    let (model, transport, _) = makeModel(
        .data(Fixtures.sessionJSON()), .data([:]), .data(Fixtures.caseJSON()),  // load, consent, case
        .data(Fixtures.caseJSON()),                                             // checklist
        .data([:]), .data(named)                                                // save name, refetch
    )
    await model.load()
    model.begin()
    try await model.consent()
    try await model.refreshForChecklist()
    model.continueFromChecklist()
    #expect(model.path == [.checklist, .yourName])
    try await model.saveName(first: "Ama", middle: "", last: "Mensah")
    #expect(model.path == [.checklist, .yourName, .idDetails])
    #expect(transport.requests[4].httpMethod == "PATCH")
    #expect(transport.requests[5].url?.path == "/api/v1/sessions/current")
}

@MainActor @Test func inResumeModeEachSaveReturnsToTheChecklist() async throws {
    let (model, _, _) = makeModel(
        .data(resumeSession()),
        .data(Fixtures.caseJSON()), .data(resumeSession()),  // checklist: case, then session
        .data([:]), .data(resumeSession())                   // save ID details, refetch
    )
    await model.load()
    model.begin()
    #expect(model.path == [.checklist])
    try await model.refreshForChecklist()
    #expect(model.mode == .resume)
    model.continueFromChecklist()
    #expect(model.path == [.checklist, .idDetails])
    try await model.saveIDDetails(dob: "1990-01-05", idType: "passport", idNumber: "G123")
    #expect(model.path == [.checklist])
}

@MainActor @Test func submittingSavesTheReportChoiceThenShowsStatus() async throws {
    let (model, transport, results) = makeModel(
        .data(resumeSession()), .data(Fixtures.caseJSON()), .data(resumeSession()),
        .data([:]), .data(["case_id": "case-1", "status": "submitted"])
    )
    await model.load()
    model.begin()
    try await model.refreshForChecklist()
    try await model.submit(reportOptIn: false, email: "ama@example.com")
    #expect(model.path == [.status])
    #expect(transport.requests[3].bodyString.contains(#""report_email":"""#))
    #expect(transport.requests[4].url?.path == "/api/verification/cases/case-1/submit")
    // Closing before the status screen's first poll must use the submit response.
    model.close()
    #expect(results.all == [.completed(caseId: "case-1", status: "submitted")])
}

@MainActor @Test func incompleteSelfieFramesNeverReachTheServer() async throws {
    let (model, transport, _) = makeModel(.data(resumeSession()))
    await model.load()
    // Provide enough replies to expose accidental requests without crashing the stub.
    transport.enqueue([.json(200, [:]), .data(["check_type": "biometric_face_match", "status": "completed"])])
    await #expect(throws: (any Error).self) {
        try await model.uploadSelfie([SelfieRole.center: Data([1])])
    }
    #expect(transport.requests.count == 1)
}

@MainActor @Test func selfieFramesUploadCentreLastThenRunTheCheck() async throws {
    let (model, transport, _) = makeModel(
        .data(resumeSession()), .data(Fixtures.caseJSON()), .data(resumeSession()),
        .json(200, ["success": true]), .json(200, ["success": true]), .json(200, ["success": true]),
        .data(["check_type": "biometric_face_match", "status": "completed"])
    )
    await model.load()
    model.begin()
    try await model.refreshForChecklist()
    let jpeg = Data([0xFF, 0xD8])
    try await model.uploadSelfie([SelfieRole.center: jpeg, SelfieRole.left: jpeg, SelfieRole.right: jpeg])
    let roles = transport.requests[3...5].map { $0.bodyString.contains("name=\"capture_role\"\r\n\r\ncenter") }
    #expect(roles == [false, false, true])
    #expect(transport.requests[6].url?.path == "/api/verification/cases/case-1/checks/biometric")
    #expect(model.path == [.checklist])
}

@MainActor @Test func aDeadSessionMidFlowEndsTheFlowInsteadOfShowingAnError() async throws {
    let (model, _, results) = makeModel(.data(resumeSession()), .error(401, "invalid session token"))
    await model.load()
    model.begin()
    do {
        try await model.refreshForChecklist()
        Issue.record("expected an error")
    } catch {
        #expect(model.message(for: error) == nil)
    }
    #expect(results.all == [.failed(.sessionInvalid)])
}

@MainActor @Test func aConcurrentEditRefetchesTheSessionBeforeTheRetry() async {
    let renamed = Fixtures.sessionJSON(["first_name": "Akosua"])
    let (model, transport, _) = makeModel(.data(Fixtures.sessionJSON()), .error(500, "verification details changed"), .data(renamed))
    await model.load()
    await #expect(throws: APIError.self) { try await model.saveName(first: "Ama", middle: "", last: "Mensah") }
    #expect(model.session?.firstName == "Akosua")
    #expect(transport.requests.count == 3)
}

@MainActor @Test func otherErrorsComeBackAsTheServersMessage() async {
    let (model, _, results) = makeModel()
    #expect(model.message(for: APIError.http(status: 400, message: "selfie is required")) == "selfie is required")
    #expect(results.all.isEmpty)
}

@MainActor @Test func pollingStopsOnAFinalStatus() async {
    let (model, transport, _) = makeModel(
        .data(Fixtures.sessionJSON(["case_id": "case-1", "case_status": "submitted", "consent_recorded": true])),
        .data(Fixtures.caseJSON(status: "submitted")),
        .error(502, "bad gateway"),
        .data(Fixtures.caseJSON(status: "approved"))
    )
    await model.load()
    await model.pollStatus(every: .zero)
    #expect(model.verificationCase?.status == "approved")
    #expect(model.statusError == nil)
    #expect(transport.requests.count == 4)
}

@MainActor @Test func closingOnStatusCompletesAndElsewhereCancels() async {
    let (onStatus, _, statusResults) = makeModel(.data(Fixtures.sessionJSON(["case_id": "case-1", "case_status": "approved", "consent_recorded": true])))
    await onStatus.load()
    onStatus.close()
    onStatus.close()
    #expect(statusResults.all == [.completed(caseId: "case-1", status: "approved")])

    let (onEntry, _, entryResults) = makeModel(.data(Fixtures.sessionJSON()))
    await onEntry.load()
    onEntry.close()
    #expect(entryResults.all == [.cancelled])
}

@MainActor @Test func reviewReadsTheCase() async throws {
    let (model, transport, _) = makeModel(.data(resumeSession()), .data(Fixtures.caseJSON(status: "documents_pending")))
    await model.load()
    try await model.loadCase()
    #expect(model.verificationCase?.status == "documents_pending")
    #expect(transport.requests[1].url?.path == "/api/verification/cases/case-1")
}
