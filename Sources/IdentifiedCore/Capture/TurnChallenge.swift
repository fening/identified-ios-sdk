import Foundation

package struct FacePoint: Equatable, Sendable {
    package var x: Double
    package var y: Double

    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A face in an upright, un-mirrored frame, in that frame's pixels (top-left
/// origin). The eyes may come in either order: yaw uses their midpoint and
/// absolute distance.
package struct FaceObservation: Equatable, Sendable {
    package var box: PixelRect
    package var firstEye: FacePoint
    package var secondEye: FacePoint
    package var nose: FacePoint
    package var headYawRadians: Double?

    package init(box: PixelRect, firstEye: FacePoint, secondEye: FacePoint, nose: FacePoint, headYawRadians: Double? = nil) {
        self.box = box
        self.firstEye = firstEye
        self.secondEye = secondEye
        self.nose = nose
        self.headYawRadians = headYawRadians
    }
}

package enum TurnPhase: Equatable, Sendable {
    case position, left, center, right, done
}

package enum TurnStatus: Equatable, Sendable {
    case noFace, far, near, offCenter, lookStraight, hold, ok
}

/// What the selfie screen draws for one analysed frame, and whether to take a
/// picture now.
package struct TurnUpdate: Equatable, Sendable {
    package var status: TurnStatus
    package var yaw: Double
    /// 3, 2, 1 during the frontal countdown.
    package var countdown: Int?
    /// 0…1 progress of the frontal countdown ring.
    package var sweep: Double
    /// 1 far, 2 fine, 3 near.
    package var distanceLevel: Int
    package var shutterAvailable: Bool
    /// A selfie role to capture from this frame, if one is due.
    package var capture: String?
    /// True once, 0.9 s after the last frame was captured.
    package var completed: Bool
}

/// A port of `FluidTurnChallenge.tsx`: hold a frontal pose through a
/// countdown, turn one way, come back, turn the other way.
package struct TurnChallenge: Sendable {
    /// Yaw that counts as turned. The server requires 0.35 on both sides
    /// (`face-verification-service/app/challenge.py`), measured on InsightFace
    /// keypoints, which read one side of a turn lower than Vision does. On an
    /// iPhone 12 (2026-11-02) a turn accepted at 0.38 here measured only 0.32
    /// on the server on one side and 0.50 on the other, so the client asks for
    /// 0.45 to clear 0.35 on both. The web uses 0.30.
    package static let side = 0.45
    package static let frontal = 0.14
    private static let frontalHeadYaw = 8.0 * Double.pi / 180
    package static let faceMin = 0.42
    package static let faceMax = 0.72
    package static let hold: TimeInterval = 0.7
    package static let settle: TimeInterval = 1.2
    package static let countdown: TimeInterval = 3.0
    package static let shutterEscape: TimeInterval = 8.0
    package static let finishDelay: TimeInterval = 0.9
    package static let ringFraction = CaptureGeometry.ringFraction

    package private(set) var phase: TurnPhase = .position
    package private(set) var roles: [String] = []
    private var goodSince: TimeInterval?
    private var stallSince: TimeInterval?
    private var holdSince: TimeInterval?
    private var inFlight: String?
    private var doneAt: TimeInterval?
    private var completed = false

    package init() {}

    /// The web's yaw proxy: nose offset from the eye midline over eye distance.
    package static func yaw(_ face: FaceObservation) -> Double {
        let mid = (face.firstEye.x + face.secondEye.x) / 2
        let inter = abs(face.firstEye.x - face.secondEye.x)
        return inter > 1e-4 ? -((face.nose.x - mid) / inter) : 0
    }

    package mutating func update(face: FaceObservation?, visible view: PixelRect, now: TimeInterval, captureBounds: PixelRect? = nil) -> TurnUpdate {
        var update = TurnUpdate(status: .noFace, yaw: 0, countdown: nil, sweep: 0, distanceLevel: 2, shutterAvailable: false, capture: nil, completed: false)

        if phase == .done {
            if let doneAt, !completed, now - doneAt >= Self.finishDelay {
                completed = true
                update.completed = true
            }
            return update
        }

        guard let face else {
            goodSince = nil
            holdSince = nil
            if phase == .position {
                if stallSince == nil { stallSince = now }
                update.shutterAvailable = shutterAvailable(now)
            }
            return update
        }

        let circle = 2 * Self.ringFraction * min(view.width, view.height)
        let faceWidth = face.box.width / circle
        let cx = (face.box.midX - view.x) / view.width
        let cy = (face.box.midY - view.y) / view.height
        let bounds = captureBounds ?? view
        let inFrame = face.box.x >= bounds.x - 4 && face.box.y >= bounds.y - 4
            && face.box.x + face.box.width <= bounds.x + bounds.width + 4
            && face.box.y + face.box.height <= bounds.y + bounds.height + 4
        let centered = cx > 0.3 && cx < 0.7 && cy > 0.26 && cy < 0.74
        let distance: TurnStatus = faceWidth < Self.faceMin ? .far : faceWidth > Self.faceMax ? .near : .ok
        update.distanceLevel = distance == .near ? 3 : faceWidth < Self.faceMin * 0.7 ? 1 : 2
        let good = distance == .ok && centered && inFrame
        let yaw = Self.yaw(face)
        update.yaw = yaw
        // The eye-to-nose proxy can shift with gaze. Use Vision's head pose
        // for frontal alignment when present, and keep the side gate unchanged.
        let isFrontal = face.headYawRadians.flatMap { $0.isFinite ? abs($0) < Self.frontalHeadYaw : nil }
            ?? (abs(yaw) < Self.frontal)
        update.status = !inFrame ? .offCenter : distance != .ok ? distance : !centered ? .offCenter : .ok

        switch phase {
        case .position:
            if good && isFrontal {
                stallSince = nil
                if goodSince == nil { goodSince = now }
                let elapsed = now - goodSince!
                update.countdown = Self.countdownValue(elapsed)
                update.sweep = clamp((elapsed - Self.settle) / Self.countdown, 0, 1)
                if elapsed >= Self.settle + Self.countdown {
                    update.capture = request(SelfieRole.center)
                } else {
                    update.status = .hold
                }
            } else {
                goodSince = nil
                if stallSince == nil { stallSince = now }
                update.shutterAvailable = shutterAvailable(now)
                if good { update.status = .lookStraight }
            }
        case .left:
            update.capture = turn(good: good, reached: yaw <= -Self.side, role: SelfieRole.left, now: now)
        case .center:
            if good && isFrontal { phase = .right }
        case .right:
            update.capture = turn(good: good, reached: yaw >= Self.side, role: SelfieRole.right, now: now)
        case .done:
            break
        }
        return update
    }

    /// The glue took the picture it was asked for.
    package mutating func didCapture(_ role: String, at now: TimeInterval = 0) {
        guard role == inFlight else { return }
        inFlight = nil
        holdSince = nil
        roles.append(role)
        switch role {
        case SelfieRole.center: phase = .left
        case SelfieRole.left: phase = .center
        default:
            phase = .done
            doneAt = now
        }
    }

    /// The picture could not be taken; ask again on a later frame.
    package mutating func captureFailed() {
        inFlight = nil
        holdSince = nil
    }

    /// The manual shutter, offered for the frontal frame after 8 s of failed
    /// framing. Returns the role to capture, or nil if it is not on offer.
    package mutating func pressShutter(now: TimeInterval) -> String? {
        guard phase == .position, shutterAvailable(now) else { return nil }
        return request(SelfieRole.center)
    }

    static func countdownValue(_ elapsed: TimeInterval) -> Int? {
        let total = settle + countdown
        guard elapsed >= settle, elapsed < total else { return nil }
        return Int((total - elapsed).rounded(.up))
    }

    private func shutterAvailable(_ now: TimeInterval) -> Bool {
        inFlight == nil && stallSince.map { now - $0 >= Self.shutterEscape } == true
    }

    private mutating func request(_ role: String) -> String? {
        guard inFlight == nil else { return nil }
        inFlight = role
        return role
    }

    private mutating func turn(good: Bool, reached: Bool, role: String, now: TimeInterval) -> String? {
        guard good, reached else {
            holdSince = nil
            return nil
        }
        if holdSince == nil { holdSince = now }
        return now - holdSince! >= Self.hold ? request(role) : nil
    }
}

/// `TurnChallenge.tsx`: used when landmarks cannot be detected. A timed
/// sequence with no face detection, one frame at the end of each pose.
package enum TimedTurnFallback {
    package struct Capture: Equatable, Sendable {
        package var role: String
        package var at: TimeInterval
    }

    package static let duration: TimeInterval = 6
    package static let captures: [Capture] = [
        Capture(role: SelfieRole.left, at: duration * 0.4),
        Capture(role: SelfieRole.center, at: duration * 0.55),
        Capture(role: SelfieRole.right, at: duration),
    ]
}

extension SelfieRole {
    /// Upload order: the centre frame last, because face match and NIA use the
    /// latest selfie.
    package static func uploadOrder(of roles: [String]) -> [String] {
        roles.filter { $0 != center } + roles.filter { $0 == center }
    }
}
