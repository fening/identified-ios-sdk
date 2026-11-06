import IdentifiedCore

/// A screen on the flow's navigation stack. Entry is the stack's root and so
/// has no route.
enum FlowRoute: Hashable {
    case consent
    case checklist
    case yourName
    case idDetails
    /// `startAt` nil means the first document step.
    case documents(startAt: String?)
    case selfie
    case proofOfAddress
    case review
    case status

    init(_ destination: Destination) {
        switch destination {
        case .yourName: self = .yourName
        case .idDetails: self = .idDetails
        case let .documents(startAt): self = .documents(startAt: startAt)
        case .selfie: self = .selfie
        case .proofOfAddress: self = .proofOfAddress
        case .review: self = .review
        case .checklist: self = .checklist
        case .status: self = .status
        }
    }
}

#if os(iOS)
extension FlowRoute {
    /// The checklist is a resume hub; status is a terminal/polling destination.
    var showsBack: Bool {
        switch self {
        case .checklist, .status: false
        default: true
        }
    }
}
#endif
