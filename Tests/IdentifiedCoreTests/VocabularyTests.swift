import Testing
@testable import IdentifiedCore

@Test func consentVersionMatchesTheWebFlow() {
    // frontend/src/lib/consentApi.ts CONSENT_VERSION. Bump both together.
    #expect(ConsentVersion.current == "2026-09-04")
}

@Test func vocabularyMatchesTheBackendConstants() {
    #expect(DocType.governmentId == "government_id")
    #expect(DocType.licenseFront == "license_front")
    #expect(DocType.licenseBack == "license_back")
    #expect(DocType.selfie == "selfie")
    #expect(DocType.proofOfAddress == "proof_of_address")
    #expect(CheckType.backgroundScreening == "background_screening")
    #expect(CaseStatus.changesRequested == "changes_requested")
}
