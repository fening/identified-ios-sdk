import Testing
@testable import Identified
import IdentifiedTestSupport

@Test func aStandardProfileGetsTheBiometricSectionButNotScreening() {
    let sections = ConsentContent.sections(Fixtures.session())
    #expect(sections.map(\.title) == [
        "What we collect", "Biometric data", "Human review", "How it’s used", "Data protection", "Retention", "Your rights",
    ])
    #expect(sections[0].body == "Front of ID, Back of ID, Biometric selfie, a short liveness check (turning your head), and the details you enter.")
    #expect(sections[5].body == "Your ID images and selfies are deleted a year after the check finishes, and the rest of the record after five years, unless deleted sooner.")
    #expect(sections[5].more == [
        "Until the images are deleted, they are kept with the case so the result can be explained or challenged. After that, only the details read from your documents and the decision remain.",
        "Acme can have Identified delete everything about you sooner, for example when you close your account with them. Acme may also keep its own copy of the result under its own policy; ask Acme about that.",
        "A verification you start but do not finish is deleted after 30 days.",
    ])
    #expect(sections[6].more == [
        "You can ask Acme for a copy of what was collected, ask for it to be corrected or deleted, or withdraw your consent.",
        "Identified holds your data for Acme, so a request to delete it goes to Acme, which decides and has Identified erase it. If you can sign in to the Identified verification portal, you can send that request from there.",
        "Withdrawing consent stops further processing. It does not undo a check that has already run, or a result already sent.",
        "Contact Acme to exercise any of these. If you are not satisfied, you can go to your country’s data-protection authority.",
    ])
}

@Test func aScreeningProfileAddsScreeningAndItsExtraParagraphs() {
    let session = Fixtures.session([
        "required_documents": ["license_front", "selfie", "proof_of_address"],
        "required_checks": ["id_document", "background_screening"],
    ])
    let sections = ConsentContent.sections(session)
    #expect(sections.map(\.title).contains("Background screening"))
    #expect(sections[0].more.count == 3)
    #expect(sections.first { $0.title == "How it’s used" }?.body == "Only to verify your identity and background for Acme. The result of the check is shared with Acme.")
}

@Test func withNoDocumentsTheCollectionIsJustTheDetails() {
    let session = Fixtures.session(["required_documents": [String](), "required_checks": ["id_document"], "branding": ["display_name": ""]])
    let sections = ConsentContent.sections(session)
    #expect(sections[0].body == "The details you enter.")
    #expect(sections.first { $0.title == "Retention" }?.more[1] == "This business can have Identified delete everything about you sooner, for example when you close your account with them. This business may also keep its own copy of the result under its own policy; ask this business about that.")
}

@Test func theAgreementNamesTheDataBeingConsentedTo() {
    #expect(ConsentContent.agreedData(Fixtures.session(["required_documents": [String](), "required_checks": ["id_document"]])) == "identity data")
    #expect(ConsentContent.agreedData(Fixtures.session()) == "identity and biometric data")
    #expect(ConsentContent.agreedData(Fixtures.session(["required_checks": ["background_screening"]])) == "identity, biometric and background screening data")
}
