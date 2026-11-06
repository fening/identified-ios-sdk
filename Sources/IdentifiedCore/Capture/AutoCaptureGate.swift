import Foundation

/// Decides when a held-still card is captured without the shutter.
package struct AutoCaptureGate: Sendable {
    package static let readyHold: TimeInterval = 0.75
    package static let detectedHold: TimeInterval = 4.0

    private var previous: CardBounds?
    private var stableSince: TimeInterval?
    private var fired = false

    package init() {}

    /// Feed every analysed frame. Returns true exactly once, on the frame that
    /// should be captured.
    package mutating func observe(_ assessment: CardAssessment, frameWidth: Int, frameHeight: Int, at now: TimeInterval) -> Bool {
        guard !fired else { return false }
        guard assessment.ready || assessment.detected else {
            stableSince = nil
            previous = nil
            return false
        }
        defer { previous = assessment.bounds }
        let hold = assessment.ready ? Self.readyHold : Self.detectedHold
        guard let previous, CardDetector.boundsAreStable(previous, assessment.bounds, frameWidth: frameWidth, frameHeight: frameHeight) else {
            stableSince = now
            return false
        }
        if let stableSince, now - stableSince >= hold {
            fired = true
            return true
        }
        return false
    }

    /// After a retake.
    package mutating func reset() {
        self = AutoCaptureGate()
    }
}
