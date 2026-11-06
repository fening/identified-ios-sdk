#if os(iOS)
import SwiftUI
import UIKit

/// A text field that rewrites each edit through `mask` before it is shown.
/// SwiftUI's `TextField` cannot do this reliably: a value changed in its
/// binding is not redisplayed, and one changed in `onChange` drops keystrokes
/// typed quickly. The caret goes to the end after every edit, which suits
/// short codes.
struct MaskedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let mask: (String) -> String
    @Environment(\.theme) private var theme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.textColor = UIColor(theme.palette.textPrimary)
        field.font = theme.appearance.fontFamily.flatMap { UIFont(name: $0, size: 17) } ?? .systemFont(ofSize: 17)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MaskedTextField

        init(_ parent: MaskedTextField) {
            self.parent = parent
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = field.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let masked = parent.mask(current.replacingCharacters(in: swiftRange, with: string))
            field.text = masked
            parent.text = masked
            return false
        }
    }
}
#endif
