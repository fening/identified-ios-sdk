import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

@Test func oneDimSampleIsNotADarkScene() {
    var light = SceneLight()
    light.observe(meanLuminance: 30)
    #expect(!light.dark)
}

@Test func twoDimSamplesInARowAreADarkScene() {
    var light = SceneLight()
    light.observe(meanLuminance: 30)
    light.observe(meanLuminance: 30)
    #expect(light.dark)
}

@Test func aBrightSampleResetsTheStreak() {
    var light = SceneLight()
    light.observe(meanLuminance: 30)
    light.observe(meanLuminance: 90)
    light.observe(meanLuminance: 30)
    #expect(!light.dark)
}

@Test func ignoresACameraThatHasNoPictureYet() {
    var light = SceneLight()
    light.observe(meanLuminance: 1)
    light.observe(meanLuminance: 1)
    #expect(!light.dark)
}

@Test func staysDarkOnceTheFillLightIsOn() {
    // The fill light brightens the scene; turning it off again would flicker.
    var light = SceneLight()
    light.observe(meanLuminance: 30)
    light.observe(meanLuminance: 30)
    light.observe(meanLuminance: 200)
    #expect(light.dark)
}

@Test func measuresMeanLuminance() {
    #expect(abs(SceneLight.meanLuminance(FrameFixtures.page(100)) - 100) < 0.01)
}
