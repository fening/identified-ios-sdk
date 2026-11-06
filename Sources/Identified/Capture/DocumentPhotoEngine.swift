import CoreImage
import Foundation
import IdentifiedCore

/// Only the supporting-document camera uses the page scanner. Its manual
/// shutter remains independent of the scanner and preserves the visible crop.
final class DocumentPhotoEngine: @unchecked Sendable {
    struct Output: Equatable, Sendable {
        let hint: DocumentHint?
        let page: DocumentPage?
        let fire: Bool
        let viewSize: PixelSize
    }

    static let analysisInterval: TimeInterval = 0.2

    private let renderer: FrameRenderer
    private let scanner: SupportingDocumentScanner
    private let lock = NSLock()
    private var viewSize: PixelSize?
    private var lastAnalysis = -Double.infinity
    private var hold = DocumentPageHold()
    private var revision = 0

    init() {
        let renderer = FrameRenderer()
        self.renderer = renderer
        scanner = SupportingDocumentScanner(renderer: renderer)
    }

    func setViewSize(_ size: PixelSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        lock.withLock {
            guard viewSize != size else { return }
            viewSize = size
            resetAnalysis()
        }
    }

    func reset() {
        lock.withLock { resetAnalysis() }
    }

    private func resetAnalysis() {
        revision += 1
        hold = DocumentPageHold()
        lastAnalysis = -.infinity
    }

    /// Called synchronously by the serial frame source, which drops late frames.
    func process(_ frame: CameraFrame, at now: TimeInterval) -> Output? {
        let snapshot = lock.withLock { () -> (PixelSize, Int)? in
            guard let viewSize, now - lastAnalysis >= Self.analysisInterval else { return nil }
            lastAnalysis = now
            return (viewSize, revision)
        }
        guard let (viewSize, revision) = snapshot,
              let visible = CaptureGeometry.visibleRect(source: frame.size, view: viewSize) else { return nil }

        let (page, quality) = autoreleasepool {
            let image = scanner.analysisImage(frame.image.cropped(to: imageRect(visible, in: frame)))
            let page = image.flatMap { scanner.detect(in: $0) }
            let quality = image.flatMap { scanner.assess(page?.straighten($0) ?? $0) }
            return (page, quality)
        }
        return lock.withLock {
            guard revision == self.revision else { return nil }
            let fire = hold.observe(quality?.ready == true ? page : nil, at: now)
            return Output(hint: quality?.hint, page: page, fire: fire, viewSize: viewSize)
        }
    }

    /// Recheck the actual still, even when the manual shutter fired without a
    /// live detection. The warp reads original pixels and is rendered only once.
    func crop(_ still: CameraFrame) -> Data? {
        let viewSize = lock.withLock { viewSize } ?? still.size
        guard let visible = CaptureGeometry.visibleRect(source: still.size, view: viewSize) else { return nil }
        let image = still.image.cropped(to: imageRect(visible, in: still))
        if let analysis = scanner.analysisImage(image), let page = scanner.detect(in: analysis),
           scanner.assess(page.straighten(analysis))?.ready == true,
           let jpeg = scanner.correctedJPEG(from: image, page: page) {
            return jpeg
        }
        return renderer.jpeg(from: still, crop: visible, quality: 0.95)
    }

    private func imageRect(_ rect: PixelRect, in frame: CameraFrame) -> CGRect {
        let flipped = CaptureGeometry.flippedForCoreImage(rect, imageHeight: frame.size.height)
        return CGRect(x: flipped.x, y: flipped.y, width: flipped.width, height: flipped.height)
    }
}
