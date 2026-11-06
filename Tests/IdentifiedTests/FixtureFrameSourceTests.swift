import CoreImage
import Foundation
import Testing
@testable import Identified

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))

@Test func fixtureSourceStreamsFramesUntilStopped() async throws {
    let source = FixtureFrameSource(images: [grey], framesPerSecond: 50)
    let counter = Counter()
    try await source.start { _ in counter.increment() }
    try await Task.sleep(for: .milliseconds(200))
    source.stop()
    let afterStop = counter.count
    #expect(afterStop >= 3)
    try await Task.sleep(for: .milliseconds(100))
    #expect(counter.count <= afterStop + 1)
}

@Test func fixtureSourceTakesAStillOfTheCurrentImage() async throws {
    let source = FixtureFrameSource(images: [grey], framesPerSecond: 50)
    let still = try await source.capturePhoto()
    #expect(still.size.width == 64 && still.size.height == 48)
}

@Test func findsNoFaceInABlankFrame() {
    #expect(FaceLandmarkDetector().detect(in: CameraFrame(image: grey)) == nil)
}
