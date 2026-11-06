import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func acceptsASharpEvenlyLitIDAlignedWithTheGuide() {
    let assessment = CardDetector.assess(FrameFixtures.card(176, detail: true))
    #expect(assessment.detected)
    #expect(assessment.ready)
    #expect(assessment.hint == .capturing)
}

@Test func doesNotDetectACardInAUniformFrame() {
    let assessment = CardDetector.assess(FrameFixtures.card())
    #expect(!assessment.detected)
    #expect(!assessment.ready)
    #expect(assessment.hint == .fitEdges)
}

@Test func waitsForASharperImageBeforeAutoCapture() {
    let assessment = CardDetector.assess(FrameFixtures.card(176))
    #expect(assessment.detected)
    #expect(!assessment.ready)
    #expect(assessment.hint == .holdStillCloser)
}

@Test func rejectsAnOverexposedCard() {
    let assessment = CardDetector.assess(FrameFixtures.card(255, detail: true))
    #expect(assessment.detected)
    #expect(!assessment.ready)
    #expect(assessment.hint == .removeGlare)
}

@Test func acceptsAPaleCardBack() {
    let assessment = CardDetector.assess(FrameFixtures.card(240, detail: true))
    #expect(assessment.detected)
    #expect(assessment.ready)
}

@Test func aCardTooDarkToStandOutIsNotDetected() {
    // 44 on a 28 background: the edge gradient never reaches 24.
    let assessment = CardDetector.assess(FrameFixtures.card(44, detail: true))
    #expect(!assessment.detected)
    #expect(assessment.hint == .fitEdges)
}

@Test func toleratesSmallMovement() {
    let baseline = CardBounds(left: 30, top: 40, right: 290, bottom: 204)
    #expect(CardDetector.boundsAreStable(baseline, CardBounds(left: 33, top: 42, right: 292, bottom: 202), frameWidth: 320, frameHeight: 240))
}

@Test func resetsStabilityAfterMaterialMovement() {
    let baseline = CardBounds(left: 30, top: 40, right: 290, bottom: 204)
    #expect(!CardDetector.boundsAreStable(baseline, CardBounds(left: 43, top: 40, right: 303, bottom: 204), frameWidth: 320, frameHeight: 240))
}

@Test func cardsBeyondAnySavedGuideEdgeCannotAutoCapture() {
    let source = FrameFixtures.card(176, detail: true)
    for (dx, dy) in [(-5, 0), (5, 0), (0, -5), (0, 5)] {
        var pixels = FrameFixtures.card().pixels
        for y in 0..<source.height {
            for x in 0..<source.width {
                let sx = x - dx, sy = y - dy
                guard sx >= 0, sx < source.width, sy >= 0, sy < source.height else { continue }
                for channel in 0..<4 {
                    pixels[(y * source.width + x) * 4 + channel] = source.pixels[(sy * source.width + sx) * 4 + channel]
                }
            }
        }
        let result = CardDetector.assess(RGBAFrame(width: source.width, height: source.height, pixels: pixels))
        #expect(result.detected)
        #expect(!result.ready)
        #expect(result.hint == .fitEdges)
    }
}
