import IdentifiedCore

/// `DOC_LABELS` in `frontend/src/lib/flow.ts`. An unknown type shows its key,
/// as on the web.
enum DocLabel {
    static func text(_ docType: String) -> String {
        switch docType {
        case DocType.governmentId: L10n.string("doc.government_id")
        case DocType.licenseFront: L10n.string("doc.license_front")
        case DocType.licenseBack: L10n.string("doc.license_back")
        case DocType.selfie: L10n.string("doc.selfie")
        case DocType.proofOfAddress: L10n.string("doc.proof_of_address")
        default: docType
        }
    }
}
