import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

// MARK: Launch

@Test func startsAtConsentWithNoCase() {
    #expect(FlowRouting.launchRoute(Fixtures.session()) == .entry(.consent))
}

@Test func resumesAtTheChecklistOnceConsentIsRecorded() {
    let session = Fixtures.session(["case_id": "case-1", "case_status": "documents_pending", "consent_recorded": true])
    #expect(FlowRouting.launchRoute(session) == .entry(.checklist(caseId: "case-1")))
}

@Test func asksForConsentAgainWhenItDoesNotCoverTheCase() {
    let session = Fixtures.session(["case_id": "case-1", "case_status": "draft", "consent_recorded": false])
    #expect(FlowRouting.launchRoute(session) == .entry(.consent))
}

@Test func goesStraightToStatusOncePastIntake() {
    for status in ["submitted", "manual_review", "automated_review", "background_pending", "approved", "rejected"] {
        let session = Fixtures.session(["case_id": "case-1", "case_status": status, "consent_recorded": true])
        #expect(FlowRouting.launchRoute(session) == .status(caseId: "case-1"))
    }
}

@Test func treatsChangesRequestedAsIntake() {
    let session = Fixtures.session(["case_id": "case-1", "case_status": "changes_requested", "consent_recorded": true])
    #expect(FlowRouting.launchRoute(session) == .entry(.checklist(caseId: "case-1")))
}

// MARK: Mode

@Test func choosesTheNavigationMode() {
    #expect(FlowRouting.navigationMode(launchHadCase: false, caseStatus: "draft") == .firstRun)
    #expect(FlowRouting.navigationMode(launchHadCase: true, caseStatus: "draft") == .resume)
    #expect(FlowRouting.navigationMode(launchHadCase: false, caseStatus: "changes_requested") == .resume)
}

// MARK: Consent

@Test func consentsOnlyToWhatTheSessionRequires() {
    #expect(FlowRouting.consentScopes(Fixtures.session(["required_documents": ["government_id"], "required_checks": ["id_document"]])) == ["identity"])
    #expect(FlowRouting.consentScopes(Fixtures.session(["required_documents": ["government_id", "selfie"], "required_checks": ["id_document"]])) == ["identity", "biometric"])
    #expect(FlowRouting.consentScopes(Fixtures.session(["required_documents": ["government_id"], "required_checks": ["biometric_face_match"]])) == ["identity", "biometric"])
    #expect(FlowRouting.consentScopes(Fixtures.session(["required_documents": ["license_front", "selfie", "proof_of_address"], "required_checks": ["id_document", "biometric_liveness", "background_screening"]])) == ["identity", "biometric", "background"])
}

// MARK: Checklist Continue

// A function, not a global: `[String: Any]` is not Sendable, and Swift 6
// rejects a non-Sendable global.
private func docs(_ extra: [String: Any] = [:]) -> [String: Any] {
    ["required_documents": ["license_front", "license_back", "selfie"]].merging(extra) { $1 }
}

@Test func firstRunWithNothingCapturedStartsWithTheName() {
    let route = FlowRouting.checklistContinue(case: Fixtures.verificationCase(), session: Fixtures.session(docs()), mode: .firstRun)
    #expect(route == .yourName)
}

@Test func firstRunSkipsTheNameWhenTheProfileDoesNotCollectIt() {
    let route = FlowRouting.checklistContinue(case: Fixtures.verificationCase(), session: Fixtures.session(docs(["collect_name": false])), mode: .firstRun)
    #expect(route == .idDetails)
}

@Test func resumeAsksForAMissingNameFirst() {
    let session = Fixtures.session(docs(["case_id": "case-1", "identity_name_complete": false, "identity_details_complete": false]))
    #expect(FlowRouting.checklistContinue(case: Fixtures.verificationCase(), session: session, mode: .resume) == .yourName)
}

@Test func resumeAsksForMissingDetailsNext() {
    let session = Fixtures.session(docs(["case_id": "case-1", "identity_name_complete": true, "identity_details_complete": false, "first_name": "Ama", "last_name": "Mensah"]))
    #expect(FlowRouting.checklistContinue(case: Fixtures.verificationCase(), session: session, mode: .resume) == .idDetails)
}

@Test func resumeContinuesAtTheFirstMissingDocument() {
    let session = Fixtures.session(docs(["case_id": "case-1", "identity_name_complete": true, "identity_details_complete": true]))
    let c = Fixtures.verificationCase(documents: [Fixtures.document("license_front")])
    #expect(FlowRouting.checklistContinue(case: c, session: session, mode: .resume) == .documents(startAt: "license_back"))
}

@Test func resumeContinuesAtTheSelfie() {
    let session = Fixtures.session(docs(["case_id": "case-1", "identity_name_complete": true, "identity_details_complete": true]))
    let c = Fixtures.verificationCase(documents: [Fixtures.document("license_front"), Fixtures.document("license_back")])
    #expect(FlowRouting.checklistContinue(case: c, session: session, mode: .resume) == .selfie)
}

@Test func resumeContinuesAtProofOfAddressAfterTheSelfie() {
    let session = Fixtures.session(["required_documents": ["license_front", "selfie", "proof_of_address"], "case_id": "case-1", "identity_name_complete": true, "identity_details_complete": true])
    let c = Fixtures.verificationCase(documents: [Fixtures.document("license_front")] + ["left", "right", "center"].map { Fixtures.document("selfie", role: $0) })
    #expect(FlowRouting.checklistContinue(case: c, session: session, mode: .resume) == .proofOfAddress)
}

@Test func goesToReviewWhenEverythingIsCaptured() {
    let session = Fixtures.session(docs(["case_id": "case-1", "identity_name_complete": true, "identity_details_complete": true]))
    let c = Fixtures.verificationCase(documents: [Fixtures.document("license_front"), Fixtures.document("license_back"), Fixtures.document("selfie")])
    #expect(FlowRouting.checklistContinue(case: c, session: session, mode: .resume) == .review)
}

@Test func blocksContinueUntilAChangeRequestIsAddressed() {
    let complete = [Fixtures.document("license_front"), Fixtures.document("license_back"), Fixtures.document("selfie")]
    let c = Fixtures.verificationCase(status: "changes_requested", documents: complete)
    let unchanged = Fixtures.session(docs(["case_id": "case-1", "correction_applied": false]))
    #expect(FlowRouting.correctionNeeded(case: c, session: unchanged))
    #expect(FlowRouting.checklistContinue(case: c, session: unchanged, mode: .resume) == nil)

    let corrected = Fixtures.session(docs(["case_id": "case-1", "correction_applied": true, "identity_name_complete": true, "identity_details_complete": true]))
    #expect(!FlowRouting.correctionNeeded(case: c, session: corrected))
    #expect(FlowRouting.checklistContinue(case: c, session: corrected, mode: .resume) == .review)
}

@Test func aChangeRequestWithMissingEvidenceIsNotBlocked() {
    let c = Fixtures.verificationCase(status: "changes_requested", documents: [Fixtures.document("license_front")])
    #expect(!FlowRouting.correctionNeeded(case: c, session: Fixtures.session(docs())))
}

// MARK: Guards

@Test func guardsTheNameScreenWhenTheProfileSkipsIt() {
    #expect(FlowRouting.guarded(.yourName, session: Fixtures.session(["collect_name": false])) == .idDetails)
}

@Test func guardsIDDetailsUntilTheNameIsKnown() {
    #expect(FlowRouting.guarded(.idDetails, session: Fixtures.session(["first_name": "Ama"])) == .yourName)
    #expect(FlowRouting.guarded(.idDetails, session: Fixtures.session(["first_name": "Ama", "last_name": "Mensah"])) == .idDetails)
    #expect(FlowRouting.guarded(.idDetails, session: Fixtures.session(["collect_name": false])) == .idDetails)
}

@Test func guardsTheSelfieWhenNoneIsRequired() {
    #expect(FlowRouting.guarded(.selfie, session: Fixtures.session(["required_documents": ["government_id"]])) == .review)
}

// MARK: After a step

@Test func firstRunWalksTheScreensInOrder() {
    let session = Fixtures.session(["required_documents": ["license_front", "selfie", "proof_of_address"], "first_name": "Ama", "last_name": "Mensah"])
    #expect(FlowRouting.afterCompleting(.yourName, session: session, mode: .firstRun) == .idDetails)
    #expect(FlowRouting.afterCompleting(.idDetails, session: session, mode: .firstRun) == .documents(startAt: nil))
    #expect(FlowRouting.afterCompleting(.documents, session: session, mode: .firstRun) == .selfie)
    #expect(FlowRouting.afterCompleting(.selfie, session: session, mode: .firstRun) == .proofOfAddress)
    #expect(FlowRouting.afterCompleting(.proofOfAddress, session: session, mode: .firstRun) == .review)
    #expect(FlowRouting.afterCompleting(.review, session: session, mode: .firstRun) == .status)
}

@Test func firstRunWithoutASelfieGoesFromDocumentsToReview() {
    let session = Fixtures.session(["required_documents": ["government_id"], "collect_name": false])
    #expect(FlowRouting.afterCompleting(.documents, session: session, mode: .firstRun) == .review)
}

@Test func resumeReturnsToTheChecklistAfterEveryStep() {
    let session = Fixtures.session(["case_id": "case-1"])
    for screen in [FlowScreen.yourName, .idDetails, .documents, .selfie, .proofOfAddress] {
        #expect(FlowRouting.afterCompleting(screen, session: session, mode: .resume) == .checklist)
    }
    #expect(FlowRouting.afterCompleting(.review, session: session, mode: .resume) == .status)
}

// MARK: Status

@Test func keepsPollingUntilAFinalStatus() {
    for status in ["submitted", "in_review", "automated_review", "manual_review", "background_pending"] {
        #expect(FlowRouting.shouldKeepPolling(status: status))
    }
    for status in ["approved", "rejected", "closed", "changes_requested", "expired", "revoked"] {
        #expect(!FlowRouting.shouldKeepPolling(status: status))
    }
}
