import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func decodesAHostedSession() throws {
    let session = Fixtures.session([
        "case_id": "case-1",
        "case_status": "changes_requested",
        "first_name": "Ama",
        "last_name": "Mensah",
        "id_details": ["dob": "1990-01-02", "id_type": "national_id", "id_number": "GHA-123456789-0"],
        "allowed_id_types": ["national_id"],
        "proof_of_address_policy": [
            "accepted_types": [["key": "utility_bill", "label": "Utility bill", "hint": "ECG or Ghana Water"]],
            "max_age_days": 90,
            "accepted_formats": ["image/jpeg", "application/pdf"],
            "max_size_bytes": 8_388_608,
        ],
    ])
    #expect(session.id == "sess-1")
    #expect(session.subjectRef == "driver-42")
    #expect(session.requiredDocuments == ["license_front", "license_back", "selfie"])
    #expect(session.collectName == true)
    #expect(session.allowedIdTypes == ["national_id"])
    #expect(session.branding?.displayName == "Acme")
    #expect(session.caseId == "case-1")
    #expect(session.caseStatus == "changes_requested")
    #expect(session.firstName == "Ama")
    #expect(session.idDetails?.idNumber == "GHA-123456789-0")
    #expect(session.proofOfAddressPolicy?.acceptedTypes.first?.label == "Utility bill")
    #expect(session.proofOfAddressPolicy?.maxSizeBytes == 8_388_608)
}

@Test func decodesNullArraysAsEmpty() {
    let session = Fixtures.session(["required_documents": NSNull(), "allowed_id_types": NSNull()])
    #expect(session.requiredDocuments == [])
    #expect(session.allowedIdTypes == [])
}

@Test func decodesMissingArraysAndFlagsAsAbsent() {
    var json = Fixtures.sessionJSON()
    json.removeValue(forKey: "required_checks")
    json.removeValue(forKey: "collect_name")
    let session = try! JSONDecoder.identified.decode(HostedSession.self, from: Fixtures.data(json))
    #expect(session.requiredChecks == [])
    #expect(session.collectName == nil)
}

@Test func decodesACaseWithDocumentsAndChecks() {
    let c = Fixtures.verificationCase(
        status: "manual_review",
        documents: [Fixtures.document("selfie", role: "center"), Fixtures.document("license_front", superseded: true)],
        overrides: [
            "review_notes": "Retake the back",
            "checks": [["id": "chk", "case_id": "case-1", "check_type": "id_document", "status": "needs_review", "result_json": "{\"data_mismatch\":true}"]],
        ]
    )
    #expect(c.status == "manual_review")
    #expect(c.reviewNotes == "Retake the back")
    #expect(c.documents.count == 2)
    #expect(c.documents[0].captureRole == "center")
    #expect(c.documents[1].superseded == true)
    #expect(c.checks.first?.checkType == "id_document")
    #expect(c.checks.first?.resultJson == "{\"data_mismatch\":true}")
}

@Test func decodesACaseWithNoDocumentsKey() {
    var json = Fixtures.caseJSON()
    json.removeValue(forKey: "documents")
    let c = try! JSONDecoder.identified.decode(VerificationCase.self, from: Fixtures.data(json))
    #expect(c.documents == [])
    #expect(c.checks == [])
}

@Test func decodesADigitalAddress() throws {
    let json: [String: Any] = ["code": "GA1839124", "latitude": 5.6, "longitude": -0.18, "area": "Osu", "district": "Accra Metropolitan", "region": "Greater Accra", "post_code": "GA183"]
    let address = try JSONDecoder.identified.decode(DigitalAddress.self, from: Fixtures.data(json))
    #expect(address.code == "GA1839124")
    #expect(address.postCode == "GA183")
    #expect(address.street == nil)
}
