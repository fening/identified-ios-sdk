import IdentifiedCore

struct ConsentSection: Equatable, Identifiable {
    let title: String
    let body: String
    let more: [String]
    var id: String { title }
}

/// The sections of `Consent.tsx`, built from what this session collects.
enum ConsentContent {
    static func brand(_ session: HostedSession) -> String {
        session.branding?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.string("consent.brand_fallback")
    }

    static func sections(_ session: HostedSession) -> [ConsentSection] {
        let brand = brand(session)
        // Opens a sentence, so "this business" becomes "This business" (the web leaves it lowercase).
        let sentenceBrand = brand.prefix(1).uppercased() + brand.dropFirst()
        let flags = Flags(session)
        var sections: [ConsentSection] = []

        let labels = session.requiredDocuments.map(DocLabel.text).joined(separator: ", ")
        let collected = labels.isEmpty
            ? L10n.string("consent.collect.none")
            : labels + (flags.biometric ? L10n.string("consent.collect.liveness") : "") + L10n.string("consent.collect.tail")
        sections.append(ConsentSection(
            title: L10n.string("consent.collect.title"),
            body: collected,
            more: [L10n.string("consent.collect.more1"), L10n.string("consent.collect.more2")]
                + (flags.proofOfAddress ? [L10n.string("consent.collect.more3")] : [])
        ))

        if flags.biometric {
            sections.append(ConsentSection(
                title: L10n.string("consent.biometric.title"),
                body: L10n.string("consent.biometric.body"),
                more: [L10n.string("consent.biometric.more1"), L10n.string("consent.biometric.more2"), L10n.string("consent.biometric.more3")]
            ))
        }

        if flags.background {
            sections.append(ConsentSection(
                title: L10n.string("consent.background.title"),
                body: L10n.string("consent.background.body"),
                more: [
                    L10n.string("consent.background.more1"), L10n.string("consent.background.more2"),
                    L10n.string("consent.background.more3"), L10n.string("consent.background.more4"),
                    L10n.string("consent.background.more5"),
                ]
            ))
        }

        sections.append(ConsentSection(
            title: L10n.string("consent.review.title"),
            body: L10n.string("consent.review.body"),
            more: [L10n.string("consent.review.more1"), L10n.string("consent.review.more2")]
                + (flags.background ? [L10n.string("consent.review.more3")] : [])
                + [L10n.format("consent.review.more4", brand)]
        ))

        let andBackground = flags.background ? L10n.string("consent.use.and_background") : ""
        sections.append(ConsentSection(
            title: L10n.string("consent.use.title"),
            body: L10n.format("consent.use.body", andBackground, brand, brand),
            more: [L10n.format("consent.use.more1", brand), L10n.string("consent.use.more2"), L10n.string("consent.use.more3")]
        ))

        sections.append(ConsentSection(
            title: L10n.string("consent.protection.title"),
            body: L10n.string("consent.protection.body"),
            more: [
                L10n.string("consent.protection.more1"), L10n.string("consent.protection.more2"),
                L10n.string("consent.protection.more3"), L10n.string("consent.protection.more4"),
            ]
        ))

        sections.append(ConsentSection(
            title: L10n.string("consent.retention.title"),
            body: L10n.string("consent.retention.body"),
            more: [
                L10n.string("consent.retention.more1"),
                L10n.format("consent.retention.more2", sentenceBrand, sentenceBrand, brand),
                L10n.string("consent.retention.more3"),
            ]
        ))

        sections.append(ConsentSection(
            title: L10n.string("consent.rights.title"),
            body: L10n.string("consent.rights.body"),
            more: [
                L10n.format("consent.rights.more1", brand), L10n.format("consent.rights.more2", brand, brand),
                L10n.string("consent.rights.more3"), L10n.format("consent.rights.more4", brand),
            ]
        ))
        return sections
    }

    /// "identity and biometric data", for the agreement line.
    static func agreedData(_ session: HostedSession) -> String {
        let flags = Flags(session)
        let items = [L10n.string("consent.data.identity")]
            + (flags.biometric ? [L10n.string("consent.data.biometric")] : [])
            + (flags.background ? [L10n.string("consent.data.background")] : [])
        guard let last = items.last, items.count > 1 else { return L10n.format("consent.data.one", items[0]) }
        return L10n.format("consent.data.many", items.dropLast().joined(separator: ", "), last)
    }

    private struct Flags {
        let biometric: Bool
        let background: Bool
        let proofOfAddress: Bool

        init(_ session: HostedSession) {
            let scopes = FlowRouting.consentScopes(session)
            biometric = scopes.contains("biometric")
            background = scopes.contains("background")
            proofOfAddress = session.requiredDocuments.contains(DocType.proofOfAddress)
        }
    }
}
