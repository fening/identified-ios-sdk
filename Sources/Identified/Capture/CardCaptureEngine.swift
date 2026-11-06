import Foundation
import IdentifiedCore

/// The card camera's per-frame work: downscale the entire source,
/// assess it, and decide when to capture. Called on the camera's queue; the
/// lock covers the gate and the view size, which the main thread sets.
final class CardCaptureEngine: @unchecked Sendable {
    struct Output: Equatable, Sendable {
        var hint: CardHint
        var ready: Bool
        var sourceAspect: Double
        /// Take the picture now. True at most once until `reset()`.
        var fire: Bool
    }

    private let renderer = FrameRenderer()
    private let lock = NSLock()
    private var gate = AutoCaptureGate()
    private var lastAnalysis = -Double.infinity
    private var viewSize: PixelSize?
    private var sourceSize: PixelSize?

    /// The preview's size on screen, in any unit: only its aspect matters.
    func setViewSize(_ size: PixelSize) {
        lock.withLock { viewSize = size }
    }

    /// After a retake or a failed capture.
    func reset() {
        lock.withLock {
            gate.reset()
            lastAnalysis = -.infinity
        }
    }

    /// Nil when this frame is skipped: too soon after the last, or no view yet.
    func process(_ frame: CameraFrame, at now: TimeInterval) -> Output? {
        lock.withLock {
            guard let viewSize, now - lastAnalysis >= CardDetector.analysisInterval,
                  CaptureGeometry.aspectFitStageRect(source: frame.size, stage: viewSize) != nil else { return nil }
            sourceSize = frame.size
            let visible = PixelRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height)
            lastAnalysis = now
            let size = CaptureGeometry.analysisSize(aspect: visible.width / visible.height)
            guard let pixels = renderer.analysisFrame(from: frame, visible: visible, width: size.width, height: size.height) else { return nil }
            let assessment = CardDetector.assess(pixels)
            let fire = gate.observe(assessment, frameWidth: pixels.width, frameHeight: pixels.height, at: now)
            return Output(hint: assessment.hint, ready: assessment.ready, sourceAspect: frame.size.width / frame.size.height, fire: fire)
        }
    }

    /// Exact visible ID guide, cut only after physical photo capture.
    func crop(_ still: CameraFrame) -> Data? {
        guard let source = lock.withLock({ sourceSize }),
              let crop = CaptureGeometry.cardCaptureRect(source: source, still: still.size) else { return nil }
        return renderer.jpeg(from: still, crop: crop, quality: 0.95)
    }
}
