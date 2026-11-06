@preconcurrency import CoreImage
import Foundation
import IdentifiedCore
import ImageIO

/// Crops, scales and encodes frames. One per camera screen: a `CIContext` is
/// expensive to create and safe to reuse from one queue.
final class FrameRenderer: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `visible` (top-left pixels) scaled to `width` x `height`, as RGBA with
    /// the top row first: what the card detector and scene light read.
    func analysisFrame(from frame: CameraFrame, visible: PixelRect, width: Int, height: Int) -> RGBAFrame? {
        guard width > 0, height > 0, visible.width > 0, visible.height > 0 else { return nil }
        let crop = CaptureGeometry.flippedForCoreImage(visible, imageHeight: frame.size.height)
        let scaled = frame.image
            .cropped(to: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height))
            .transformed(by: CGAffineTransform(translationX: -crop.x, y: -crop.y))
            .transformed(by: CGAffineTransform(scaleX: Double(width) / crop.width, y: Double(height) / crop.height))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(scaled, toBitmap: &pixels, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: colorSpace)
        return RGBAFrame(width: width, height: height, pixels: pixels)
    }

    func rasterize(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }

    /// `crop` (top-left pixels) as a JPEG.
    func jpeg(from frame: CameraFrame, crop: PixelRect, quality: Double) -> Data? {
        let flipped = CaptureGeometry.flippedForCoreImage(crop, imageHeight: frame.size.height)
        let rect = CGRect(x: flipped.x, y: flipped.y, width: flipped.width, height: flipped.height).integral
        let cropped = frame.image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        return jpeg(from: cropped, quality: quality)
    }

    func jpeg(from image: CIImage, quality: Double) -> Data? {
        let option = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: image, colorSpace: colorSpace, options: [option: quality])
    }
}
