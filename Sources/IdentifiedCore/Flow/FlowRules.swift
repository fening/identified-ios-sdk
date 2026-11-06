import Foundation

/// A numbered screen, as the progress bar counts them.
package enum FlowScreen: String, CaseIterable, Sendable {
    case yourName = "your-name"
    case idDetails = "id-details"
    case documents
    case selfie
    case proofOfAddress = "proof-of-address"
    case review
}

/// Documents runs twice for a screening profile: once before the selfie for
/// the ID, once after it for the proof of address.
package enum CapturePhase: Sendable {
    case documents
    case proofOfAddress
}

package struct ChecklistItem: Equatable, Sendable {
    package var key: String
    package var complete: Bool
}

package struct StepPosition: Equatable, Sendable {
    package var step: Int
    package var total: Int
}

/// A port of `frontend/src/lib/flow.ts`. Keep the two in step: a rule changed
/// here and not there makes the native and web flows disagree about what a
/// subject has left to do.
package enum FlowRules {
    /// A document counts when it is neither superseded nor rejected. A selfie
    /// captured as a named burst counts only once all three poses are present.
    package static func hasDocument(_ c: VerificationCase, _ key: String) -> Bool {
        let documents = c.documents.filter { $0.docType == key && $0.superseded != true && $0.status != "rejected" }
        if key == DocType.selfie, documents.contains(where: { SelfieRole.all.contains($0.captureRole ?? "") }) {
            return SelfieRole.all.allSatisfy { role in documents.contains { $0.captureRole == role } }
        }
        return !documents.isEmpty
    }

    package static func checklist(_ c: VerificationCase, requiredDocuments: [String]) -> [ChecklistItem] {
        requiredDocuments.map { ChecklistItem(key: $0, complete: hasDocument(c, $0)) }
    }

    package static func nextIncompleteStep(_ c: VerificationCase, requiredDocuments: [String]) -> String? {
        checklist(c, requiredDocuments: requiredDocuments).first { !$0.complete }?.key
    }

    /// Everything capturable on the spot first, the selfie next, proof of
    /// address last: it is the step that sends a subject off to find a file.
    package static func orderedCaptureSteps(_ requiredDocuments: [String]) -> [String] {
        let onTheSpot = requiredDocuments.filter { $0 != DocType.proofOfAddress && $0 != DocType.selfie }
        let selfie = requiredDocuments.filter { $0 == DocType.selfie }
        let proofOfAddress = requiredDocuments.filter { $0 == DocType.proofOfAddress }
        return onTheSpot + selfie + proofOfAddress
    }

    /// The steps the Documents screen captures itself, in order, for a phase.
    package static func documentSteps(_ requiredDocuments: [String], phase: CapturePhase) -> [String] {
        switch phase {
        case .proofOfAddress:
            return requiredDocuments.filter { $0 == DocType.proofOfAddress }
        case .documents:
            return orderedCaptureSteps(requiredDocuments).filter { $0 != DocType.selfie && $0 != DocType.proofOfAddress }
        }
    }

    /// Absent means yes: an SDK talking to an older backend keeps asking.
    package static func collectsName(_ session: HostedSession) -> Bool {
        session.collectName != false
    }

    package static func screens(requiredDocuments: [String], collectName: Bool) -> [FlowScreen] {
        var screens: [FlowScreen] = collectName ? [.yourName, .idDetails] : [.idDetails]
        if !documentSteps(requiredDocuments, phase: .documents).isEmpty { screens.append(.documents) }
        if requiredDocuments.contains(DocType.selfie) { screens.append(.selfie) }
        if requiredDocuments.contains(DocType.proofOfAddress) { screens.append(.proofOfAddress) }
        screens.append(.review)
        return screens
    }

    package static func position(of screen: FlowScreen, requiredDocuments: [String], collectName: Bool) -> StepPosition {
        let all = screens(requiredDocuments: requiredDocuments, collectName: collectName)
        let index = all.firstIndex(of: screen).map { $0 + 1 } ?? 1
        return StepPosition(step: index, total: all.count)
    }
}
