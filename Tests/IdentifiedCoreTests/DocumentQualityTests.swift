import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func saysTooDarkFirst() {
    let quality = DocumentQuality.assess(FrameFixtures.page(20, stripes: true))
    #expect(quality.hint == .tooDark)
    #expect(!quality.ready)
}

@Test func saysGlareBeforeBrightness() {
    let quality = DocumentQuality.assess(FrameFixtures.page(255, stripes: true))
    #expect(quality.hint == .tooMuchGlare)
}

@Test func saysTooBrightWithoutGlare() {
    let quality = DocumentQuality.assess(FrameFixtures.page(250))
    #expect(quality.hint == .tooBright)
}

@Test func saysBlurryForAFeaturelessPage() {
    let quality = DocumentQuality.assess(FrameFixtures.page(176))
    #expect(quality.hint == .blurry)
}

@Test func saysSharpForReadableText() {
    let quality = DocumentQuality.assess(FrameFixtures.page(176, stripes: true))
    #expect(quality.hint == .looksSharp)
    #expect(quality.ready)
}
