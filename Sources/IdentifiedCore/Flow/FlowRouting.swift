import Foundation

package enum NavigationMode: Equatable, Sendable {
    /// Each screen leads to the next one.
    case firstRun
    /// Each screen returns to the checklist after saving.
    case resume
}

package enum EntryDestination: Equatable, Sendable {
    case consent
    case checklist(caseId: String)
}

package enum LaunchRoute: Equatable, Sendable {
    /// Show the entry screen; its button goes to the destination.
    case entry(EntryDestination)
    /// The case is past intake: show its status.
    case status(caseId: String)
}

package enum Destination: Equatable, Sendable {
    case yourName
    case idDetails
    /// `startAt` nil means the first document step.
    case documents(startAt: String?)
    case selfie
    case proofOfAddress
    case review
    case checklist
    case status
}

/// The web flow's routing, from `Entry.tsx`, `Consent.tsx`, `Checklist.tsx`,
/// the page guards and `Status.tsx`.
package enum FlowRouting {
    /// Statuses in which the subject can still change their evidence
    /// (`frontend/src/lib/mobileHandoff.ts`, `repository/lifecycle.go`).
    package static let intakeStatuses: Set<String> = [
        CaseStatus.draft, CaseStatus.intakeInProgress, CaseStatus.documentsPending,
        CaseStatus.biometricPending, CaseStatus.changesRequested,
    ]

    /// Statuses after which the status screen stops polling (`Status.tsx`).
    package static let finalStatuses: Set<String> = [
        CaseStatus.approved, CaseStatus.rejected, CaseStatus.closed,
        CaseStatus.changesRequested, CaseStatus.expired, CaseStatus.revoked,
    ]

    package static func launchRoute(_ session: HostedSession) -> LaunchRoute {
        if let caseId = session.caseId, let status = session.caseStatus, !intakeStatuses.contains(status) {
            return .status(caseId: caseId)
        }
        if let caseId = session.caseId, session.consentRecorded == true {
            return .entry(.checklist(caseId: caseId))
        }
        return .entry(.consent)
    }

    package static func navigationMode(launchHadCase: Bool, caseStatus: String?) -> NavigationMode {
        launchHadCase || caseStatus == CaseStatus.changesRequested ? .resume : .firstRun
    }

    /// Exactly the scopes this session requires and no more: the backend's
    /// consent gate reads them to decide whether screening may run.
    package static func consentScopes(_ session: HostedSession) -> [String] {
        let checks = session.requiredChecks
        let biometric = session.requiredDocuments.contains(DocType.selfie)
            || checks.contains(CheckType.biometricLiveness)
            || checks.contains(CheckType.biometricFaceMatch)
        let background = checks.contains(CheckType.backgroundScreening)
        return ["identity"] + (biometric ? ["biometric"] : []) + (background ? ["background"] : [])
    }

    /// A change request whose evidence is all present still needs a change to
    /// the subject's details before it can be resubmitted.
    package static func correctionNeeded(case c: VerificationCase, session: HostedSession) -> Bool {
        guard c.status == CaseStatus.changesRequested else { return false }
        let steps = FlowRules.orderedCaptureSteps(session.requiredDocuments)
        return FlowRules.checklist(c, requiredDocuments: steps).allSatisfy(\.complete) && session.correctionApplied != true
    }

    /// Where the checklist's Continue button goes, or nil while it is disabled.
    package static func checklistContinue(case c: VerificationCase, session: HostedSession, mode: NavigationMode) -> Destination? {
        if correctionNeeded(case: c, session: session) { return nil }
        let steps = FlowRules.orderedCaptureSteps(session.requiredDocuments)
        let items = FlowRules.checklist(c, requiredDocuments: steps)
        let resuming = mode == .resume

        if resuming && session.identityNameComplete == false { return guarded(.yourName, session: session) }
        if resuming && session.identityDetailsComplete == false { return guarded(.idDetails, session: session) }
        if !resuming && !items.contains(where: \.complete) { return guarded(.yourName, session: session) }

        guard let next = FlowRules.nextIncompleteStep(c, requiredDocuments: steps) else { return .review }
        if next == DocType.selfie { return .selfie }
        if next == DocType.proofOfAddress { return .proofOfAddress }
        return .documents(startAt: next)
    }

    /// The redirects each web page applies when it is opened out of turn.
    package static func guarded(_ destination: Destination, session: HostedSession) -> Destination {
        let collectsName = FlowRules.collectsName(session)
        switch destination {
        case .yourName where !collectsName:
            return guarded(.idDetails, session: session)
        case .idDetails where collectsName && (isBlank(session.firstName) || isBlank(session.lastName)):
            return .yourName
        case .selfie where !session.requiredDocuments.contains(DocType.selfie):
            return .review
        default:
            return destination
        }
    }

    /// Where the flow goes once a screen has saved its work.
    package static func afterCompleting(_ screen: FlowScreen, session: HostedSession, mode: NavigationMode) -> Destination {
        if screen == .review { return .status }
        if mode == .resume { return .checklist }
        let screens = FlowRules.screens(requiredDocuments: session.requiredDocuments, collectName: FlowRules.collectsName(session))
        guard let index = screens.firstIndex(of: screen), index + 1 < screens.count else { return .review }
        return guarded(destination(for: screens[index + 1]), session: session)
    }

    package static func shouldKeepPolling(status: String) -> Bool {
        !finalStatuses.contains(status)
    }

    private static func destination(for screen: FlowScreen) -> Destination {
        switch screen {
        case .yourName: return .yourName
        case .idDetails: return .idDetails
        case .documents: return .documents(startAt: nil)
        case .selfie: return .selfie
        case .proofOfAddress: return .proofOfAddress
        case .review: return .review
        }
    }

    private static func isBlank(_ value: String?) -> Bool {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
