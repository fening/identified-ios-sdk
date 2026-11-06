import Foundation

package struct IDTypeOption: Equatable, Sendable {
    package var key: String
    package var label: String
}

/// `frontend/src/pages/IdDetails.tsx` and `lib/extractedIdentity.ts`.
package enum IDDetailsInput {
    package static let nationalID = "national_id"

    package static let catalogue = [
        IDTypeOption(key: nationalID, label: "Ghana Card"),
        IDTypeOption(key: "passport", label: "Passport"),
        IDTypeOption(key: "drivers_license", label: "Driver's License"),
    ]

    package enum Problem: Equatable, Sendable {
        case missingDateOfBirth
        case missingType
        case invalidGhanaCard
    }

    /// The catalogue in its own order, limited to the profile's allowed types.
    /// An empty list allows everything.
    package static func options(allowed: [String]) -> [IDTypeOption] {
        allowed.isEmpty ? catalogue : catalogue.filter { allowed.contains($0.key) }
    }

    /// The display label sent as `id_type_display`.
    package static func label(for key: String) -> String {
        catalogue.first { $0.key == key }?.label
            ?? key.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    package static func isValidGhanaCard(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^GHA-\d{9}-[0-9A-Za-z]$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The web's checks, in its order. An empty number is not checked here:
    /// the screen keeps Continue disabled until there is one, as the web's
    /// `required` attribute does.
    package static func validate(dob: Date?, idType: String?, idNumber: String) -> Problem? {
        if dob == nil { return .missingDateOfBirth }
        guard let idType, !idType.isEmpty else { return .missingType }
        if idType == nationalID && !isValidGhanaCard(idNumber) { return .invalidGhanaCard }
        return nil
    }

    /// `YYYY-MM-DD` for the calendar day the subject picked, in their time zone.
    package static func dobString(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    package static func date(fromDOB value: String) -> Date? {
        let pieces = value.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }
}
