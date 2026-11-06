#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Consent.tsx`. Records consent with exactly the session's scopes, then
/// creates the case.
struct ConsentView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @State private var agreed = false
    @State private var busy = false
    @State private var error: String?
    @State private var showsTerms = false

    var body: some View {
        if let session = flow.session {
            FlowScaffold(title: L10n.string("consent.title"), subtitle: L10n.format("consent.subtitle", ConsentContent.brand(session)), showsLockup: false) {
                VStack(spacing: 12) {
                    ForEach(ConsentContent.sections(session)) { ConsentCard(section: $0) }
                    agreement(session).padding(16)
                        .background(theme.warmSurface, in: RoundedRectangle(cornerRadius: theme.radius))
                        .padding(.top, 8)
                    if let error { ErrorText(message: error) }
                }
            } footer: {
                PrimaryButton(title: L10n.string("consent.button"), busyTitle: L10n.string("consent.button_busy"), busy: busy, enabled: agreed) {
                    Task { await agree() }
                }
            }
            // A sheet does not reliably inherit environment objects on iOS 16.
            .sheet(isPresented: $showsTerms) { TermsView().environmentObject(flow).environment(\.theme, theme) }
        }
    }

    private func agreement(_ session: HostedSession) -> some View {
        var text = AttributedString(L10n.string("consent.agree.prefix"))
        var terms = AttributedString(L10n.string("consent.agree.terms"))
        terms.link = URL(string: "identified-sdk://terms")
        terms.underlineStyle = .single
        text += terms
        text += AttributedString(L10n.format("consent.agree.suffix", ConsentContent.agreedData(session)))
        return HStack(alignment: .top, spacing: 12) {
            Button { agreed.toggle() } label: {
                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(-12)
                    .foregroundStyle(agreed ? theme.palette.accent : theme.palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("consent.agree.checkbox"))
            .accessibilityAddTraits(agreed ? .isSelected : [])
            Text(text)
                .font(theme.body(14))
                .lineSpacing(4)
                .foregroundStyle(theme.palette.textPrimary)
                .tint(theme.palette.accent)
                .environment(\.openURL, OpenURLAction { _ in
                    showsTerms = true
                    return .handled
                })
        }
    }

    private func agree() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await flow.consent()
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("consent.error")
        }
    }
}

private struct ConsentCard: View {
    let section: ConsentSection
    @State private var expanded = false
    @Environment(\.theme) private var theme

    var body: some View {
        Card {
            Text(section.title).font(theme.heading(15, weight: .medium)).foregroundStyle(theme.palette.textPrimary)
            BodyText(section.body, secondary: true, size: 14).lineSpacing(4)
            if expanded {
                Divider().overlay(theme.palette.border)
                ForEach(section.more, id: \.self) { BodyText($0, secondary: true, size: 13).lineSpacing(4) }
            }
            Button { expanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text(expanded ? L10n.string("consent.show_less") : L10n.string("consent.learn_more")).underline()
                    Image(systemName: "chevron.down").font(.system(size: 10)).rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(theme.body(13, weight: .medium)).foregroundStyle(theme.palette.textSecondary)
                .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                .padding(.vertical, -12)
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(expanded ? L10n.string("consent.show_less") : L10n.string("consent.learn_more")))
        }
    }
}
#endif
