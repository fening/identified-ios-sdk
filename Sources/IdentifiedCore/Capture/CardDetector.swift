import Foundation

package struct CardBounds: Equatable, Sendable {
    package var left: Double
    package var top: Double
    package var right: Double
    package var bottom: Double

    package init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

/// What the card camera tells the subject. Copy lives in the UI layer.
package enum CardHint: Equatable, Sendable {
    /// "Fit all four edges inside the frame"
    case fitEdges
    /// "Move to better light"
    case moveToLight
    /// "Tilt the ID to remove glare"
    case removeGlare
    /// "Hold still and move closer"
    case holdStillCloser
    /// "Hold steady — capturing automatically"
    case capturing
}

package struct InteriorQuality: Equatable, Sendable {
    package var brightness: Double
    package var glare: Double
    package var sharpness: Double
}

package struct CardAssessment: Equatable, Sendable {
    package var detected: Bool
    package var ready: Bool
    package var bounds: CardBounds
    package var edgeCoverage: Double
    package var straightness: Double
    package var interior: InteriorQuality
    package var hint: CardHint
}

/// A port of `frontend/src/lib/cardAutoCapture.ts`: finds an ID-sized
/// rectangle around the on-screen guide in a small frame, and judges whether
/// the card inside it is lit and sharp enough to capture. Thresholds were tuned
/// against real captures on the web; change them there and here together.
package enum CardDetector {
    package static let aspectRatio = 1.586
    package static let guideWidthFraction = 0.82
    /// The analysed frame is downscaled to about this many pixels.
    package static let analysisPixels = 90_000.0
    /// Minimum time between analysed frames.
    package static let analysisInterval: TimeInterval = 0.12

    static let edgeThreshold: Float = 24
    static let minEdgeCoverage = 0.5
    static let maxStraightness = 0.045
    package static let minSharpness = 6.0
    package static let minBrightness = 48.0
    /// 246, not ~232: a pale card back reads 233–250 under good light and is
    /// not glare. True blowout is caught by the glare ratio.
    package static let maxBrightness = 246.0
    package static let maxGlare = 0.45

    package static func guideBounds(width: Int, height: Int) -> CardBounds {
        let guideWidth = Double(width) * guideWidthFraction
        let guideHeight = guideWidth / aspectRatio
        return CardBounds(
            left: (Double(width) - guideWidth) / 2,
            top: (Double(height) - guideHeight) / 2,
            right: (Double(width) + guideWidth) / 2,
            bottom: (Double(height) + guideHeight) / 2
        )
    }

    package static func assess(_ frame: RGBAFrame) -> CardAssessment {
        let guide = guideBounds(width: frame.width, height: frame.height)
        let luminance = frame.luminance()
        let guideWidth = guide.right - guide.left
        let guideHeight = guide.bottom - guide.top
        let horizontalSearch = max(5, guideWidth * 0.075)
        let verticalSearch = max(5, guideHeight * 0.075)
        let w = frame.width, h = frame.height

        let left = verticalEdge(luminance, w, h, expectedX: guide.left, top: guide.top, bottom: guide.bottom, radius: horizontalSearch)
        let right = verticalEdge(luminance, w, h, expectedX: guide.right, top: guide.top, bottom: guide.bottom, radius: horizontalSearch)
        let top = horizontalEdge(luminance, w, h, expectedY: guide.top, left: guide.left, right: guide.right, radius: verticalSearch)
        let bottom = horizontalEdge(luminance, w, h, expectedY: guide.bottom, left: guide.left, right: guide.right, radius: verticalSearch)

        let bounds = CardBounds(left: left.position, top: top.position, right: right.position, bottom: bottom.position)
        let edgeCoverage = min(left.coverage, right.coverage, top.coverage, bottom.coverage)
        let straightness = max(left.straightness, right.straightness, top.straightness, bottom.straightness)
        let detectedWidth = max(1, bounds.right - bounds.left)
        let detectedHeight = max(1, bounds.bottom - bounds.top)
        let aspect = detectedWidth / detectedHeight
        let aspectAligned = abs(aspect - aspectRatio) / aspectRatio <= 0.14
        let sizeAligned = detectedWidth >= guideWidth * 0.86 && detectedHeight >= guideHeight * 0.86
        let detected = edgeCoverage >= minEdgeCoverage && straightness <= maxStraightness && aspectAligned && sizeAligned

        let interior = assessInterior(frame, luminance, bounds)
        let lightingGood = interior.brightness >= minBrightness && interior.brightness <= maxBrightness && interior.glare <= maxGlare
        let sharpEnough = interior.sharpness >= minSharpness
        // Left/top estimates precede the physical edge by one pixel because
        // the detector uses a centred one-pixel luminance gradient.
        let insideGuide = bounds.left >= guide.left.rounded() - 1 && bounds.top >= guide.top.rounded() - 1
            && bounds.right <= guide.right.rounded() && bounds.bottom <= guide.bottom.rounded()
        let ready = detected && insideGuide && lightingGood && sharpEnough

        var hint = CardHint.fitEdges
        if detected && !insideGuide {
            hint = .fitEdges
        } else if detected && interior.brightness < minBrightness {
            hint = .moveToLight
        } else if detected && (interior.brightness > maxBrightness || interior.glare > maxGlare) {
            hint = .removeGlare
        } else if detected && !sharpEnough {
            hint = .holdStillCloser
        } else if ready {
            hint = .capturing
        }

        return CardAssessment(
            detected: detected, ready: ready, bounds: bounds,
            edgeCoverage: edgeCoverage, straightness: straightness,
            interior: interior, hint: hint
        )
    }

    /// Brightness, glare share and Laplacian sharpness, sampled every third
    /// pixel inside `bounds` inset by 5.
    package static func assessInterior(_ frame: RGBAFrame, _ luminance: [Float], _ bounds: CardBounds) -> InteriorQuality {
        let w = frame.width
        let left = clamp(Int((bounds.left + 5).rounded()), 2, w - 3)
        let right = clamp(Int((bounds.right - 5).rounded()), 2, w - 3)
        let top = clamp(Int((bounds.top + 5).rounded()), 2, frame.height - 3)
        let bottom = clamp(Int((bounds.bottom - 5).rounded()), 2, frame.height - 3)
        var brightnessTotal = 0.0, sharpnessTotal = 0.0
        var glarePixels = 0, samples = 0

        frame.pixels.withUnsafeBufferPointer { data in
            var y = top
            while y <= bottom {
                var x = left
                while x <= right {
                    let index = y * w + x
                    let value = luminance[index]
                    let source = index * 4
                    brightnessTotal += Double(value)
                    if data[source] >= 252 && data[source + 1] >= 252 && data[source + 2] >= 252 { glarePixels += 1 }
                    let laplacian = 4 * value - luminance[index - 1] - luminance[index + 1] - luminance[index - w] - luminance[index + w]
                    sharpnessTotal += Double(abs(laplacian))
                    samples += 1
                    x += 3
                }
                y += 3
            }
        }

        guard samples > 0 else { return InteriorQuality(brightness: 0, glare: 1, sharpness: 0) }
        return InteriorQuality(
            brightness: brightnessTotal / Double(samples),
            glare: Double(glarePixels) / Double(samples),
            sharpness: sharpnessTotal / Double(samples)
        )
    }

    /// Whether the card moved less than 1.8% of the frame on every edge.
    package static func boundsAreStable(_ previous: CardBounds, _ current: CardBounds, frameWidth: Int, frameHeight: Int) -> Bool {
        let xTolerance = Double(frameWidth) * 0.018
        let yTolerance = Double(frameHeight) * 0.018
        return abs(previous.left - current.left) <= xTolerance
            && abs(previous.right - current.right) <= xTolerance
            && abs(previous.top - current.top) <= yTolerance
            && abs(previous.bottom - current.bottom) <= yTolerance
    }

    // MARK: Edges

    private struct EdgeEstimate {
        var position: Double
        var coverage: Double
        var straightness: Double
    }

    private static func verticalEdge(_ luminance: [Float], _ width: Int, _ height: Int, expectedX: Double, top: Double, bottom: Double, radius: Double) -> EdgeEstimate {
        var positions: [Double] = []
        var samples = 0
        let yStart = clamp(Int((top + (bottom - top) * 0.08).rounded()), 2, height - 3)
        let yEnd = clamp(Int((bottom - (bottom - top) * 0.08).rounded()), 2, height - 3)
        let step = max(2, Int((Double(yEnd - yStart) / 42).rounded()))
        let xStart = clamp(Int((expectedX - radius).rounded()), 2, width - 3)
        let xEnd = clamp(Int((expectedX + radius).rounded()), 2, width - 3)

        var y = yStart
        while y <= yEnd {
            var strongest: Float = 0
            var strongestX = Int(expectedX.rounded())
            var x = xStart
            while x <= xEnd {
                let gradient = abs(luminance[y * width + x + 1] - luminance[y * width + x - 1])
                if gradient > strongest {
                    strongest = gradient
                    strongestX = x
                }
                x += 1
            }
            samples += 1
            if strongest >= edgeThreshold { positions.append(Double(strongestX)) }
            y += step
        }
        return estimate(positions, samples: samples, expected: expectedX, span: bottom - top)
    }

    private static func horizontalEdge(_ luminance: [Float], _ width: Int, _ height: Int, expectedY: Double, left: Double, right: Double, radius: Double) -> EdgeEstimate {
        var positions: [Double] = []
        var samples = 0
        let xStart = clamp(Int((left + (right - left) * 0.08).rounded()), 2, width - 3)
        let xEnd = clamp(Int((right - (right - left) * 0.08).rounded()), 2, width - 3)
        let step = max(2, Int((Double(xEnd - xStart) / 54).rounded()))
        let yStart = clamp(Int((expectedY - radius).rounded()), 2, height - 3)
        let yEnd = clamp(Int((expectedY + radius).rounded()), 2, height - 3)

        var x = xStart
        while x <= xEnd {
            var strongest: Float = 0
            var strongestY = Int(expectedY.rounded())
            var y = yStart
            while y <= yEnd {
                let gradient = abs(luminance[(y + 1) * width + x] - luminance[(y - 1) * width + x])
                if gradient > strongest {
                    strongest = gradient
                    strongestY = y
                }
                y += 1
            }
            samples += 1
            if strongest >= edgeThreshold { positions.append(Double(strongestY)) }
            x += step
        }
        return estimate(positions, samples: samples, expected: expectedY, span: right - left)
    }

    private static func estimate(_ positions: [Double], samples: Int, expected: Double, span: Double) -> EdgeEstimate {
        let position = positions.isEmpty ? expected : median(positions)
        return EdgeEstimate(
            position: position,
            coverage: samples > 0 ? Double(positions.count) / Double(samples) : 0,
            straightness: positions.isEmpty ? 1 : deviation(positions, around: position) / max(1, span)
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func deviation(_ values: [Double], around center: Double) -> Double {
        (values.reduce(0) { $0 + ($1 - center) * ($1 - center) } / Double(values.count)).squareRoot()
    }
}

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    max(lower, min(upper, value))
}
