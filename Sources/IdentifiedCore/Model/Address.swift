import Foundation

/// A resolved GhanaPostGPS digital address (`frontend/src/lib/ghanapost.ts`).
package struct DigitalAddress: Decodable, Equatable, Sendable {
    package var code: String
    package var latitude: Double
    package var longitude: Double
    package var area: String?
    package var district: String?
    package var region: String?
    package var postCode: String?
    package var street: String?

    package init(code: String, latitude: Double, longitude: Double, area: String? = nil, district: String? = nil,
                 region: String? = nil, postCode: String? = nil, street: String? = nil) {
        self.code = code
        self.latitude = latitude
        self.longitude = longitude
        self.area = area
        self.district = district
        self.region = region
        self.postCode = postCode
        self.street = street
    }

}

/// How the subject arrived at the stated address. There is no map pin on
/// native, so `pin` is never sent; it exists so a value from the web decodes.
package enum AddressSource: String, Codable, Equatable, Sendable {
    case typed
    case pin
    case currentLocation = "current_location"
}

/// The address the subject states before photographing a proof of address.
package struct StatedAddress: Encodable, Equatable, Sendable {
    package var code: String
    package var area: String?
    package var district: String?
    package var region: String?
    package var source: AddressSource

    package init(code: String, area: String? = nil, district: String? = nil, region: String? = nil, source: AddressSource) {
        self.code = code
        self.area = area
        self.district = district
        self.region = region
        self.source = source
    }
}
