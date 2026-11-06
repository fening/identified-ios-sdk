import Foundation
import CoreImage
import Testing
@testable import Identified
import IdentifiedCore
import IdentifiedTestSupport

/// Returns whatever face the test set last.
private final class ScriptedFaces: FaceDetecting, @unchecked Sendable {
    var next: IdentifiedCore.FaceObservation?
    func detect(in frame: CameraFrame) -> IdentifiedCore.FaceObservation? { next }
}

/// A face centred on the raised guide in a 720x1280 frame, 0.6 of the guide circle wide. A nose
/// 50 px right of the eye midline is a yaw of -0.5 (turned left).
private func face(nose: Double = 0, x: Double = 210) -> IdentifiedCore.FaceObservation {
    IdentifiedCore.FaceObservation(
        box: PixelRect(x: x, y: 362, width: 300, height: 300),
        firstEye: FacePoint(x: x + 100, y: 472),
        secondEye: FacePoint(x: x + 200, y: 472),
        nose: FacePoint(x: x + 150 + nose, y: 552)
    )
}

private let frame = cameraFrame(FrameFixtures.page(128, width: 720, height: 1280))

private func engine(_ faces: ScriptedFaces) -> SelfieCaptureEngine {
    let engine = SelfieCaptureEngine(detector: faces)
    engine.setViewSize(PixelSize(width: 720, height: 1280))
    return engine
}

@Test func aFaceOutsideTheGuideSquareNeverAutoCaptures() {
    let faces = ScriptedFaces()
    var observation = face()
    observation.box.y = 750 // Inside the preview, but below the square around its 40%-height circle.
    faces.next = observation
    let engine = engine(faces)
    let first = engine.process(frame, at: 0)
    #expect(first?.update?.status == .offCenter)
    for tick in 1...55 { _ = engine.process(frame, at: Double(tick) / 10) }
    #expect(engine.capturedFrames().isEmpty)
}

@Test func portraitCaptureRetainsFullFieldBeyondTheRaisedGuide() throws {
    // A red band inside the guide plus blue source borders distinguishes full-field encoding.
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
        .cropped(to: CGRect(x: 0, y: 1020, width: 720, height: 70))
    let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 720, height: 1280))
    let source = CameraFrame(image: red.composited(over: blue))
    let faces = ScriptedFaces()
    faces.next = face()
    let engine = engine(faces)
    for tick in 0...50 { _ = engine.process(source, at: Double(tick) / 10) }
    let jpeg = try #require(engine.capturedFrames()[SelfieRole.center])
    let image = try #require(CIImage(data: jpeg))
    #expect(image.extent.width == 720 && image.extent.height == 1280)
    let decoded = CameraFrame(image: image)
    let pixels = try #require(FrameRenderer().analysisFrame(
        from: decoded,
        visible: PixelRect(x: 0, y: 0, width: decoded.size.width, height: decoded.size.height),
        width: 120, height: 120
    ))
    let firstRowCenter = 60 * 4
    #expect(pixels.pixels[firstRowCenter] < 50)
    #expect(pixels.pixels[firstRowCenter + 2] > 200)
    let bandCenter = (21 * 120 + 60) * 4
    #expect(pixels.pixels[bandCenter] > 200)
    #expect(pixels.pixels[bandCenter + 2] < 50)
    let lastRowCenter = (119 * 120 + 60) * 4
    #expect(pixels.pixels[lastRowCenter + 2] > 200)
}

@Test func aFullTurnCapturesThreeFramesAndCompletes() throws {
    let faces = ScriptedFaces()
    let engine = engine(faces)
    var phase = TurnPhase.position
    var completedAt: Double?
    for tick in 0..<300 where completedAt == nil {
        let now = Double(tick) / 10
        faces.next = switch phase {
        case .left: face(nose: 50)
        case .right: face(nose: -50)
        default: face()
        }
        guard let output = engine.process(frame, at: now) else { continue }
        phase = output.phase
        if output.completed { completedAt = now }
    }
    #expect(completedAt != nil)
    let frames = engine.capturedFrames()
    #expect(Set(frames.keys) == SelfieRole.all)
    let centre = try #require(frames[SelfieRole.center])
    let size = try #require(jpegSize(centre))
    #expect(size.width == 720 && size.height == 1280)
}

@Test func noFaceForFiveSecondsSwitchesToTheTimedSequence() {
    let engine = engine(ScriptedFaces())
    var mode = SelfieCaptureEngine.Mode.challenge
    for tick in 0...52 {
        mode = engine.process(frame, at: Double(tick) / 10)?.mode ?? mode
    }
    #expect(mode == .timedWaiting)

    engine.startTimed(at: 6)
    var completed = false
    for tick in 60...122 {
        completed = engine.process(frame, at: Double(tick) / 10)?.completed ?? completed
    }
    #expect(completed)
    #expect(Set(engine.capturedFrames().keys) == SelfieRole.all)
}

@Test func aFaceSeenOnceKeepsTheChallenge() {
    let faces = ScriptedFaces()
    let engine = engine(faces)
    faces.next = face()
    _ = engine.process(frame, at: 0)
    faces.next = nil
    var mode = SelfieCaptureEngine.Mode.challenge
    for tick in 1...80 { mode = engine.process(frame, at: Double(tick) / 10)?.mode ?? mode }
    #expect(mode == .challenge)
}

@Test func theShutterTakesTheFrontFrameAfterEightSecondsOfBadFraming() {
    let faces = ScriptedFaces()
    let engine = engine(faces)
    faces.next = face(x: 0) // off centre
    var available = false
    for tick in 0...82 { available = engine.process(frame, at: Double(tick) / 10)?.update?.shutterAvailable ?? available }
    #expect(available)
    #expect(engine.pressShutter(at: 8.3))
    #expect(engine.capturedFrames().keys.contains(SelfieRole.center))
}

@Test func twoDimSamplesTurnOnTheFillLight() {
    let engine = engine(ScriptedFaces())
    let dim = cameraFrame(FrameFixtures.page(20, width: 720, height: 1280))
    #expect(engine.process(dim, at: 0)?.dark == false)
    #expect(engine.process(dim, at: 0.5)?.dark == true)
}

@Test func tallFullStageKeepsFitGuideContainmentAndFullSourceCapture() throws {
    let faces = ScriptedFaces()
    faces.next = face()
    let engine = engine(faces)
    engine.setViewSize(.init(width: 720, height: 2560))
    // Aspect fill would halve the source width and reject this face as too near.
    #expect(engine.process(frame, at: 0)?.update?.status == .hold)
    for tick in 1...50 { _ = engine.process(frame, at: Double(tick) / 10) }
    let jpeg = try #require(engine.capturedFrames()[SelfieRole.center])
    let size = try #require(jpegSize(jpeg))
    #expect(size.width == 720 && size.height == 1280)
}

@Test func fitStageLightSamplesBrightSourceBordersOutsideTheFillRegion() {
    let dim = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.08))
        .cropped(to: CGRect(x: 0, y: 0, width: 720, height: 1280))
    let left = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 180, height: 1280))
    let right = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
        .cropped(to: CGRect(x: 540, y: 0, width: 180, height: 1280))
    let source = CameraFrame(image: left.composited(over: right.composited(over: dim)))
    let engine = engine(ScriptedFaces())
    engine.setViewSize(.init(width: 720, height: 2560))
    #expect(engine.process(source, at: 0)?.dark == false)
    #expect(engine.process(source, at: 0.5)?.dark == false)
}

@Test func mismatchedStageTimedCaptureUsesActualPixelsWithoutLetterboxPadding() throws {
    let engine = engine(ScriptedFaces())
    // Opposite aspect ratios: the guide square clamps to the source's short side.
    engine.setViewSize(.init(width: 1280, height: 720))
    _ = engine.process(frame, at: 0)
    _ = engine.process(frame, at: 5)
    engine.startTimed(at: 6)
    #expect(engine.process(frame, at: 12)?.completed == true)
    for jpeg in engine.capturedFrames().values {
        let size = try #require(jpegSize(jpeg))
        #expect(size.width == 720 && size.height == 1280)
    }
}
