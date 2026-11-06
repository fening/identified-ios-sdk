import Testing
@testable import IdentifiedCore

private let view = PixelRect(x: 0, y: 0, width: 720, height: 1280)
private let circle = 2 * TurnChallenge.ringFraction * 720

/// A face in the 720x1280 frame: `size` as a share of the guide circle,
/// centred at (cx, cy) as shares of the frame, turned to `yaw` (web convention).
private func face(yaw: Double = 0, size: Double = 0.55, cx: Double = 0.5, cy: Double = 0.5) -> FaceObservation {
    let width = size * circle
    let center = FacePoint(x: cx * 720, y: cy * 1280)
    let inter = width * 0.4
    return FaceObservation(
        box: PixelRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width),
        firstEye: FacePoint(x: center.x - inter / 2, y: center.y - width * 0.1),
        secondEye: FacePoint(x: center.x + inter / 2, y: center.y - width * 0.1),
        nose: FacePoint(x: center.x - yaw * inter, y: center.y + width * 0.05)
    )
}

/// Feeds the same face every 50 ms from `from` to `to` and returns every update.
private func feed(_ challenge: inout TurnChallenge, _ observation: FaceObservation?, from: Double, to: Double) -> [TurnUpdate] {
    stride(from: from, through: to, by: 0.05).map { challenge.update(face: observation, visible: view, now: $0) }
}

private func firstCapture(_ updates: [TurnUpdate]) -> String? {
    updates.compactMap(\.capture).first
}

@Test func computesYawLikeTheWeb() {
    #expect(abs(TurnChallenge.yaw(face(yaw: 0.4)) - 0.4) < 1e-9)
    #expect(abs(TurnChallenge.yaw(face(yaw: -0.2)) + 0.2) < 1e-9)
}

@Test func capturesTheFrontalFrameAfterSettleAndCountdown() {
    var challenge = TurnChallenge()
    let settling = feed(&challenge, face(), from: 0, to: 1.15)
    #expect(settling.allSatisfy { $0.status == .hold && $0.countdown == nil && $0.capture == nil })
    let counting = feed(&challenge, face(), from: 1.2, to: 4.15)
    #expect(counting.first?.countdown == 3)
    #expect(counting.contains { $0.countdown == 1 })
    #expect(firstCapture(counting) == nil)
    #expect(challenge.update(face: face(), visible: view, now: 4.25).capture == SelfieRole.center)
}

@Test func doesNotAskForASecondCaptureWhileOneIsInFlight() {
    var challenge = TurnChallenge()
    _ = feed(&challenge, face(), from: 0, to: 4.3)
    #expect(firstCapture(feed(&challenge, face(), from: 4.35, to: 5)) == nil)
}

@Test func walksLeftCentreRightAndCompletes() {
    var challenge = TurnChallenge()
    _ = feed(&challenge, face(), from: 0, to: 4.3)
    challenge.didCapture(SelfieRole.center)
    #expect(challenge.phase == .left)

    // The web's 0.30, and the server's own 0.35, are not enough here: Vision
    // reads one side of a turn higher than the server does.
    #expect(firstCapture(feed(&challenge, face(yaw: -0.40), from: 5, to: 7)) == nil)
    let left = feed(&challenge, face(yaw: -0.50), from: 7.05, to: 8)
    #expect(firstCapture(left) == SelfieRole.left)
    challenge.didCapture(SelfieRole.left)
    #expect(challenge.phase == .center)

    _ = challenge.update(face: face(yaw: 0.05), visible: view, now: 8.5)
    #expect(challenge.phase == .right)

    let right = feed(&challenge, face(yaw: 0.50), from: 9, to: 10)
    #expect(firstCapture(right) == SelfieRole.right)
    challenge.didCapture(SelfieRole.right, at: 10)
    #expect(challenge.phase == .done)

    #expect(!challenge.update(face: nil, visible: view, now: 10.5).completed)
    #expect(challenge.update(face: nil, visible: view, now: 10.95).completed)
    #expect(!challenge.update(face: nil, visible: view, now: 11).completed)
    #expect(challenge.roles == [SelfieRole.center, SelfieRole.left, SelfieRole.right])
}

@Test func aTurnMustBeHeld() {
    var challenge = TurnChallenge()
    _ = feed(&challenge, face(), from: 0, to: 4.3)
    challenge.didCapture(SelfieRole.center)
    _ = feed(&challenge, face(yaw: -0.50), from: 5, to: 5.5)
    #expect(firstCapture(feed(&challenge, face(yaw: 0), from: 5.55, to: 6)) == nil)
    #expect(firstCapture(feed(&challenge, face(yaw: -0.50), from: 6.05, to: 6.6)) == nil)
}

@Test func losingFramingRestartsTheFrontalCountdown() {
    var challenge = TurnChallenge()
    _ = feed(&challenge, face(), from: 0, to: 3)
    #expect(challenge.update(face: face(size: 0.3), visible: view, now: 3.05).status == .far)
    #expect(firstCapture(feed(&challenge, face(), from: 3.1, to: 7)) == nil)
    #expect(firstCapture(feed(&challenge, face(), from: 7.05, to: 7.5)) == SelfieRole.center)
}

@Test func reportsWhatIsWrongWithTheFraming() {
    var challenge = TurnChallenge()
    #expect(challenge.update(face: nil, visible: view, now: 0).status == .noFace)
    #expect(challenge.update(face: face(size: 0.3), visible: view, now: 0.1).status == .far)
    #expect(challenge.update(face: face(size: 0.25), visible: view, now: 0.15).distanceLevel == 1)
    #expect(challenge.update(face: face(size: 0.8), visible: view, now: 0.2).status == .near)
    #expect(challenge.update(face: face(size: 0.8), visible: view, now: 0.2).distanceLevel == 3)
    #expect(challenge.update(face: face(cx: 0.2), visible: view, now: 0.3).status == .offCenter)
    #expect(challenge.update(face: face(yaw: 0.3), visible: view, now: 0.4).status == .lookStraight)
}

@Test func offersTheShutterAfterEightSecondsOfFailedFraming() {
    var challenge = TurnChallenge()
    let early = feed(&challenge, nil, from: 0, to: 7.9)
    #expect(early.allSatisfy { !$0.shutterAvailable })
    #expect(challenge.pressShutter(now: 7.9) == nil)
    #expect(challenge.update(face: nil, visible: view, now: 8.05).shutterAvailable)
    #expect(challenge.pressShutter(now: 8.05) == SelfieRole.center)
    #expect(challenge.pressShutter(now: 8.1) == nil)
}

@Test func aFailedCaptureCanBeRequestedAgain() {
    var challenge = TurnChallenge()
    _ = feed(&challenge, face(), from: 0, to: 4.3)
    challenge.captureFailed()
    #expect(firstCapture(feed(&challenge, face(), from: 4.35, to: 4.4)) == SelfieRole.center)
}

@Test func theFallbackTakesOneFrameAtTheEndOfEachPose() {
    let times = TimedTurnFallback.captures.map { ($0.role, $0.at) }
    #expect(times.map(\.0) == [SelfieRole.left, SelfieRole.center, SelfieRole.right])
    #expect(times.map(\.1).enumerated().allSatisfy { abs($0.element - [2.4, 3.3, 6.0][$0.offset]) < 1e-9 })
}

@Test func uploadsTheCentreFrameLast() {
    // Face match and NIA use the latest selfie.
    #expect(SelfieRole.uploadOrder(of: [SelfieRole.center, SelfieRole.left, SelfieRole.right]) == [SelfieRole.left, SelfieRole.right, SelfieRole.center])
}


@Test func frontalCountdownUsesHeadPoseRatherThanEyeGazeWhenAvailable() {
    var challenge = TurnChallenge()
    var forward = face(yaw: 0.20)
    forward.headYawRadians = 0.04
    let front = feed(&challenge, forward, from: 0, to: 4.3)
    #expect(front.contains { $0.countdown == 3 })
    #expect(firstCapture(front) == SelfieRole.center)

    var turnedChallenge = TurnChallenge()
    var turned = face(yaw: 0)
    turned.headYawRadians = 0.20
    let offAngle = feed(&turnedChallenge, turned, from: 0, to: 4.3)
    #expect(offAngle.allSatisfy { $0.status == .lookStraight && $0.countdown == nil })
    #expect(firstCapture(offAngle) == nil)
}
