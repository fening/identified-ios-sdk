#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `YourName.tsx`. Redirects to ID details when the profile does not collect
/// names; that guard lives in `FlowRouting.guarded`, so this screen is never
/// pushed in that case.
struct YourNameView: View {
    @EnvironmentObject private var flow: FlowModel
    @State private var first = ""
    @State private var middle = ""
    @State private var last = ""
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FlowScaffold(title: L10n.string("name.title"), subtitle: L10n.string("name.subtitle"), step: .yourName) {
            VStack(alignment: .leading, spacing: 16) {
                if let previous = previousName {
                    BodyText(L10n.format("name.previous", previous), secondary: true, size: 15)
                }
                FieldBox(label: L10n.string("name.first"), isFilled: !first.isEmpty) {
                    TextField("", text: $first).textContentType(.givenName).textInputAutocapitalization(.words).autocorrectionDisabled()
                }
                FieldBox(label: L10n.string("name.middle"), isFilled: !middle.isEmpty) {
                    TextField("", text: $middle).textContentType(.middleName).textInputAutocapitalization(.words).autocorrectionDisabled()
                }
                FieldBox(label: L10n.string("name.last"), isFilled: !last.isEmpty) {
                    TextField("", text: $last).textContentType(.familyName).textInputAutocapitalization(.words).autocorrectionDisabled()
                }
                if let error { ErrorText(message: error) }
            }
        } footer: {
            PrimaryButton(title: L10n.string("flow.continue"), busyTitle: L10n.string("flow.saving"), busy: busy) {
                Task { await save() }
            }
        }
        .onAppear(perform: prefill)
    }

    /// Shown when the session holds a full name but no first name: a name the
    /// integrator supplied in one piece, for the subject to split.
    private var previousName: String? {
        guard let session = flow.session, (session.firstName ?? "").isEmpty,
              let full = session.fullName, !full.isEmpty else { return nil }
        return full
    }

    private func prefill() {
        guard !loaded, let session = flow.session else { return }
        loaded = true
        first = session.firstName ?? ""
        middle = session.middleName ?? ""
        last = session.lastName ?? ""
    }

    private func save() async {
        error = nil
        switch NameInput.validate(first: first, middle: middle, last: last) {
        case .missing:
            error = L10n.string("name.missing")
            return
        case .tooLong:
            error = L10n.string("name.too_long")
            return
        case nil:
            break
        }
        busy = true
        defer { busy = false }
        do {
            try await flow.saveName(first: NameInput.normalise(first), middle: NameInput.normalise(middle), last: NameInput.normalise(last))
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("name.error")
        }
    }
}
#endif
