import Testing
@testable import IdentifiedCore

private func format(_ width: Int, _ height: Int, fps30: Bool = true) -> SelfieFormatCandidate {
    .init(width: width, height: height, supports30FPS: fps30)
}

@Test func selfieFormatSelectsTheSmallestQualifyingNativeFourByThreeVideo() {
    let candidates = [format(1920, 1440), format(1440, 1080), format(1280, 960), format(1280, 720)]
    #expect(SelfieFormatSelection.preferredIndex(in: candidates, inputPrioritySupported: true) == 2)
    #expect(SelfieFormatSelection.preferredIndex(in: [format(1920, 1440), format(1440, 1080)], inputPrioritySupported: true) == 1)
    #expect(SelfieFormatSelection.preferredIndex(in: [format(960, 1280)], inputPrioritySupported: true) == 0)
}

@Test func selfieFormatRejectsLargePhotoFormatsWrongAspectsAndMissingThirtyFPS() {
    let rejected = [format(4032, 3024), format(2048, 1536), format(1920, 1080),
                    format(1280, 720), format(640, 480), format(1280, 960, fps30: false),
                    format(0, 960), format(-1280, 960), format(Int.max, Int.max)]
    #expect(SelfieFormatSelection.preferredIndex(in: rejected, inputPrioritySupported: true) == nil)
    #expect(SelfieFormatSelection.preferredIndex(in: rejected + [format(1440, 1080)], inputPrioritySupported: true) == rejected.count)
}

@Test func selfieFormatFallbackKeepsPresetWhenInputPriorityOrCandidatesAreUnavailable() {
    #expect(SelfieFormatSelection.preferredIndex(in: [format(1280, 960)], inputPrioritySupported: false) == nil)
    #expect(SelfieFormatSelection.preferredIndex(in: [], inputPrioritySupported: true) == nil)
    #expect(SelfieFormatSelection.preferredIndex(in: [format(1280, 960), format(1280, 960)], inputPrioritySupported: true) == 0)
}

@Test func selfieFormatFrameRateRangeMustActuallyContainThirtyFPS() {
    #expect(SelfieFormatSelection.supports30FPS(minimum: 15, maximum: 60))
    #expect(SelfieFormatSelection.supports30FPS(minimum: 30, maximum: 30))
    #expect(!SelfieFormatSelection.supports30FPS(minimum: 60, maximum: 120))
    #expect(!SelfieFormatSelection.supports30FPS(minimum: 31, maximum: 60))
    #expect(!SelfieFormatSelection.supports30FPS(minimum: 1, maximum: 29.97))
    #expect(!SelfieFormatSelection.supports30FPS(minimum: .nan, maximum: 60))
    #expect(!SelfieFormatSelection.supports30FPS(minimum: 1, maximum: .infinity))
}
