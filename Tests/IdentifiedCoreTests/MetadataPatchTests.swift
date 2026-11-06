import Foundation
import Testing
@testable import IdentifiedCore

private func json(_ patch: MetadataPatch) throws -> String {
    String(decoding: try JSONEncoder.identified.encode(patch), as: UTF8.self)
}

@Test func encodesTheName() throws {
    #expect(try json(.name(first: "Ama", middle: "", last: "Mensah"))
        == #"{"metadata":{"first_name":"Ama","last_name":"Mensah","middle_name":""}}"#)
}

@Test func encodesIDDetailsWithAnEmptyOtherType() throws {
    #expect(try json(.idDetails(dob: "1990-01-02", idType: "national_id", idNumber: "GHA-123456789-0", idTypeDisplay: "Ghana Card"))
        == #"{"metadata":{"dob":"1990-01-02","id_number":"GHA-123456789-0","id_type":"national_id","id_type_display":"Ghana Card","id_type_other":""}}"#)
}

@Test func encodesAStatedAddressWithoutAbsentParts() throws {
    let address = StatedAddress(code: "GA1839124", area: "Osu", source: .currentLocation)
    #expect(try json(.statedAddress(address))
        == #"{"metadata":{"stated_address":{"area":"Osu","code":"GA1839124","source":"current_location"}}}"#)
}

@Test func encodesReportDelivery() throws {
    #expect(try json(.reportDelivery(optIn: true, email: "ama@example.com"))
        == #"{"metadata":{"report_email":"ama@example.com","report_email_opt_in":true}}"#)
}
