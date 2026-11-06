import CoreImage
import ImageIO
import Testing
@testable import Identified
import IdentifiedCore

/// 100x100: red on top, blue underneath, as a person looking at it sees it.
/// (Core Image's origin is bottom-left, so "top" is y 50–100 there.)
private func redOverBlue() -> CIImage {
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 50, width: 100, height: 50))
    let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50))
    return red.composited(over: blue)
}

private func pixel(_ frame: RGBAFrame, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
    let i = (y * frame.width + x) * 4
    return (frame.pixels[i], frame.pixels[i + 1], frame.pixels[i + 2])
}

@Test func rendersTheTopRowFirst() throws {
    let frame = try #require(FrameRenderer().analysisFrame(from: CameraFrame(image: redOverBlue()), visible: PixelRect(x: 0, y: 0, width: 100, height: 100), width: 10, height: 10))
    #expect(frame.width == 10 && frame.height == 10)
    #expect(pixel(frame, 5, 0).0 > 200 && pixel(frame, 5, 0).2 < 50)
    #expect(pixel(frame, 5, 9).2 > 200 && pixel(frame, 5, 9).0 < 50)
}

@Test func cropsTheVisibleRegionInTopLeftCoordinates() throws {
    let frame = try #require(FrameRenderer().analysisFrame(from: CameraFrame(image: redOverBlue()), visible: PixelRect(x: 0, y: 0, width: 100, height: 50), width: 8, height: 4))
    for y in 0..<4 { for x in 0..<8 { #expect(pixel(frame, x, y).0 > 200) } }
}

@Test func encodesACropAsAJPEGOfThatSize() throws {
    let data = try #require(FrameRenderer().jpeg(from: CameraFrame(image: redOverBlue()), crop: PixelRect(x: 10, y: 60, width: 40, height: 20), quality: 0.9))
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 40)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 20)
    #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
}

@Test func reportsTheFrameSize() {
    #expect(CameraFrame(image: redOverBlue()).size == PixelSize(width: 100, height: 100))
}
