import Foundation

/// `GET /api/v1/sessions/current`. Only the fields the flow reads.
///
/// Flags the backend always sends are still optional: the web treats an absent
/// `collect_name` as "collect", and the same tolerance keeps an SDK in the field
/// working against a backend that predates a field.
package struct HostedSession: Decodable, Equatable, Sendable {
    package struct Branding: Decodable, Equatable, Sendable {
        package var displayName: String?
        package var primaryColor: String?
    }

    package struct IDDetails: Decodable, Equatable, Sendable {
        package var dob: String?
        package var idType: String?
        package var idNumber: String?
    }

    package var id: String
    package var subjectRef: String
    package var subjectId: String?
    package var profileKey: String
    package var status: String
    package var expiresAt: String?
    @DefaultEmpty package var requiredDocuments: [String]
    @DefaultEmpty package var requiredChecks: [String]
    package var collectName: Bool?
    @DefaultEmpty package var allowedIdTypes: [String]
    package var reportEmailOptIn: Bool?
    package var reportEmail: String?
    package var branding: Branding?
    package var proofOfAddressPolicy: ProofOfAddressPolicy?
    package var firstName: String?
    package var middleName: String?
    package var lastName: String?
    package var fullName: String?
    package var correctionApplied: Bool?
    package var caseId: String?
    package var caseStatus: String?
    package var consentRecorded: Bool?
    package var identityNameComplete: Bool?
    package var identityDetailsComplete: Bool?
    package var idDetails: IDDetails?
}

/// `service.ProofOfAddressPolicy`: what counts as a valid proof of address.
package struct ProofOfAddressPolicy: Decodable, Equatable, Sendable {
    package struct AcceptedType: Decodable, Equatable, Sendable {
        package var key: String
        package var label: String
        package var hint: String?
    }

    @DefaultEmpty package var acceptedTypes: [AcceptedType]
    package var maxAgeDays: Int
    @DefaultEmpty package var acceptedFormats: [String]
    package var maxSizeBytes: Int
}

extension ProofOfAddressPolicy {
    package init(acceptedTypes: [AcceptedType], maxAgeDays: Int, acceptedFormats: [String], maxSizeBytes: Int) {
        _acceptedTypes = DefaultEmpty(wrappedValue: acceptedTypes)
        self.maxAgeDays = maxAgeDays
        _acceptedFormats = DefaultEmpty(wrappedValue: acceptedFormats)
        self.maxSizeBytes = maxSizeBytes
    }

    /// The backend's limits (`service/proof_of_address.go`), for a session from
    /// a backend that does not send a policy. No types are listed: the screen
    /// then shows only the age, format and size lines.
    package static let standard = ProofOfAddressPolicy(
        acceptedTypes: [], maxAgeDays: 90,
        acceptedFormats: ["image/jpeg", "image/png", "image/webp", "application/pdf"],
        maxSizeBytes: 8 * 1024 * 1024
    )
}
