import Foundation

/// What the document camera tells the subject. Copy lives in the UI layer.
package enum DocumentHint: Equatable, Sendable {
    /// "Too dark — move into better light"
    case tooDark
    /// "Too much glare — tilt the document away from the light"
    case tooMuchGlare
    /// "Too bright — move out of direct light"
    case tooBright
    /// "Hold steady — the text looks blurry"
    case blurry
    /// "Looks sharp — you can take the photo"
    case looksSharp
}

/// A port of `frontend/src/lib/documentQuality.ts`. Shape-agnostic: a proof of
/// address may be any size or orientation, so only what defeats OCR is judged.
/// It reports and never blocks; the server refuses an unreadable photo.
package struct DocumentQuality: Equatable, Sendable {
    package var interior: InteriorQuality
    package var ready: Bool
    package var hint: DocumentHint

    package static func assess(_ frame: RGBAFrame) -> DocumentQuality {
        let inset = 0.05
        let bounds = CardBounds(
            left: Double(frame.width) * inset,
            top: Double(frame.height) * inset,
            right: Double(frame.width) * (1 - inset),
            bottom: Double(frame.height) * (1 - inset)
        )
        let q = CardDetector.assessInterior(frame, frame.luminance(), bounds)
        // Ordered by how badly each defeats OCR, and by what the subject can act on.
        let hint: DocumentHint =
            q.brightness < CardDetector.minBrightness ? .tooDark
            : q.glare > CardDetector.maxGlare ? .tooMuchGlare
            : q.brightness > CardDetector.maxBrightness ? .tooBright
            : q.sharpness < CardDetector.minSharpness ? .blurry
            : .looksSharp
        let ready = q.brightness >= CardDetector.minBrightness
            && q.brightness <= CardDetector.maxBrightness
            && q.glare <= CardDetector.maxGlare
            && q.sharpness >= CardDetector.minSharpness
        return DocumentQuality(interior: q, ready: ready, hint: hint)
    }
}
