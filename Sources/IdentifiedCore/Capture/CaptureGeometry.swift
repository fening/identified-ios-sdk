import Foundation

package struct PixelSize: Equatable, Sendable {
    package var width: Double
    package var height: Double

    package init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in a frame's pixels, top-left origin.
package struct PixelRect: Equatable, Sendable {
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double

    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var midX: Double { x + width / 2 }
    package var midY: Double { y + height / 2 }
}

/// Ports of `frontend/src/lib/captureFrame.ts` and `CameraCapture.tsx`'s
/// `frameSize`.
package enum CaptureGeometry {
    /// The selfie guide circle's radius as a share of the shorter visible side
    /// (`CaptureStage.tsx` RING_FRACTION).
    package static let ringFraction = 104.0 / 300.0

    /// Full stage in source coordinates, including letterbox space. Never crop with this rect.
    package static func aspectFitStageRect(source: PixelSize, stage: PixelSize) -> PixelRect? {
        guard [source.width, source.height, stage.width, stage.height].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let scale = min(stage.width / source.width, stage.height / source.height)
        let width = stage.width / scale
        let height = stage.height / scale
        guard scale.isFinite, scale > 0, width.isFinite, height.isFinite else { return nil }
        return PixelRect(x: (source.width - width) / 2, y: (source.height - height) / 2, width: width, height: height)
    }

    package static func selfieCenterY(stage: PixelSize, sourceAspect: Double = 0.75) -> Double {
        stage.height > stage.width ? min(stage.height, stage.width / sourceAspect) / 2 : stage.height / 2
    }

    /// Guide-centred coordinates for face checks; includes virtual letterbox pixels.
    package static func selfieFramingRect(source: PixelSize, stage: PixelSize) -> PixelRect? {
        aspectFitStageRect(source: source, stage: stage)
    }

    /// Map the full-source ID guide into a still whose aspect may differ from video.
    /// AVFoundation's centred video field occupies this aspect within the photo.
    package static func cardCaptureRect(source: PixelSize, still: PixelSize) -> PixelRect? {
        guard aspectFitStageRect(source: source, stage: still) != nil,
              let videoInStill = visibleRect(source: still, view: source) else { return nil }
        return guideCrop(visible: videoInStill, margin: 1)
    }

    /// The full-stage guide plus bleed, bounded to actual camera pixels.
    package static func selfieCaptureRect(source: PixelSize, stage: PixelSize) -> PixelRect? {
        guard let virtual = selfieFramingRect(source: source, stage: stage) else { return nil }
        let side = min(2 * ringFraction * min(virtual.width, virtual.height) * 1.2, min(source.width, source.height))
        return PixelRect(x: max(0, min(source.width - side, virtual.midX - side / 2)),
                         y: max(0, min(source.height - side, virtual.midY - side / 2)), width: side, height: side)
    }

    /// The part of a `source` frame an aspect-fill preview of `view` shows.
    package static func visibleRect(source: PixelSize, view: PixelSize) -> PixelRect? {
        guard source.width > 0, source.height > 0, view.width > 0, view.height > 0 else { return nil }
        let scale = max(view.width / source.width, view.height / source.height)
        let width = min(source.width, view.width / scale)
        let height = min(source.height, view.height / scale)
        return PixelRect(x: (source.width - width) / 2, y: (source.height - height) / 2, width: width, height: height)
    }

    /// The card guide, widened by `margin` so a card a little outside the
    /// outline keeps its edges.
    package static func guideCrop(
        visible: PixelRect,
        widthFraction: Double = CardDetector.guideWidthFraction,
        aspectRatio: Double = CardDetector.aspectRatio,
        margin: Double = 1.08
    ) -> PixelRect {
        let width = min(visible.width * widthFraction * margin, visible.width)
        let height = min(width / aspectRatio, visible.height)
        return PixelRect(x: visible.x + (visible.width - width) / 2, y: visible.y + (visible.height - height) / 2, width: width, height: height)
    }

    /// A square around the selfie guide circle, with margin for hair and chin.
    package static func circleCrop(visible: PixelRect, ringFraction: Double = CaptureGeometry.ringFraction, margin: Double = 1.2) -> PixelRect {
        let side = min(2 * ringFraction * min(visible.width, visible.height) * margin, visible.width, visible.height)
        return PixelRect(x: visible.x + (visible.width - side) / 2, y: visible.y + (visible.height - side) / 2, width: side, height: side)
    }

    /// Hosted CaptureStage uses the centre of the visible preview (50%).
    /// Both upload cropping and the containment guard use this same square.
    package static func selfieCrop(visible: PixelRect) -> PixelRect {
        circleCrop(visible: visible)
    }

    /// The analysis frame for a visible region of this aspect: about
    /// `CardDetector.analysisPixels`, never under 120 on a side.
    package static func analysisSize(aspect: Double, pixels: Double = CardDetector.analysisPixels) -> (width: Int, height: Int) {
        let width = max(120, Int((pixels * aspect).squareRoot().rounded()))
        return (width, max(120, Int((Double(width) / aspect).rounded())))
    }

    /// Core Image puts the origin bottom-left.
    package static func flippedForCoreImage(_ rect: PixelRect, imageHeight: Double) -> PixelRect {
        PixelRect(x: rect.x, y: imageHeight - rect.y - rect.height, width: rect.width, height: rect.height)
    }
}
