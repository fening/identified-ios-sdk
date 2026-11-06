import IdentifiedCore

package enum FrameFixtures {
    /// A dark 320x240 frame, optionally with a uniform card of `cardValue`
    /// filling the guide, optionally with dark text lines on the card.
    package static func card(_ cardValue: UInt8? = nil, detail: Bool = false, width: Int = 320, height: Int = 240) -> RGBAFrame {
        var pixels = [UInt8](repeating: 28, count: width * height * 4)
        for pixel in 0..<(width * height) { pixels[pixel * 4 + 3] = 255 }
        func paint(_ x: Int, _ y: Int, _ value: UInt8) {
            let index = (y * width + x) * 4
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
        }
        if let cardValue {
            let bounds = CardDetector.guideBounds(width: width, height: height)
            let left = Int(bounds.left.rounded()), right = Int(bounds.right.rounded())
            let top = Int(bounds.top.rounded()), bottom = Int(bounds.bottom.rounded())
            for y in top...bottom { for x in left...right { paint(x, y, cardValue) } }
            if detail {
                var y = top + 32
                while y < bottom - 24 {
                    for line in 0..<2 { for x in (left + 36)..<(right - 36) { paint(x, y + line, 65) } }
                    y += 9
                }
            }
        }
        return RGBAFrame(width: width, height: height, pixels: pixels)
    }

    /// A uniform frame, optionally striped with dark text-like lines across it.
    package static func page(_ value: UInt8, stripes: Bool = false, width: Int = 320, height: Int = 240) -> RGBAFrame {
        var pixels = [UInt8](repeating: value, count: width * height * 4)
        for pixel in 0..<(width * height) { pixels[pixel * 4 + 3] = 255 }
        if stripes {
            var y = 4
            while y < height - 4 {
                for line in 0..<2 {
                    for x in 0..<width {
                        let index = ((y + line) * width + x) * 4
                        pixels[index] = 65
                        pixels[index + 1] = 65
                        pixels[index + 2] = 65
                    }
                }
                y += 9
            }
        }
        return RGBAFrame(width: width, height: height, pixels: pixels)
    }
}
