import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

private let docs = ["government_id", "license_front", "license_back", "selfie"]

@Test func asksForProofOfAddressLastEvenWhenTheProfileListsItFirst() {
    #expect(FlowRules.orderedCaptureSteps(["proof_of_address", "government_id", "selfie"]) == ["government_id", "selfie", "proof_of_address"])
}

@Test func putsTheSelfieBeforeProofOfAddress() {
    #expect(FlowRules.orderedCaptureSteps(["license_front", "proof_of_address", "license_back", "selfie"])
        == ["license_front", "license_back", "selfie", "proof_of_address"])
}

@Test func leavesAnOrderWithoutProofOfAddressUntouched() {
    #expect(FlowRules.orderedCaptureSteps(["government_id", "selfie"]) == ["government_id", "selfie"])
}

@Test func documentsPhaseCapturesNeitherSelfieNorProofOfAddress() {
    #expect(FlowRules.documentSteps(["proof_of_address", "government_id", "selfie"], phase: .documents) == ["government_id"])
}

@Test func proofOfAddressPhaseCapturesOnlyProofOfAddress() {
    #expect(FlowRules.documentSteps(["proof_of_address", "government_id", "selfie"], phase: .proofOfAddress) == ["proof_of_address"])
    #expect(FlowRules.documentSteps(["government_id", "selfie"], phase: .proofOfAddress) == [])
}

@Test func marksEveryItemIncompleteForAnEmptyCase() {
    let items = FlowRules.checklist(Fixtures.verificationCase(), requiredDocuments: docs)
    #expect(items.map(\.key) == docs)
    #expect(items.allSatisfy { !$0.complete })
}

@Test func marksAnItemCompleteWhenItsDocumentExists() {
    let c = Fixtures.verificationCase(documents: [Fixtures.document("selfie")])
    #expect(FlowRules.checklist(c, requiredDocuments: docs).first { $0.key == "selfie" }?.complete == true)
}

@Test func returnsTheFirstIncompleteStepOrNil() {
    #expect(FlowRules.nextIncompleteStep(Fixtures.verificationCase(), requiredDocuments: docs) == "government_id")
    let full = Fixtures.verificationCase(documents: docs.map { Fixtures.document($0) })
    #expect(FlowRules.nextIncompleteStep(full, requiredDocuments: docs) == nil)
}

@Test func doesNotTreatRejectedOrSupersededEvidenceAsDone() {
    let rejected = Fixtures.verificationCase(documents: [Fixtures.document("proof_of_address", status: "rejected")])
    #expect(FlowRules.nextIncompleteStep(rejected, requiredDocuments: ["proof_of_address"]) == "proof_of_address")
    let superseded = Fixtures.verificationCase(documents: [Fixtures.document("license_front", superseded: true)])
    #expect(FlowRules.nextIncompleteStep(superseded, requiredDocuments: ["license_front"]) == "license_front")
}

@Test func asksForTheSelfieAgainWhenOnlyPartOfTheBurstUploaded() {
    let partial = Fixtures.verificationCase(documents: [Fixtures.document("selfie", role: "left")])
    #expect(FlowRules.nextIncompleteStep(partial, requiredDocuments: ["selfie"]) == "selfie")
    let full = Fixtures.verificationCase(documents: ["left", "right", "center"].map { Fixtures.document("selfie", role: $0) })
    #expect(FlowRules.nextIncompleteStep(full, requiredDocuments: ["selfie"]) == nil)
}

@Test func opensWithYourNameWhenTheProfileCollectsIt() {
    #expect(FlowRules.screens(requiredDocuments: ["license_front", "selfie"], collectName: true) == [.yourName, .idDetails, .documents, .selfie, .review])
}

@Test func dropsYourNameWhenTheProfileDoesNot() {
    #expect(FlowRules.screens(requiredDocuments: ["license_front", "selfie"], collectName: false) == [.idDetails, .documents, .selfie, .review])
}

@Test func addsProofOfAddressAfterTheSelfie() {
    #expect(FlowRules.screens(requiredDocuments: ["license_front", "selfie", "proof_of_address"], collectName: true)
        == [.yourName, .idDetails, .documents, .selfie, .proofOfAddress, .review])
}

@Test func skipsDocumentsWhenOnlyProofOfAddressIsRequired() {
    #expect(FlowRules.screens(requiredDocuments: ["proof_of_address"], collectName: false) == [.idDetails, .proofOfAddress, .review])
}

@Test func renumbersTheRemainingScreens() {
    #expect(FlowRules.position(of: .idDetails, requiredDocuments: ["license_front", "selfie"], collectName: true) == StepPosition(step: 2, total: 5))
    #expect(FlowRules.position(of: .idDetails, requiredDocuments: ["license_front", "selfie"], collectName: false) == StepPosition(step: 1, total: 4))
}

@Test func treatsAnAbsentCollectNameAsCollecting() {
    var json = Fixtures.sessionJSON()
    json.removeValue(forKey: "collect_name")
    #expect(FlowRules.collectsName(try! JSONDecoder.identified.decode(HostedSession.self, from: Fixtures.data(json))))
    #expect(FlowRules.collectsName(Fixtures.session(["collect_name": false])) == false)
}
