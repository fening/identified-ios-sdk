import Foundation

/// `frontend/src/pages/Review.tsx`.
package enum ReviewInput {
    package static func isValidEmail(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil
    }
}
