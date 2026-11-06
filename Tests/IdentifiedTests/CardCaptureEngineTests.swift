import Testing
@testable import Identified
import IdentifiedCore
import IdentifiedTestSupport

@Test func waitsForTheViewSize() {
    let engine = CardCaptureEngine()
    #expect(engine.process(cameraFrame(FrameFixtures.card(176, detail: true)), at: 0) == nil)
}

@Test func analysesAtMostEvery120Milliseconds() {
    let engine = CardCaptureEngine()
    engine.setViewSize(PixelSize(width: 320, height: 240))
    let frame = cameraFrame(FrameFixtures.card())
    #expect(engine.process(frame, at: 0) != nil)
    #expect(engine.process(frame, at: 0.05) == nil)
    #expect(engine.process(frame, at: 0.13) != nil)
}

@Test func firesOnceForACardHeldInTheGuide() {
    let engine = CardCaptureEngine()
    engine.setViewSize(PixelSize(width: 320, height: 240))
    let frame = cameraFrame(FrameFixtures.card(176, detail: true))
    var fires: [Double] = []
    for tick in 0..<45 {
        let now = Double(tick) * 0.12
        if engine.process(frame, at: now)?.fire == true { fires.append(now) }
    }
    #expect(fires.count == 1)
    // 0.75 s when every check passes, 4 s when the card is only detected:
    // either way, well inside the 5.4 s fed.
    #expect((fires.first ?? 99) <= 4.3)
}

@Test func anEmptyFrameNeverFiresAndAsksForTheEdges() {
    let engine = CardCaptureEngine()
    engine.setViewSize(PixelSize(width: 320, height: 240))
    let frame = cameraFrame(FrameFixtures.card())
    let outputs = (0..<45).compactMap { engine.process(frame, at: Double($0) * 0.12) }
    #expect(!outputs.contains { $0.fire })
    #expect(outputs.allSatisfy { $0.hint == .fitEdges })
}

@Test func cropsTheGuideFromAStill() throws {
    let engine = CardCaptureEngine()
    engine.setViewSize(PixelSize(width: 390, height: 844))
    _ = engine.process(flatFrame(width: 1080, height: 1440), at: 0)
    let data = try #require(engine.crop(flatFrame(width: 3024, height: 4032)))
    let size = try #require(jpegSize(data))
    // Exactly 82% of the entire 4:3 photo width, with no bleed.
    #expect(abs(size.width - 3024 * 0.82) <= 2)
    #expect(abs(size.width / size.height - CardDetector.aspectRatio) < 0.01)
}

@Test func fullSourceCardAnalysisIsIndependentOfStageAspect() throws {
    let source = cameraFrame(FrameFixtures.card(176, detail: true))
    let portrait = CardCaptureEngine()
    let landscape = CardCaptureEngine()
    portrait.setViewSize(.init(width: 390, height: 844))
    landscape.setViewSize(.init(width: 844, height: 390))
    let first = try #require(portrait.process(source, at: 0))
    #expect(first == landscape.process(source, at: 0))
    #expect(first.sourceAspect == source.size.width / source.size.height)
    #expect(portrait.crop(source) == landscape.crop(source))
}
