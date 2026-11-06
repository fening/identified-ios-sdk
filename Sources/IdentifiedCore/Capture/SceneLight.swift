import Foundation

/// A port of `frontend/src/hooks/useSceneLight.ts`: two dim samples in a row
/// turn the screen into a fill light for the selfie, and it stays on.
package struct SceneLight: Equatable, Sendable {
    package static let sampleInterval: TimeInterval = 0.5
    static let darkBelow = 45.0
    static let darkSamples = 2
    /// A camera still starting up reads black; that is not a dark room.
    static let noPictureBelow = 3.0

    package private(set) var dark = false
    private var streak = 0

    package init() {}

    package mutating func observe(meanLuminance mean: Double) {
        guard !dark, mean >= Self.noPictureBelow else { return }
        guard mean < Self.darkBelow else {
            streak = 0
            return
        }
        streak += 1
        if streak >= Self.darkSamples { dark = true }
    }

    package static func meanLuminance(_ frame: RGBAFrame) -> Double {
        let plane = frame.luminance()
        return plane.isEmpty ? 0 : plane.reduce(0) { $0 + Double($1) } / Double(plane.count)
    }
}
