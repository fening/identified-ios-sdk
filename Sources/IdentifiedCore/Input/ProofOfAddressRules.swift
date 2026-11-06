import Foundation

/// The requirement text and page rules from
/// `frontend/src/components/ProofOfAddressCapture.tsx`.
package enum ProofOfAddressRules {
    package static let maxPages = 4

    package enum FormatName: Equatable, Sendable {
        case photo, pdf
    }

    /// Formats as a subject names them: three image types are one answer to
    /// "will my photo work". Duplicates collapse, first-seen order kept.
    package static func formatNames(_ mimeTypes: [String]) -> [FormatName] {
        var names: [FormatName] = []
        for type in mimeTypes {
            let name: FormatName = type == "application/pdf" ? .pdf : .photo
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    package static func months(_ days: Int) -> Int {
        Int((Double(days) / 30).rounded())
    }

    package static func megabytes(_ bytes: Int) -> Int {
        bytes / (1024 * 1024)
    }

    /// Page 1 is judged as the document; later pages are extra evidence.
    package static func captureRole(forPage page: Int) -> String? {
        page <= 1 ? nil : "page_\(page)"
    }
}
