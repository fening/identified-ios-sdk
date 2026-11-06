#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Checklist.tsx`. No back button: it is the hub every resumed step returns to.
struct ChecklistView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        FlowScaffold(title: L10n.string("checklist.title"), subtitle: L10n.string("checklist.subtitle")) {
            if loading && flow.verificationCase == nil {
                LoadingView(text: L10n.string("checklist.loading"), showsHeader: false).frame(height: 160)
            } else if let error, flow.verificationCase == nil {
                VStack(alignment: .leading, spacing: 12) {
                    ErrorText(message: error)
                    SecondaryButton(title: L10n.string("checklist.retry")) { Task { await load() } }
                }
            } else if let session = flow.session, let current = flow.verificationCase {
                content(session: session, current: current)
            }
        } footer: {
            PrimaryButton(title: L10n.string("flow.continue"), enabled: canContinue) {
                flow.continueFromChecklist()
            }
        }
        .navigationBarBackButtonHidden(true)
        .task { await load() }
    }

    private var canContinue: Bool {
        guard !loading, let session = flow.session, let current = flow.verificationCase else { return false }
        return !FlowRouting.correctionNeeded(case: current, session: session)
    }

    @ViewBuilder
    private func content(session: HostedSession, current: VerificationCase) -> some View {
        let changesRequested = current.status == CaseStatus.changesRequested
        let items = FlowRules.checklist(current, requiredDocuments: FlowRules.orderedCaptureSteps(session.requiredDocuments))
        VStack(alignment: .leading, spacing: 12) {
            if changesRequested {
                Card {
                    Text(L10n.string("checklist.changes.title")).font(theme.heading(17)).foregroundStyle(theme.palette.warning)
                    BodyText(current.reviewNotes.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.string("checklist.changes.body"), size: 15)
                    HStack(spacing: 18) {
                        if FlowRules.collectsName(session) {
                            LinkButton(title: L10n.string("checklist.changes.name")) { flow.open(.yourName) }
                        }
                        LinkButton(title: L10n.string("checklist.changes.details")) { flow.open(.idDetails) }
                    }
                }
            }
            ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
                ChecklistRow(number: index + 1, item: item, replaceable: changesRequested && item.complete) {
                    flow.replace(item.key)
                }
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await flow.refreshForChecklist()
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("checklist.error")
        }
    }
}

private struct ChecklistRow: View {
    let number: Int
    let item: ChecklistItem
    let replaceable: Bool
    let replace: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(item.complete ? theme.palette.success.opacity(0.14) : theme.palette.border).frame(width: 44, height: 44)
                    if item.complete {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.palette.success)
                    } else {
                        Text("\(number)").font(theme.body(15, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                    }
                }
                .accessibilityHidden(true)
                Text(DocLabel.text(item.key)).font(theme.body(16, weight: .medium)).foregroundStyle(theme.palette.textPrimary)
                Spacer()
                Text(item.complete ? L10n.string("checklist.done") : L10n.string("checklist.required"))
                    .font(theme.body(13, weight: .medium))
                    .foregroundStyle(item.complete ? theme.palette.success : theme.palette.textSecondary)
            }
            if replaceable {
                LinkButton(title: L10n.format("checklist.replace", DocLabel.text(item.key)), action: replace)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
