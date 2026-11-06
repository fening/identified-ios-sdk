import CoreImage
import ImageIO
@testable import Identified
import IdentifiedCore

/// A fixture frame as the camera would deliver it.
func cameraFrame(_ frame: RGBAFrame) -> CameraFrame {
    CameraFrame(image: CIImage(
        bitmapData: Data(frame.pixels),
        bytesPerRow: frame.width * 4,
        size: CGSize(width: frame.width, height: frame.height),
        format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    ))
}

/// A flat grey frame of the given size.
func flatFrame(width: Int, height: Int, gray: Double = 0.5) -> CameraFrame {
    CameraFrame(image: CIImage(color: CIColor(red: gray, green: gray, blue: gray)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height)))
}

func jpegSize(_ data: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return CGSize(width: width, height: height)
}
