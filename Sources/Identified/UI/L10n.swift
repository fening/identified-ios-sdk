import Foundation

/// The flow's copy, from `Resources/en.lproj/Localizable.strings`. Keys are
/// `screen.element`; values are the web flow's text, word for word, so a
/// translation is a new `.lproj`, not a code change.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}
