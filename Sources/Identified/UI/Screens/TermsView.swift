#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Terms.tsx`, in a sheet over Consent.
struct TermsView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let brand = flow.session?.branding?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.string("terms.brand_fallback")
        let clauses: [(String, [String])] = [
            (L10n.string("terms.1.title"), [L10n.string("terms.1.p1"), L10n.format("terms.1.p2", brand), L10n.string("terms.1.p3")]),
            (L10n.string("terms.2.title"), [L10n.string("terms.2.p1"), L10n.string("terms.2.p2"), L10n.string("terms.2.p3")]),
            (L10n.string("terms.3.title"), [L10n.string("terms.3.p1"), L10n.string("terms.3.p2"), L10n.string("terms.3.p3")]),
            (L10n.string("terms.4.title"), [L10n.string("terms.4.p1"), L10n.string("terms.4.p2"), L10n.string("terms.4.p3")]),
            (L10n.string("terms.5.title"), [L10n.string("terms.5.p1"), L10n.string("terms.5.p2"), L10n.string("terms.5.p3"), L10n.string("terms.5.p4")]),
            (L10n.string("terms.6.title"), [L10n.string("terms.6.p1"), L10n.string("terms.6.p2")]),
            (L10n.string("terms.7.title"), [
                L10n.string("terms.7.p1"), L10n.string("terms.7.p2"),
                L10n.format("terms.7.p3", ConsentVersion.current), L10n.string("terms.7.p4"),
            ]),
        ]
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.string("terms.title")).font(theme.heading()).foregroundStyle(theme.palette.textPrimary)
                    ForEach(clauses, id: \.0) { clause in
                        Text(clause.0).font(theme.heading(18)).foregroundStyle(theme.palette.textPrimary).padding(.top, 8)
                        ForEach(clause.1, id: \.self) { BodyText($0, secondary: true, size: 15).textSelection(.enabled) }
                    }
                }
                .padding(20)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("flow.done")) { dismiss() }.foregroundStyle(theme.palette.accent)
                }
            }
        }
    }
}
#endif
