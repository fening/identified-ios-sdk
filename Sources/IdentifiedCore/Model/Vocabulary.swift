import Foundation

/// The consent wording version recorded with every consent. Mirrors
/// `CONSENT_VERSION` in `frontend/src/lib/consentApi.ts`: when the consent copy
/// changes on any platform, bump it on web, iOS and Android together.
package enum ConsentVersion {
    package static let current = "2026-09-04"
}

/// `model.DocType*` on the backend.
package enum DocType {
    package static let governmentId = "government_id"
    package static let licenseFront = "license_front"
    package static let licenseBack = "license_back"
    package static let selfie = "selfie"
    package static let proofOfAddress = "proof_of_address"
}

/// `model.CheckType*` on the backend.
package enum CheckType {
    package static let idDocument = "id_document"
    package static let biometricLiveness = "biometric_liveness"
    package static let biometricFaceMatch = "biometric_face_match"
    package static let backgroundScreening = "background_screening"
}

/// `model.CaseStatus*` on the backend.
package enum CaseStatus {
    package static let draft = "draft"
    package static let intakeInProgress = "intake_in_progress"
    package static let documentsPending = "documents_pending"
    package static let biometricPending = "biometric_pending"
    package static let submitted = "submitted"
    package static let inReview = "in_review"
    package static let automatedReview = "automated_review"
    package static let backgroundPending = "background_pending"
    package static let manualReview = "manual_review"
    package static let changesRequested = "changes_requested"
    package static let approved = "approved"
    package static let rejected = "rejected"
    package static let closed = "closed"
    package static let expired = "expired"
    package static let revoked = "revoked"
}

/// The three frames of the selfie turn challenge.
package enum SelfieRole {
    package static let center = "center"
    package static let left = "left"
    package static let right = "right"
    package static let all: Set<String> = [center, left, right]
}
