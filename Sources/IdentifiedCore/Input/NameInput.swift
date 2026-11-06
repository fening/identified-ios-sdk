import Foundation

/// `frontend/src/pages/YourName.tsx`: trimmed, inner whitespace collapsed,
/// first and last required, at most 256 code points in all.
package enum NameInput {
    package static let maxLength = 256

    package enum Problem: Equatable, Sendable {
        case missing
        case tooLong
    }

    package static func normalise(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    package static func validate(first: String, middle: String, last: String) -> Problem? {
        let parts = [first, middle, last].map(normalise)
        if parts[0].isEmpty || parts[2].isEmpty { return .missing }
        let full = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return full.unicodeScalars.count > maxLength ? .tooLong : nil
    }
}
