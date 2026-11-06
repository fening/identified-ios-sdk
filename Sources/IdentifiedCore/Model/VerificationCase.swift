import Foundation

/// `model.VerificationCase`, as `GET /api/verification/cases/:id` returns it.
package struct VerificationCase: Decodable, Equatable, Sendable {
    package var id: String
    package var status: String
    package var reviewNotes: String?
    @DefaultEmpty package var requiredDocuments: [String]
    @DefaultEmpty package var requiredChecks: [String]
    @DefaultEmpty package var documents: [VerificationDocument]
    @DefaultEmpty package var checks: [VerificationCheck]
    package var identityOutcome: String?
    package var backgroundOutcome: String?
    package var submittedAt: String?
}

/// `model.IdentityDocument`. `superseded` is computed by the server on read.
package struct VerificationDocument: Decodable, Equatable, Sendable {
    package var id: String?
    package var docType: String
    package var captureRole: String?
    package var fileUrl: String?
    package var status: String?
    package var superseded: Bool?
}

/// `model.VerificationCheck`. `resultJson` is a JSON document in a string.
package struct VerificationCheck: Decodable, Equatable, Sendable {
    package var checkType: String
    package var status: String
    package var provider: String?
    package var resultJson: String?
}

/// `POST /api/verification/cases/:id/submit` data.
package struct SubmitResult: Decodable, Equatable, Sendable {
    package var caseId: String
    package var status: String
    package var readyForReview: Bool?
    package var closureReason: String?

    package init(caseId: String, status: String, readyForReview: Bool?, closureReason: String?) {
        self.caseId = caseId
        self.status = status
        self.readyForReview = readyForReview
        self.closureReason = closureReason
    }
}
