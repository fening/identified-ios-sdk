import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

private func check(_ type: String, status: String = "completed", result: Any? = nil) -> [String: Any] {
    var check: [String: Any] = ["check_type": type, "status": status]
    if let result { check["result_json"] = String(decoding: Fixtures.data(result), as: UTF8.self) }
    return check
}

private func summary(_ status: String, checks: [[String: Any]] = [], notes: String? = nil) -> StatusSummary {
    var overrides: [String: Any] = ["checks": checks]
    if let notes { overrides["review_notes"] = notes }
    return StatusRules.summary(Fixtures.verificationCase(status: status, overrides: overrides))
}

@Test func approvalSaysFullyVerifiedOnlyWithScreening() {
    #expect(summary("approved").kind == .verified)
    #expect(summary("approved", checks: [check("background_screening")]).kind == .fullyVerified)
    #expect(summary("approved").tone == .success)
}

@Test func backgroundPendingAndManualReviewWinOverPendingScreenings() {
    let pending = check("background_screening", status: "pending")
    #expect(summary("background_pending", checks: [pending]).kind == .backgroundPending)
    #expect(summary("manual_review", checks: [pending]).kind == .manualReview)
    #expect(summary("submitted", checks: [pending]).kind == .backgroundInProgress)
}

@Test func pendingScreeningsAreCountedFromTheReport() {
    let report = ["background": ["status": "in_progress", "screenings": [["status": "pending"], ["status": "awaiting_subject"], ["status": "clear"]]]]
    let c = Fixtures.verificationCase(status: "submitted", overrides: ["checks": [check("background_screening", result: report)]])
    #expect(StatusRules.backgroundProgress(c) == BackgroundProgress(pending: true, count: 2))
    #expect(StatusRules.backgroundProgress(Fixtures.verificationCase()) == BackgroundProgress(pending: false, count: 0))
}

@Test func everyOtherStatusUsesTheMapThenTheFallback() {
    #expect(summary("rejected").kind == .notApproved)
    #expect(summary("rejected").tone == .failure)
    #expect(summary("changes_requested").kind == .changesRequested)
    #expect(summary("changes_requested").tone == .attention)
    #expect(summary("expired").kind == .pending)
    #expect(summary("revoked").kind == .pending)
    #expect(summary("in_review").kind == .inReview)
}

@Test func manualReviewExplainsTheFirstIssue() {
    let mismatch = check("id_document", result: ["selected_id_type": "passport", "detected_id_type": "national_id", "data_mismatch": "x"])
    #expect(summary("manual_review", checks: [mismatch]).reviewIssue == .typeMismatch(selected: "Passport", detected: "Ghana Card"))
    let name = check("id_document", result: ["name_comparison": ["status": "needs_review"]])
    #expect(summary("manual_review", checks: [name]).reviewIssue == .nameNeedsConfirmation)
    let number = check("id_document", result: ["data_mismatch": "GHA-1 vs GHA-2"])
    #expect(summary("manual_review", checks: [number]).reviewIssue == .numberNeedsConfirmation)
    #expect(summary("submitted", checks: [number]).reviewIssue == nil)
}

@Test func reviewerNotesShowOnlyWhenChangesAreRequested() {
    #expect(summary("changes_requested", notes: "Retake the back").reviewerNote == "Retake the back")
    #expect(summary("approved", notes: "ok").reviewerNote == nil)
}
