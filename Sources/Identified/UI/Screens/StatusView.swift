#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Status.tsx`: polls the case every 5 s until it is final. "Done" ends the
/// flow with `completed`; a change request goes back to the checklist.
struct StatusView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme

    var body: some View {
        FlowScaffold {
            if let current = flow.verificationCase {
                content(current, summary: StatusRules.summary(current))
            } else if let error = flow.statusError {
                ErrorText(message: error)
            } else {
                LoadingView(text: L10n.string("status.loading"), showsHeader: false).frame(height: 200)
            }
        } footer: {
            if flow.verificationCase?.status == CaseStatus.changesRequested {
                PrimaryButton(title: L10n.string("status.resubmit")) { flow.resubmit() }
            } else {
                PrimaryButton(title: L10n.string("flow.done")) { flow.close() }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task { await flow.pollStatus() }
    }

    @ViewBuilder
    private func content(_ current: VerificationCase, summary: StatusSummary) -> some View {
        let (title, body) = copy(summary.kind)
        VStack(spacing: 0) {
            badge(summary.tone).padding(.bottom, 28)
            Text(title).font(theme.heading(30)).foregroundStyle(theme.palette.textPrimary).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(body).font(theme.body(16)).foregroundStyle(theme.palette.textSecondary)
                .lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 304).padding(.top, 12)
            if let error = flow.statusError { ErrorText(message: error) }
            if summary.background.pending {
                identityCard(current.status)
                progressCard(
                    title: summary.background.count == 0 ? L10n.string("status.screening.none")
                        : summary.background.count == 1 ? L10n.format("status.screening.one", summary.background.count)
                        : L10n.format("status.screening.many", summary.background.count),
                    badge: L10n.string("status.badge.in_progress"),
                    note: L10n.string("status.screening.note")
                )
            } else if current.status == CaseStatus.automatedReview {
                progressCard(title: L10n.string("status.auto.title"), badge: L10n.string("status.badge.live"), note: L10n.string("status.auto.note"))
            }
            if let note = summary.reviewerNote {
                (Text(L10n.string("status.note")).bold() + Text(" " + note))
                    .font(theme.body(15)).foregroundStyle(theme.palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(theme.palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: theme.radius))
                    .padding(.top, 20)
            }
            if let issue = summary.reviewIssue { reason(issue) }
            (Text(L10n.string("status.case_id")) + Text(current.id).font(.system(.footnote, design: .monospaced)))
                .font(theme.body(12)).foregroundStyle(theme.palette.textSecondary)
                .padding(.top, 24)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func copy(_ kind: StatusKind) -> (String, String) {
        switch kind {
        case .fullyVerified: (L10n.string("status.fully_verified.title"), L10n.string("status.fully_verified.body"))
        case .verified: (L10n.string("status.verified.title"), L10n.string("status.verified.body"))
        case .notApproved: (L10n.string("status.not_approved.title"), L10n.string("status.not_approved.body"))
        case .closed: (L10n.string("status.closed.title"), L10n.string("status.closed.body"))
        case .automatedReview: (L10n.string("status.automated.title"), L10n.string("status.automated.body"))
        case .manualReview: (L10n.string("status.manual.title"), L10n.string("status.manual.body"))
        case .backgroundPending: (L10n.string("status.background_pending.title"), L10n.string("status.background_pending.body"))
        case .inReview: (L10n.string("status.in_review.title"), L10n.string("status.in_review.body"))
        case .submitted: (L10n.string("status.submitted.title"), L10n.string("status.submitted.body"))
        case .changesRequested: (L10n.string("status.changes.title"), L10n.string("status.changes.body"))
        case .backgroundInProgress: (L10n.string("status.background.title"), L10n.string("status.background.body"))
        case .pending: (L10n.string("status.pending.title"), L10n.string("status.pending.body"))
        }
    }

    private func badge(_ tone: StatusTone) -> some View {
        let (symbol, color): (String, Color) = switch tone {
        case .success: ("checkmark", theme.palette.success)
        case .failure: ("xmark", theme.palette.error)
        case .attention: ("exclamationmark", theme.palette.warning)
        case .waiting: ("clock", theme.palette.textSecondary)
        }
        return ZStack {
            Circle().fill(tone == .waiting ? theme.lilacBadge : color.opacity(0.14))
            if tone == .waiting {
                Path { path in
                    path.move(to: CGPoint(x: 44, y: 35))
                    path.addLine(to: CGPoint(x: 44, y: 44))
                    path.addLine(to: CGPoint(x: 49.5, y: 47.7))
                }
                .stroke(theme.palette.textPrimary, style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
            } else {
                Image(systemName: symbol).font(.system(size: 36, weight: .regular)).foregroundStyle(color)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityHidden(true)
    }

    private func identityCard(_ status: String) -> some View {
        let verified = status == CaseStatus.backgroundPending || status == CaseStatus.approved
        let review = status == CaseStatus.manualReview
        return progressCard(
            title: L10n.string("status.identity.title"),
            subtitle: verified ? L10n.string("status.identity.done") : review ? L10n.string("status.identity.review") : L10n.string("status.identity.running"),
            badge: verified ? L10n.string("status.badge.verified") : review ? L10n.string("status.badge.needs_review") : L10n.string("status.badge.in_progress"),
            note: nil
        )
    }

    private func progressCard(title: String, subtitle: String = L10n.string("status.auto.updates"), badge: String, note: String?) -> some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(theme.body(14, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                    Text(subtitle).font(theme.body(12)).foregroundStyle(theme.palette.textSecondary)
                }
                Spacer()
                Text(badge.uppercased()).font(theme.body(10, weight: .semibold)).tracking(1)
                    .foregroundStyle(theme.palette.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(theme.palette.success.opacity(0.12), in: Capsule())
            }
            if let note {
                Divider().overlay(theme.palette.border)
                BodyText(note, secondary: true, size: 12).lineSpacing(4)
            }
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func reason(_ issue: ReviewIssue) -> some View {
        Card {
            Text(L10n.string("status.reason.eyebrow").uppercased()).font(theme.body(11, weight: .medium)).tracking(1.3).foregroundStyle(theme.palette.textSecondary)
            switch issue {
            case let .typeMismatch(selected, detected):
                Text(L10n.string("status.reason.mismatch.title")).font(theme.heading(18)).foregroundStyle(theme.palette.textPrimary)
                HStack {
                    VStack(alignment: .leading) { Text(L10n.string("status.reason.selected")).font(theme.body(12)); Text(selected).bold() }
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                    VStack(alignment: .leading) { Text(L10n.string("status.reason.detected")).font(theme.body(12)); Text(detected).bold() }
                }
                .foregroundStyle(theme.palette.textPrimary)
                BodyText(L10n.string("status.reason.mismatch.message"), secondary: true, size: 14)
            case .nameNeedsConfirmation:
                Text(L10n.string("status.reason.name.title")).font(theme.heading(18)).foregroundStyle(theme.palette.textPrimary)
                BodyText(L10n.string("status.reason.name.message"), secondary: true, size: 14)
            case .numberNeedsConfirmation:
                Text(L10n.string("status.reason.number.title")).font(theme.heading(18)).foregroundStyle(theme.palette.textPrimary)
                BodyText(L10n.string("status.reason.number.message"), secondary: true, size: 14)
            }
        }
        // Same 24pt gap the progress cards use. Without it the card's border sat on the
        // paragraph's last line, which read as that line being clipped.
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
    }
}
#endif
