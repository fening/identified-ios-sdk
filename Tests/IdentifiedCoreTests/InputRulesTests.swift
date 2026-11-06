import Foundation
import Testing
@testable import IdentifiedCore

// MARK: Name (YourName.tsx)

@Test func namesCollapseWhitespace() {
    #expect(NameInput.normalise("  Ama \t  Serwaa  ") == "Ama Serwaa")
}

@Test func firstAndLastNamesAreRequired() {
    #expect(NameInput.validate(first: " ", middle: "", last: "Mensah") == .missing)
    #expect(NameInput.validate(first: "Ama", middle: "", last: "") == .missing)
    #expect(NameInput.validate(first: "Ama", middle: "", last: "Mensah") == nil)
}

@Test func theFullNameIsCappedAt256CodePoints() {
    let first = String(repeating: "a", count: 200)
    #expect(NameInput.validate(first: first, middle: "", last: String(repeating: "b", count: 55)) == nil) // 200 + 1 + 55
    #expect(NameInput.validate(first: first, middle: "", last: String(repeating: "b", count: 56)) == .tooLong)
}

// MARK: ID details (IdDetails.tsx)

@Test func allowedTypesFilterTheCatalogueInItsOrder() {
    #expect(IDDetailsInput.options(allowed: []).map(\.key) == ["national_id", "passport", "drivers_license"])
    #expect(IDDetailsInput.options(allowed: ["drivers_license", "national_id"]).map(\.key) == ["national_id", "drivers_license"])
}

@Test func unknownTypesGetATitleCasedLabel() {
    #expect(IDDetailsInput.label(for: "national_id") == "Ghana Card")
    #expect(IDDetailsInput.label(for: "voter_card") == "Voter Card")
}

@Test func ghanaCardNumbersAreCheckedTrimmedAndCaseInsensitively() {
    #expect(IDDetailsInput.isValidGhanaCard(" gha-123456789-x "))
    #expect(!IDDetailsInput.isValidGhanaCard("GHA-12345678-1"))
    #expect(!IDDetailsInput.isValidGhanaCard("GHA123456789-1"))
}

@Test func idDetailsProblemsComeInTheWebsOrder() {
    let dob = Date(timeIntervalSince1970: 0)
    #expect(IDDetailsInput.validate(dob: nil, idType: nil, idNumber: "") == .missingDateOfBirth)
    #expect(IDDetailsInput.validate(dob: dob, idType: nil, idNumber: "") == .missingType)
    #expect(IDDetailsInput.validate(dob: dob, idType: "national_id", idNumber: "123") == .invalidGhanaCard)
    #expect(IDDetailsInput.validate(dob: dob, idType: "passport", idNumber: "G1234567") == nil)
}

@Test func datesOfBirthRoundTripAsCalendarDates() throws {
    let date = try #require(IDDetailsInput.date(fromDOB: "1990-01-05"))
    #expect(IDDetailsInput.dobString(date) == "1990-01-05")
    #expect(IDDetailsInput.date(fromDOB: "") == nil)
}

// MARK: Digital address (ghanapost.ts)

@Test func theMaskInsertsHyphensAsDigitsArrive() {
    #expect(DigitalAddressCode.mask("ga1839124") == "GA-183-9124")
    #expect(DigitalAddressCode.mask("GA-1839") == "GA-183-9")
    #expect(DigitalAddressCode.mask("ga12345678") == "GA-1234-5678")
    #expect(DigitalAddressCode.mask("GA 183 9124 99") == "GA-1839-1249")
    #expect(DigitalAddressCode.mask("1GA") == "G")
    #expect(DigitalAddressCode.mask("g") == "G")
}

@Test func validityIsCheckedAsWritten() {
    #expect(DigitalAddressCode.isValid("GA-183-9124"))
    #expect(DigitalAddressCode.isValid("ga1839124"))
    #expect(!DigitalAddressCode.isValid("GA-183-9124-5"))
    #expect(!DigitalAddressCode.isValid("GA-18-9124"))
}

@Test func codesAreStoredWithoutHyphensAndShownWithThem() {
    #expect(DigitalAddressCode.storageForm(" ga-183-9124 ") == "GA1839124")
    #expect(DigitalAddressCode.storageForm("nope") == "")
    #expect(DigitalAddressCode.displayForm("GA1839124") == "GA-183-9124")
}

@Test func aPlaceIsDescribedFromItsNonEmptyParts() {
    let address = DigitalAddress(code: "GA1839124", latitude: 5.6, longitude: -0.2, area: "Ofankor", district: " ", region: "Greater Accra")
    #expect(DigitalAddressCode.describe(address) == "Ofankor · Greater Accra")
}

// MARK: Review (Review.tsx)

@Test func reportEmailsNeedAnAtAndADot() {
    #expect(ReviewInput.isValidEmail(" ama@example.com "))
    #expect(!ReviewInput.isValidEmail("ama@example"))
    #expect(!ReviewInput.isValidEmail("ama example.com"))
}

// MARK: Proof of address (ProofOfAddressCapture.tsx)

@Test func formatsAreNamedAsASubjectWouldNameThem() {
    #expect(ProofOfAddressRules.formatNames(["image/jpeg", "image/png", "application/pdf"]) == [.photo, .pdf])
    #expect(ProofOfAddressRules.formatNames([]) == [])
}

@Test func ageAndSizeAreRounded() {
    #expect(ProofOfAddressRules.months(90) == 3)
    #expect(ProofOfAddressRules.megabytes(8 * 1024 * 1024 + 5) == 8)
}

@Test func pagesAfterTheFirstCarryARole() {
    #expect(ProofOfAddressRules.captureRole(forPage: 1) == nil)
    #expect(ProofOfAddressRules.captureRole(forPage: 2) == "page_2")
    #expect(ProofOfAddressRules.maxPages == 4)
}
