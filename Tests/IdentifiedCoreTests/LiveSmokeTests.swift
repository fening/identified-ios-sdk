import Foundation
import Testing
@testable import IdentifiedCore

private let environment = ProcessInfo.processInfo.environment
private let liveToken = environment["IDENTIFIED_LIVE_TOKEN"]
private let liveBaseURL = environment["IDENTIFIED_LIVE_BASE_URL"].flatMap(URL.init(string:))

/// Walks the first steps of a real session: launch, consent, case creation,
/// metadata, refetch and relaunch. Use mobile/scripts/local_backend_smoke.py.
@Suite(.enabled(if: liveToken != nil && liveBaseURL != nil, "set IDENTIFIED_LIVE_TOKEN and IDENTIFIED_LIVE_BASE_URL"))
struct LiveSmokeTests {
    @Test func walksTheOpeningOfARealSession() async throws {
        // This acceptance test accepts only the shared harness loopback gateway.
        try #require(liveBaseURL?.absoluteString == "http://127.0.0.1:8101")
        let api = APIClient(baseURL: liveBaseURL!, sessionToken: liveToken!)

        let first = try await Launch.load(using: api).get()
        #expect(first.route == .entry(.consent))
        #expect(first.mode == .firstRun)
        #expect(first.session.profileKey == "android_sdk_smoke")
        #expect(first.session.caseId == nil)
        #expect(FlowRouting.consentScopes(first.session) == ["identity", "biometric"])
        #expect(!first.session.requiredDocuments.isEmpty)

        try await api.recordConsent(scopes: FlowRouting.consentScopes(first.session))
        let created = try await api.getOrCreateCase(for: first.session)
        #expect(created.status == CaseStatus.draft)

        try await api.saveMetadata(.name(first: "Synthetic", middle: "", last: "SDK Test"))
        try await api.saveMetadata(.idDetails(
            dob: "1990-01-02", idType: "passport", idNumber: "SYNTHETIC123", idTypeDisplay: "Passport"
        ))
        let resumed = try await api.currentSession()
        #expect(resumed.caseId == created.id)
        #expect(resumed.firstName == "Synthetic")
        #expect(resumed.lastName == "SDK Test")
        #expect(resumed.identityDetailsComplete == true)
        #expect(resumed.idDetails?.dob == "1990-01-02")
        #expect(resumed.idDetails?.idType == "passport")
        #expect(resumed.idDetails?.idNumber == "SYNTHETIC123")

        let fetched = try await api.getCase(id: created.id)
        #expect(fetched.id == created.id)
        #expect(FlowRules.nextIncompleteStep(fetched, requiredDocuments: FlowRules.orderedCaptureSteps(first.session.requiredDocuments)) != nil)

        let again = try await Launch.load(using: api).get()
        #expect(again.route == .entry(.checklist(caseId: created.id)))
        #expect(again.mode == .resume)
    }
}
