import Foundation

/// A `PATCH /api/v1/sessions/metadata` body. The server merges the keys
/// shallowly into the session's metadata.
package enum MetadataPatch: Encodable, Equatable, Sendable {
    case name(first: String, middle: String, last: String)
    case idDetails(dob: String, idType: String, idNumber: String, idTypeDisplay: String)
    case statedAddress(StatedAddress)
    case reportDelivery(optIn: Bool, email: String)

    private enum Outer: String, CodingKey { case metadata }

    private enum Keys: String, CodingKey {
        case firstName = "first_name"
        case middleName = "middle_name"
        case lastName = "last_name"
        case dob
        case idType = "id_type"
        case idTypeOther = "id_type_other"
        case idNumber = "id_number"
        case idTypeDisplay = "id_type_display"
        case statedAddress = "stated_address"
        case reportEmailOptIn = "report_email_opt_in"
        case reportEmail = "report_email"
    }

    package func encode(to encoder: Encoder) throws {
        var outer = encoder.container(keyedBy: Outer.self)
        var body = outer.nestedContainer(keyedBy: Keys.self, forKey: .metadata)
        switch self {
        case let .name(first, middle, last):
            try body.encode(first, forKey: .firstName)
            try body.encode(middle, forKey: .middleName)
            try body.encode(last, forKey: .lastName)
        case let .idDetails(dob, idType, idNumber, idTypeDisplay):
            try body.encode(dob, forKey: .dob)
            try body.encode(idType, forKey: .idType)
            // The web always sends an empty "other" type; the catalogue has no
            // free-text option, and the server stores what it is given.
            try body.encode("", forKey: .idTypeOther)
            try body.encode(idNumber, forKey: .idNumber)
            try body.encode(idTypeDisplay, forKey: .idTypeDisplay)
        case let .statedAddress(address):
            try body.encode(address, forKey: .statedAddress)
        case let .reportDelivery(optIn, email):
            try body.encode(optIn, forKey: .reportEmailOptIn)
            try body.encode(email, forKey: .reportEmail)
        }
    }
}

extension JSONEncoder {
    /// The encoder for every request body. Keys are spelled out by each body;
    /// sorted output keeps tests and logs stable.
    package static var identified: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
