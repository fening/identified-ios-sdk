import Foundation

/// GhanaPostGPS codes, ported from `frontend/src/lib/ghanapost.ts`.
package enum DigitalAddressCode {
    private static let pattern = #"^[A-Z]{2}-?\d{3,4}-?\d{4}$"#

    /// Checked as written, before hyphens are stripped: "GA-183-9124-5"
    /// collapses to two letters and eight digits, which would otherwise pass.
    package static func isValid(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .range(of: pattern, options: .regularExpression) != nil
    }

    /// Upper case, no hyphens; empty when the code is not valid.
    package static func storageForm(_ code: String) -> String {
        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return isValid(raw) ? raw.replacingOccurrences(of: "-", with: "") : ""
    }

    /// GA-183-9124.
    package static func displayForm(_ code: String) -> String {
        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "-", with: "")
        guard raw.count >= 9, raw.count <= 10, raw.prefix(2).allSatisfy(\.isLetter), raw.dropFirst(2).allSatisfy(\.isNumber) else {
            return code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let digits = raw.dropFirst(2)
        return "\(raw.prefix(2))-\(digits.dropLast(4))-\(digits.suffix(4))"
    }

    /// Applied on every keystroke: two letters, then up to eight digits,
    /// hyphenated as they arrive. A digit typed first cannot occupy the prefix.
    package static func mask(_ input: String) -> String {
        let cleaned = input.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let letters = String(cleaned.prefix(2).filter(\.isLetter))
        let digits = letters.count == 2 ? String(cleaned.dropFirst(2).filter(\.isNumber).prefix(8)) : ""
        guard !digits.isEmpty else { return letters }
        let areaLength = digits.count > 7 ? 4 : 3
        let area = digits.prefix(areaLength)
        let location = digits.dropFirst(areaLength)
        return location.isEmpty ? "\(letters)-\(area)" : "\(letters)-\(area)-\(location)"
    }

    /// "Ofankor · Ga North · Greater Accra": the subject confirms a place, not
    /// a code, because a mistyped code points somewhere else in Ghana.
    package static func describe(_ address: DigitalAddress) -> String {
        [address.area, address.district, address.region]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
