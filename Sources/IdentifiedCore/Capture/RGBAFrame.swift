import Foundation

/// Pixels as the detectors read them: RGBA, 8 bits per channel, row-major,
/// top row first, upright and un-mirrored.
package struct RGBAFrame: Sendable {
    package let width: Int
    package let height: Int
    package let pixels: [UInt8]

    package init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "RGBAFrame needs width * height * 4 bytes")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Rec. 709 luma per pixel, as `luminancePlane` computes it on the web.
    package func luminance() -> [Float] {
        var plane = [Float](repeating: 0, count: width * height)
        pixels.withUnsafeBufferPointer { data in
            for pixel in 0..<plane.count {
                let i = pixel * 4
                plane[pixel] = Float(data[i]) * 0.2126 + Float(data[i + 1]) * 0.7152 + Float(data[i + 2]) * 0.0722
            }
        }
        return plane
    }
}
