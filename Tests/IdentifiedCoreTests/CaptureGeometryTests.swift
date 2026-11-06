import Testing
@testable import IdentifiedCore

private func close(_ a: PixelRect?, _ b: PixelRect, tolerance: Double = 0.05) -> Bool {
    guard let a else { return false }
    return abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
}

@Test func aspectFillShowsTheMiddleOfAWiderFrame() {
    // A portrait 1080x1920 buffer in a 390x844 view: the sides are cut off.
    let visible = CaptureGeometry.visibleRect(source: PixelSize(width: 1080, height: 1920), view: PixelSize(width: 390, height: 844))
    let scale = 844.0 / 1920.0
    let width = 390.0 / scale
    #expect(close(visible, PixelRect(x: (1080 - width) / 2, y: 0, width: width, height: 1920)))
}

@Test func aMatchingViewShowsTheWholeFrame() {
    let visible = CaptureGeometry.visibleRect(source: PixelSize(width: 1080, height: 1920), view: PixelSize(width: 540, height: 960))
    #expect(close(visible, PixelRect(x: 0, y: 0, width: 1080, height: 1920)))
}

@Test func anEmptyViewHasNoVisibleRect() {
    #expect(CaptureGeometry.visibleRect(source: PixelSize(width: 1080, height: 1920), view: PixelSize(width: 0, height: 0)) == nil)
}

@Test func cropsTheCardGuideWithBleed() {
    let crop = CaptureGeometry.guideCrop(visible: PixelRect(x: 0, y: 0, width: 1000, height: 800))
    let width = 1000 * 0.82 * 1.08
    let height = width / 1.586
    #expect(close(crop, PixelRect(x: (1000 - width) / 2, y: (800 - height) / 2, width: width, height: height)))
}

@Test func cropsASquareAroundTheFaceCircle() {
    let crop = CaptureGeometry.circleCrop(visible: PixelRect(x: 0, y: 0, width: 720, height: 1280))
    let side = 2 * (104.0 / 300.0) * 720 * 1.2
    #expect(close(crop, PixelRect(x: (720 - side) / 2, y: (1280 - side) / 2, width: side, height: side)))
}

@Test func selfieUploadCropTracksTheDisplayedCircleAndStaysInTheVisibleFrame() {
    let visible = PixelRect(x: 20, y: 30, width: 600, height: 1000)
    let crop = CaptureGeometry.selfieCrop(visible: visible)
    #expect(abs(crop.midX - 320) < 0.001)
    #expect(abs(crop.midY - 530) < 0.001)
    #expect(crop.width == crop.height)
    #expect(crop.x >= visible.x && crop.y >= visible.y)
    #expect(crop.x + crop.width <= visible.x + visible.width)
    #expect(crop.y + crop.height <= visible.y + visible.height)

    let short = PixelRect(x: 10, y: 20, width: 1000, height: 300)
    let shortCrop = CaptureGeometry.selfieCrop(visible: short)
    #expect(shortCrop.y >= short.y && shortCrop.y + shortCrop.height <= short.y + short.height)
}

@Test func sizesTheAnalysisFrameToAboutNinetyThousandPixels() {
    let size = CaptureGeometry.analysisSize(aspect: 390.0 / 844.0)
    #expect(size.width == 204)
    #expect(size.height == 441)
    #expect(CaptureGeometry.analysisSize(aspect: 0.01).width == 120)
}

@Test func flipsARectIntoCoreImageCoordinates() {
    #expect(CaptureGeometry.flippedForCoreImage(PixelRect(x: 10, y: 20, width: 30, height: 40), imageHeight: 100) == PixelRect(x: 10, y: 40, width: 30, height: 40))
}

@Test func fitStagePreservesFullFieldOfViewAndMapsTheStageCircle() throws {
    let sources = [PixelSize(width: 720, height: 1280), PixelSize(width: 1280, height: 720), PixelSize(width: 960, height: 1280), PixelSize(width: 1000, height: 200)]
    let stages = [PixelSize(width: 1080, height: 2400), PixelSize(width: 2400, height: 1080), PixelSize(width: 500, height: 500), PixelSize(width: 100, height: 110)]
    for source in sources { for stage in stages {
        let virtual = try #require(CaptureGeometry.aspectFitStageRect(source: source, stage: stage))
        let scale = min(stage.width / source.width, stage.height / source.height)
        #expect(abs(virtual.width * scale - stage.width) < 1e-9)
        #expect(abs(virtual.height * scale - stage.height) < 1e-9)
        #expect(abs(virtual.midX - source.width / 2) < 1e-9)
        #expect(abs(virtual.midY - source.height / 2) < 1e-9)
        // All four source edges lie within the stage: no camera FoV is lost.
        #expect(virtual.x <= 1e-9 && virtual.y <= 1e-9)
        #expect(virtual.x + virtual.width >= source.width - 1e-9)
        #expect(virtual.y + virtual.height >= source.height - 1e-9)
        let crop = try #require(CaptureGeometry.selfieCaptureRect(source: source, stage: stage))
        let ringDiameter = 2 * CaptureGeometry.ringFraction * min(stage.width, stage.height)
        #expect(abs(2 * CaptureGeometry.ringFraction * min(virtual.width, virtual.height) * scale - ringDiameter) < 1e-9)
        #expect(abs(crop.width - min(ringDiameter * 1.2 / scale, min(source.width, source.height))) < 1e-9)
        #expect(crop.width == crop.height)
        let framing = try #require(CaptureGeometry.selfieFramingRect(source: source, stage: stage))
        let wantedY = source.height / 2
        #expect(abs(framing.midY - wantedY) < 1e-9)
        #expect(abs(crop.midX - max(crop.width / 2, min(source.width - crop.width / 2, framing.midX))) < 1e-9)
        #expect(abs(crop.midY - max(crop.height / 2, min(source.height - crop.height / 2, wantedY))) < 1e-9)
        #expect(crop.x >= 0 && crop.y >= 0)
        #expect(crop.x + crop.width <= source.width && crop.y + crop.height <= source.height)
    } }
}

@Test func portraitAndLandscapeLetterboxesHaveNegativeVirtualOrigins() throws {
    #expect(try #require(CaptureGeometry.aspectFitStageRect(source: .init(width: 720, height: 1280), stage: .init(width: 1080, height: 2400))) == PixelRect(x: 0, y: -160, width: 720, height: 1600))
    #expect(try #require(CaptureGeometry.aspectFitStageRect(source: .init(width: 1280, height: 720), stage: .init(width: 2400, height: 1080))) == PixelRect(x: -160, y: 0, width: 1600, height: 720))
    #expect(try #require(CaptureGeometry.selfieCaptureRect(source: .init(width: 200, height: 1000), stage: .init(width: 1000, height: 200))) == PixelRect(x: 0, y: 400, width: 200, height: 200))
}

@Test func invalidFitInputsHaveNoVirtualOrCaptureRect() {
    for bad in [0.0, -1, .nan, .infinity, -.infinity] {
        for index in 0...3 {
            var d = [720.0, 1280, 1080, 2400]
            d[index] = bad
            let source = PixelSize(width: d[0], height: d[1])
            let stage = PixelSize(width: d[2], height: d[3])
            #expect(CaptureGeometry.aspectFitStageRect(source: source, stage: stage) == nil)
            #expect(CaptureGeometry.selfieCaptureRect(source: source, stage: stage) == nil)
        }
    }
}

@Test func cardGuideMapsVideoFieldIntoPhysicalPhotoWithoutBleed() throws {
    let video = PixelSize(width: 960, height: 1280)
    let matched = try #require(CaptureGeometry.cardCaptureRect(source: video, still: .init(width: 3024, height: 4032)))
    #expect(abs(matched.width - 3024 * 0.82) < 1e-9)
    #expect(abs(matched.midY - 2016) < 1e-9)
    // A wider photo contains the centred video field: do not crop 82% of its entire width.
    let wider = try #require(CaptureGeometry.cardCaptureRect(source: video, still: .init(width: 4000, height: 4000)))
    #expect(abs(wider.width - 3000 * 0.82) < 1e-9)
    #expect(wider.midX == 2000 && wider.midY == 2000)
    #expect(abs(wider.width / wider.height - CardDetector.aspectRatio) < 1e-9)
}
