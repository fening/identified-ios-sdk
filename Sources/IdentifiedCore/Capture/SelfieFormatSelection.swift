import Foundation

/// Platform-neutral metadata only; no camera handles or image buffers.
package struct SelfieFormatCandidate: Equatable, Sendable {
    package let width: Int
    package let height: Int
    package let supports30FPS: Bool

    package init(width: Int, height: Int, supports30FPS: Bool) {
        self.width = width
        self.height = height
        self.supports30FPS = supports30FPS
    }
}

package enum SelfieFormatSelection {
    package static func supports30FPS(minimum: Double, maximum: Double) -> Bool {
        minimum.isFinite && maximum.isFinite && minimum <= 30 && maximum >= 30
    }

    /// Prefer the smallest native 4:3 video format at least 1280x960, capped
    /// at 1920x1440. Nil keeps the existing 720p session-preset fallback.
    package static func preferredIndex(in candidates: [SelfieFormatCandidate], inputPrioritySupported: Bool) -> Int? {
        guard inputPrioritySupported else { return nil }
        return candidates.indices.filter { index in
            let format = candidates[index]
            let width = max(format.width, format.height)
            let height = min(format.width, format.height)
            guard format.supports30FPS, width >= 1280, height >= 960,
                  width <= 1920, height <= 1440 else { return false }
            return width * 3 == height * 4
        }.min { lhs, rhs in
            let left = candidates[lhs].width * candidates[lhs].height
            let right = candidates[rhs].width * candidates[rhs].height
            return left == right ? lhs < rhs : left < right
        }
    }
}
