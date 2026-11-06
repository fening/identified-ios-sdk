import Testing
@testable import Identified

@Test func documentsAreLabelledAsTheWebLabelsThem() {
    #expect(DocLabel.text("license_front") == "Front of ID")
    #expect(DocLabel.text("selfie") == "Biometric selfie")
    #expect(DocLabel.text("utility_bill") == "utility_bill")
}
