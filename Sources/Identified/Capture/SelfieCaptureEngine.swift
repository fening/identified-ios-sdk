import Foundation
import IdentifiedCore

protocol FaceDetecting: Sendable {
    func detect(in frame: CameraFrame) -> IdentifiedCore.FaceObservation?
}

extension FaceLandmarkDetector: FaceDetecting {}

/// The selfie camera's per-frame work. Frames come from the front camera's
/// stream; each pose is cropped from the frame that triggered it, so there is
/// no separate photo capture. Called on the camera's queue.
final class SelfieCaptureEngine: @unchecked Sendable {
    enum Mode: Equatable, Sendable {
        /// The landmark-driven turn challenge.
        case challenge
        /// No face was ever found: waiting for the subject to start the timed sequence.
        case timedWaiting
        /// `TurnChallenge.tsx`'s six-second sequence.
        case timed
    }

    struct Output: Equatable, Sendable {
        var mode: Mode
        var phase: TurnPhase
        /// The challenge's view of this frame. Nil in the timed modes.
        var update: TurnUpdate?
        /// 0…1 through the timed sequence.
        var timedProgress: Double
        var dark: Bool
        var completed: Bool
    }

    /// Vision on every frame is wasted work; ten analyses a second is smooth.
    static let analysisInterval: TimeInterval = 0.1
    /// No landmarks at all for this long, with frames arriving, means the
    /// detector cannot work here.
    static let fallbackAfter: TimeInterval = 5

    private let detector: FaceDetecting
    private let renderer = FrameRenderer()
    private let lock = NSLock()
    private var viewSize: PixelSize?
    private var challenge = TurnChallenge()
    private var light = SceneLight()
    private var mode = Mode.challenge
    private var frames: [String: Data] = [:]
    private var lastFrame: (frame: CameraFrame, captureRect: PixelRect)?
    private var lastAnalysis = -Double.infinity
    private var lastLightSample = -Double.infinity
    private var firstFrameAt: TimeInterval?
    private var timedStart: TimeInterval?
    private var sawFace = false
    private var completed = false

    init(detector: FaceDetecting = FaceLandmarkDetector()) {
        self.detector = detector
    }

    func setViewSize(_ size: PixelSize) {
        lock.withLock { viewSize = size }
    }

    func capturedFrames() -> [String: Data] {
        lock.withLock { frames }
    }

    /// A retake. The fallback, once chosen, is kept: the detector did not
    /// start working in the meantime.
    func reset() {
        lock.withLock {
            challenge = TurnChallenge()
            frames = [:]
            completed = false
            lastAnalysis = -.infinity
            timedStart = nil
            if mode == .timed { mode = .timedWaiting }
        }
    }

    /// The timed sequence's start button.
    func startTimed(at now: TimeInterval) {
        lock.withLock {
            guard mode == .timedWaiting else { return }
            mode = .timed
            timedStart = now
        }
    }

    /// The manual shutter, for the front frame only. False when not on offer.
    func pressShutter(at now: TimeInterval) -> Bool {
        lock.withLock {
            guard mode == .challenge, let last = lastFrame, let role = challenge.pressShutter(now: now) else { return false }
            return capture(role, from: last.frame, captureRect: last.captureRect, at: now)
        }
    }

    func process(_ frame: CameraFrame, at now: TimeInterval) -> Output? {
        lock.withLock {
            guard !completed, let viewSize,
                  let framing = CaptureGeometry.selfieFramingRect(source: frame.size, stage: viewSize),
                  let captureRect = CaptureGeometry.selfieCaptureRect(source: frame.size, stage: viewSize) else { return nil }
            lastFrame = (frame, captureRect)
            let started = firstFrameAt ?? now
            firstFrameAt = started
            sampleLight(frame, at: now)

            switch mode {
            case .timedWaiting:
                return Output(mode: mode, phase: .position, update: nil, timedProgress: 0, dark: light.dark, completed: false)
            case .timed:
                let elapsed = now - (timedStart ?? now)
                for step in TimedTurnFallback.captures where step.at <= elapsed && frames[step.role] == nil {
                    if let jpeg = crop(frame, captureRect: captureRect) { frames[step.role] = jpeg }
                }
                completed = frames.count == SelfieRole.all.count
                return Output(mode: mode, phase: completed ? .done : .position, update: nil,
                              timedProgress: min(elapsed / TimedTurnFallback.duration, 1), dark: light.dark, completed: completed)
            case .challenge:
                guard now - lastAnalysis >= Self.analysisInterval else { return nil }
                lastAnalysis = now
                let face = detector.detect(in: frame)
                if face != nil { sawFace = true }
                if !sawFace, now - started >= Self.fallbackAfter {
                    mode = .timedWaiting
                    return Output(mode: mode, phase: .position, update: nil, timedProgress: 0, dark: light.dark, completed: false)
                }
                let update = challenge.update(face: face, visible: framing, now: now, captureBounds: captureRect)
                if let role = update.capture { _ = capture(role, from: frame, captureRect: captureRect, at: now) }
                completed = update.completed
                return Output(mode: mode, phase: challenge.phase, update: update, timedProgress: 0, dark: light.dark, completed: completed)
            }
        }
    }

    private func capture(_ role: String, from frame: CameraFrame, captureRect: PixelRect, at now: TimeInterval) -> Bool {
        guard let jpeg = crop(frame, captureRect: captureRect) else {
            challenge.captureFailed()
            return false
        }
        frames[role] = jpeg
        challenge.didCapture(role, at: now)
        return true
    }

    /// Keep the full source field. captureRect remains the challenge containment boundary.
    private func crop(_ frame: CameraFrame, captureRect: PixelRect) -> Data? {
        renderer.jpeg(from: frame, crop: PixelRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height), quality: 0.85)
    }

    private func sampleLight(_ frame: CameraFrame, at now: TimeInterval) {
        guard now - lastLightSample >= SceneLight.sampleInterval,
              let small = renderer.analysisFrame(from: frame, visible: PixelRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height), width: 48, height: 64) else { return }
        lastLightSample = now
        light.observe(meanLuminance: SceneLight.meanLuminance(small))
    }
}
