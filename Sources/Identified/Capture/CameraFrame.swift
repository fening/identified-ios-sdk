@preconcurrency import CoreImage
import IdentifiedCore

/// A camera frame or still: upright, un-mirrored, origin normalised to zero.
struct CameraFrame: @unchecked Sendable {
    let image: CIImage

    init(image: CIImage) {
        let extent = image.extent
        self.image = extent.origin == .zero ? image : image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    var size: PixelSize {
        PixelSize(width: Double(image.extent.width), height: Double(image.extent.height))
    }
}
