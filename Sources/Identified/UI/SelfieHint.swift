import IdentifiedCore

/// `captureHint` in `CaptureStage.tsx`: the first matching rule wins.
enum SelfieHint {
    static func text(phase: TurnPhase, status: TurnStatus, yaw: Double) -> String {
        if phase == .done { return L10n.string("selfie.hint.done") }
        switch status {
        case .noFace, .offCenter: return L10n.string("selfie.hint.center")
        case .far: return L10n.string("selfie.hint.closer")
        case .near: return L10n.string("selfie.hint.back")
        case .lookStraight: return L10n.string("selfie.hint.straight")
        case .hold, .ok: break
        }
        let turn = phase == .left ? max(0, -yaw) / TurnChallenge.side : phase == .right ? max(0, yaw) / TurnChallenge.side : 0
        switch phase {
        case .position: return L10n.string("selfie.hint.hold_photo")
        // Two arms: in `case .left, .right where …` the condition binds to .right only.
        case .left where turn >= 1, .right where turn >= 1: return L10n.string("selfie.hint.perfect")
        case .left where turn >= 0.35: return L10n.string("selfie.hint.keep_left")
        case .right where turn >= 0.35: return L10n.string("selfie.hint.keep_right")
        case .left: return L10n.string("selfie.hint.turn_left")
        case .center: return L10n.string("selfie.hint.centre")
        case .right: return L10n.string("selfie.hint.turn_right")
        case .done: return L10n.string("selfie.hint.done")
        }
    }
}
