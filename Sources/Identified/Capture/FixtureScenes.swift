#if DEBUG
import CoreImage

/// Generated camera scenes for running the flow without a camera. Portrait
/// and upright, as `CameraController` delivers frames.
enum FixtureScenes {
    /// A pale ID card with dark text lines on a dark desk, 1080x1920, sized to
    /// sit in the guide of a typical full-screen phone preview (aspect about
    /// 0.46) so auto-capture can fire. On other aspects use the shutter.
    static func card() -> CIImage {
        let size = CGSize(width: 1080, height: 1920)
        let cardWidth = 724.0
        let card = CGRect(x: (size.width - cardWidth) / 2, y: (size.height - cardWidth / 1.586) / 2, width: cardWidth, height: cardWidth / 1.586)
        var image = CIImage(color: CIColor(red: 0.11, green: 0.11, blue: 0.11)).cropped(to: CGRect(origin: .zero, size: size))
        image = CIImage(color: CIColor(red: 0.69, green: 0.69, blue: 0.69)).cropped(to: card).composited(over: image)
        var y = card.minY + 70
        while y < card.maxY - 60 {
            let line = CGRect(x: card.minX + 80, y: y, width: card.width - 160, height: 8)
            image = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: line).composited(over: image)
            y += 30
        }
        return image
    }

    /// A flat frame with no face in it, 720x1280. The selfie screen finds no
    /// landmarks and falls back to the timed sequence, as on a device whose
    /// detector cannot start.
    static func noFace() -> CIImage {
        CIImage(color: CIColor(red: 0.55, green: 0.5, blue: 0.47)).cropped(to: CGRect(x: 0, y: 0, width: 720, height: 1280))
    }
}
#endif
