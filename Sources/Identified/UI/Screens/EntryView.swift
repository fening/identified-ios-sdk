#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Entry.tsx` once the link has checked out. There is no desktop handoff:
/// the SDK already runs on the phone.
struct EntryView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme

    var body: some View {
        let session = flow.session
        let brand = session?.branding?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.string("entry.brand_fallback")
        let duration = session?.requiredDocuments.contains(DocType.proofOfAddress) == true
            ? L10n.string("entry.duration_long") : L10n.string("entry.duration_short")
        FlowScaffold {
            VStack(spacing: 0) {
                IdentityHero().padding(.top, 8).padding(.bottom, 32)
                Text(L10n.string("entry.title"))
                    .font(theme.heading(30)).tracking(-0.5)
                    .foregroundStyle(theme.palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.format("entry.body", brand))
                    .font(theme.body(16)).foregroundStyle(theme.palette.textSecondary)
                    .lineSpacing(4).frame(maxWidth: 304).padding(.top, 12)
                Text(L10n.format("entry.small_print", duration))
                    .font(theme.body(13)).foregroundStyle(theme.palette.textSecondary)
                    .lineSpacing(4).padding(.top, 16)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        } footer: {
            PrimaryButton(title: session?.caseId == nil ? L10n.string("entry.begin") : L10n.string("entry.continue")) {
                flow.begin()
            }
        }
    }
}

/// The service could not be reached when the flow opened.
struct EntryUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        FlowScaffold(title: L10n.string("entry.unavailable.title"), subtitle: L10n.string("entry.unavailable.body")) {
            EmptyView()
        } footer: {
            PrimaryButton(title: L10n.string("entry.unavailable.retry"), action: retry)
        }
    }
}
#endif
