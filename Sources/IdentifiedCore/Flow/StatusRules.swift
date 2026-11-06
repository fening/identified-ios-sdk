import Foundation

package enum StatusKind: Equatable, Sendable {
    case fullyVerified, verified, notApproved, closed, automatedReview, manualReview
    case backgroundPending, inReview, submitted, changesRequested, backgroundInProgress, pending
}

/// The status badge: teal check, red cross, amber mark, or a clock.
package enum StatusTone: Equatable, Sendable {
    case success, failure, attention, waiting
}

/// `getApplicantReviewIssue`: an applicant-safe reason for manual review. Raw
/// mismatch strings can hold full ID numbers and are never shown.
package enum ReviewIssue: Equatable, Sendable {
    case typeMismatch(selected: String, detected: String)
    case nameNeedsConfirmation
    case numberNeedsConfirmation
}

package struct BackgroundProgress: Equatable, Sendable {
    package var pending: Bool
    package var count: Int
}

package struct StatusSummary: Equatable, Sendable {
    package var kind: StatusKind
    package var tone: StatusTone
    package var background: BackgroundProgress
    package var reviewIssue: ReviewIssue?
    package var reviewerNote: String?
}

/// A port of the copy selection in `frontend/src/pages/Status.tsx`.
package enum StatusRules {
    package static func summary(_ c: VerificationCase) -> StatusSummary {
        let background = backgroundProgress(c)
        let kind: StatusKind
        // background_pending before the generic screening message: there the
        // identity result is already final and the subject should hear it.
        switch c.status {
        case CaseStatus.backgroundPending: kind = .backgroundPending
        case CaseStatus.manualReview: kind = .manualReview
        default:
            kind = background.pending ? .backgroundInProgress : mapped(c)
        }
        let tone: StatusTone = switch c.status {
        case CaseStatus.approved: .success
        case CaseStatus.rejected: .failure
        case CaseStatus.changesRequested: .attention
        default: .waiting
        }
        let notes = c.reviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return StatusSummary(
            kind: kind,
            tone: tone,
            background: background,
            reviewIssue: c.status == CaseStatus.manualReview ? reviewIssue(c) : nil,
            reviewerNote: c.status == CaseStatus.changesRequested && notes?.isEmpty == false ? notes : nil
        )
    }

    /// `frontend/src/lib/backgroundProgress.ts`.
    package static func backgroundProgress(_ c: VerificationCase) -> BackgroundProgress {
        guard let check = c.checks.first(where: { $0.checkType == CheckType.backgroundScreening }) else {
            return BackgroundProgress(pending: false, count: 0)
        }
        let background = json(check.resultJson)?["background"] as? [String: Any]
        let screenings = background?["screenings"] as? [Any] ?? []
        let count = screenings.filter {
            let status = ($0 as? [String: Any])?["status"] as? String
            return status == "pending" || status == "awaiting_subject"
        }.count
        let reportPending = background?["status"] as? String == "pending"
        return BackgroundProgress(pending: count > 0 || reportPending || check.status == "pending", count: count)
    }

    package static func reviewIssue(_ c: VerificationCase) -> ReviewIssue? {
        guard let parsed = json(c.checks.first { $0.checkType == CheckType.idDocument }?.resultJson) else { return nil }
        let selected = parsed["selected_id_type"] as? String ?? ""
        let detected = parsed["detected_id_type"] as? String ?? ""
        if !selected.isEmpty, !detected.isEmpty, selected != detected {
            return .typeMismatch(selected: IDDetailsInput.label(for: selected), detected: IDDetailsInput.label(for: detected))
        }
        let nameStatus = (parsed["name_comparison"] as? [String: Any])?["status"] as? String
        if nameStatus == "needs_review" || nameStatus == "unavailable" { return .nameNeedsConfirmation }
        if let mismatch = parsed["data_mismatch"] as? String, !mismatch.trimmingCharacters(in: .whitespaces).isEmpty {
            return .numberNeedsConfirmation
        }
        return nil
    }

    private static func mapped(_ c: VerificationCase) -> StatusKind {
        switch c.status {
        case CaseStatus.approved:
            return c.checks.contains { $0.checkType == CheckType.backgroundScreening } ? .fullyVerified : .verified
        case CaseStatus.rejected: return .notApproved
        case CaseStatus.closed: return .closed
        case CaseStatus.automatedReview: return .automatedReview
        case CaseStatus.inReview: return .inReview
        case CaseStatus.submitted: return .submitted
        case CaseStatus.changesRequested: return .changesRequested
        default: return .pending
        }
    }

    private static func json(_ text: String?) -> [String: Any]? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
