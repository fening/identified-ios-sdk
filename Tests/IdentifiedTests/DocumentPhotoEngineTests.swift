import CoreImage
import Foundation
import Testing
@testable import Identified
import IdentifiedCore
import IdentifiedTestSupport

@Test func aDimPageAsksForBetterLight() {
    let engine = DocumentPhotoEngine()
    engine.setViewSize(PixelSize(width: 320, height: 240))
    #expect(engine.process(cameraFrame(FrameFixtures.page(20)), at: 0)?.hint == .tooDark)
    #expect(engine.process(cameraFrame(FrameFixtures.page(20)), at: 0.1) == nil)
    #expect(engine.process(cameraFrame(FrameFixtures.page(20)), at: 0.21)?.hint == .tooDark)
}

@Test func thePhotoIsTheWholeVisibleFrameWhenNoPageIsFound() throws {
    let engine = DocumentPhotoEngine()
    engine.setViewSize(PixelSize(width: 390, height: 844))
    let photo = try #require(engine.crop(flatFrame(width: 1080, height: 1920)))
    let size = try #require(jpegSize(photo))
    #expect(abs(size.width - 887) <= 2 && size.height == 1920)
}

@Test func tiltedPageIsDetectedAndStraightenedFromTheHighResolutionStill() throws {
    let engine = documentEngine()
    let result = try #require(engine.process(tiltedPage(), at: 0))
    let page = try #require(result.page)
    #expect(abs(page.topLeft.x - 105.0 / 480) < 0.025)
    #expect(abs(page.topLeft.y - 546.0 / 640) < 0.025)
    #expect(abs(page.bottomRight.x - 400.0 / 480) < 0.025)
    #expect(abs(page.bottomRight.y - 105.0 / 640) < 0.025)
    #expect(result.hint == .looksSharp)

    let jpeg = try #require(engine.crop(tiltedPage(scale: 4)))
    let size = try #require(jpegSize(jpeg))
    #expect(size.width > 1000 && size.width < 1800, "Corrected dimensions: \(size)")
    #expect(size.height > 1550 && size.height < 2400, "Corrected dimensions: \(size)")
    let image = try #require(CIImage(data: jpeg))
    let corrected = CameraFrame(image: image)
    let pixels = try #require(FrameRenderer().analysisFrame(from: corrected,
        visible: PixelRect(x: 0, y: 0, width: size.width, height: size.height), width: 60, height: 80))
    // All four corners are inside the paper. The dark table is gone.
    for (x, y) in [(2, 2), (57, 2), (2, 77), (57, 77)] {
        #expect(pixels.pixels[(y * 60 + x) * 4] > 160)
    }
}

@Test func autoCaptureRequiresAnUninterruptedStableAndSharpPage() {
    let engine = documentEngine()
    let page = tiltedPage()
    let shifted = tiltedPage(offset: 32)
    let blank = flatFrame(width: 480, height: 640)
    for index in 0..<7 {
        let output = engine.process(index.isMultiple(of: 2) ? page : shifted, at: Double(index) * 0.21)
        #expect(output?.page != nil)
        #expect(output?.fire == false)
    }
    for index in 0..<7 {
        let output = engine.process(index == 3 ? blank : page, at: 2 + Double(index) * 0.21)
        #expect(output?.fire == false)
    }

    for index in 0..<5 {
        let output = engine.process(page, at: 4 + Double(index) * 0.21)
        #expect(output?.fire == (index == 4))
    }
    #expect(engine.process(page, at: 5.1)?.fire == false)

    engine.reset()
    for index in 0..<5 {
        let output = engine.process(page, at: 6 + Double(index) * 0.21)
        #expect(output?.fire == (index == 4))
    }
}

@Test func clippedAndTextlessPagesNeverAutoCaptureOrReplaceTheOriginal() throws {
    let engine = documentEngine()
    let clipped = tiltedPage(offset: 110)
    let textless = tiltedPage(hasText: false)
    for index in 0..<6 {
        #expect(engine.process(clipped, at: Double(index) * 0.21)?.page == nil)
    }
    for index in 0..<6 {
        #expect(engine.process(textless, at: 2 + Double(index) * 0.21)?.fire == false)
    }
    // A different still must never reuse the live page corners.
    #expect(engine.process(tiltedPage(), at: 4)?.page != nil)
    let photo = try #require(engine.crop(textless))
    #expect(jpegSize(photo) == CGSize(width: 480, height: 640))
}

#if os(iOS) && DEBUG
@MainActor @Test func manualShutterReturnsTheVisibleStillWithoutPageDetection() async throws {
    let source = FixtureFrameSource(images: [flatFrame(width: 480, height: 640).image])
    let environment = CaptureEnvironment(makeSource: { _ in source }, needsPermission: false)
    var captures: [Data] = []
    let model = DocumentCameraModel(environment: environment) { captures.append($0) }
    model.setViewSize(CGSize(width: 360, height: 640))
    await model.start()
    await model.capture()

    let photo = try #require(captures.first)
    #expect(captures.count == 1)
    #expect(jpegSize(photo) == CGSize(width: 360, height: 640))
    #expect(model.camera.state == .idle)
}
#endif

private func documentEngine() -> DocumentPhotoEngine {
    let engine = DocumentPhotoEngine()
    engine.setViewSize(PixelSize(width: 480, height: 640))
    return engine
}

private func tiltedPage(offset: CGFloat = 0, scale: CGFloat = 1, hasText: Bool = true) -> CameraFrame {
    let frame = CGRect(x: 0, y: 0, width: 480, height: 640)
    let paper = CGRect(x: 0, y: 0, width: 300, height: 440)
    var sheet = CIImage(color: CIColor(red: 0.86, green: 0.86, blue: 0.86)).cropped(to: paper)
    if hasText {
        let ink = CIImage(color: CIColor(red: 0.11, green: 0.11, blue: 0.11))
        for row in 0..<23 {
            let line = CGRect(x: 25, y: 40 + row * 16, width: 170 + (row % 4) * 24, height: 4)
            sheet = ink.cropped(to: line).composited(over: sheet)
        }
    }
    let warped = sheet.applyingFilter("CIPerspectiveTransform", parameters: [
        "inputTopLeft": CIVector(x: 105 + offset, y: 546),
        "inputTopRight": CIVector(x: 379 + offset, y: 514),
        "inputBottomRight": CIVector(x: 400 + offset, y: 105),
        "inputBottomLeft": CIVector(x: 76 + offset, y: 78),
    ])
    let background = CIImage(color: CIColor(red: 0.18, green: 0.18, blue: 0.18)).cropped(to: frame)
    let image = warped.composited(over: background).cropped(to: frame)
    return CameraFrame(image: image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
}
