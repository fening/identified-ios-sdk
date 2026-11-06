import SwiftUI

/// How the verification flow looks. Every screen reads its colours, fonts and
/// corner radius from here; the defaults reproduce the hosted web flow.
///
/// The session's `branding.primary_color` is not applied, as on the web: this
/// is the only theming input.
public struct Appearance: Sendable {
    public struct Palette: Sendable {
        public var accent: Color
        /// Text and icons on an accent-filled button. The web puts its label
        /// colour on coral, not white.
        public var onAccent: Color
        public var background: Color
        /// Cards and fields on the background.
        public var surface: Color
        public var textPrimary: Color
        public var textSecondary: Color
        public var border: Color
        public var error: Color
        public var success: Color
        public var warning: Color

        public init(
            accent: Color, onAccent: Color, background: Color, surface: Color,
            textPrimary: Color, textSecondary: Color, border: Color,
            error: Color, success: Color, warning: Color
        ) {
            self.accent = accent
            self.onAccent = onAccent
            self.background = background
            self.surface = surface
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.border = border
            self.error = error
            self.success = success
            self.warning = warning
        }

        /// The web flow in light mode (`frontend/tailwind.config.js` brand colours).
        public static let light = Palette(
            accent: Color(hex: 0xEF6D5B), onAccent: Color(hex: 0x172A30), background: Color(hex: 0xFBFAF6), surface: .white,
            textPrimary: Color(hex: 0x193A36), textSecondary: Color(hex: 0x56716B), border: Color(hex: 0xE2E8DF),
            error: Color(hex: 0xDC2626), success: Color(hex: 0x237F74), warning: Color(hex: 0xD97706)
        )

        /// The web flow in dark mode.
        public static let dark = Palette(
            accent: Color(hex: 0xEF6D5B), onAccent: Color(hex: 0x172A30), background: Color(hex: 0x102A28), surface: Color(hex: 0x193A36),
            textPrimary: Color(hex: 0xFBFAF6), textSecondary: Color(hex: 0x7A918C), border: Color(hex: 0x193A36),
            error: Color(hex: 0xF87171), success: Color(hex: 0x40A99A), warning: Color(hex: 0xFBBF24)
        )
    }

    public enum ColorSchemePreference: Sendable {
        /// Follow the device.
        case system, light, dark
    }

    public var light: Palette
    public var dark: Palette
    /// A font family for body text, registered by your app. `nil` is the system font.
    public var fontFamily: String?
    /// A font family for headings. `nil` uses `fontFamily`.
    public var headingFontFamily: String?
    /// Buttons, fields and cards.
    public var cornerRadius: CGFloat
    /// Whether the identified.cc lockup appears in the flow's header.
    public var showsLockup: Bool
    public var colorScheme: ColorSchemePreference

    public init(
        light: Palette = .light,
        dark: Palette = .dark,
        fontFamily: String? = nil,
        headingFontFamily: String? = nil,
        cornerRadius: CGFloat = 16,
        showsLockup: Bool = true,
        colorScheme: ColorSchemePreference = .system
    ) {
        self.light = light
        self.dark = dark
        self.fontFamily = fontFamily
        self.headingFontFamily = headingFontFamily
        self.cornerRadius = cornerRadius
        self.showsLockup = showsLockup
        self.colorScheme = colorScheme
    }

    /// The default look with your accent colour in both schemes.
    public init(
        accent: Color,
        fontFamily: String? = nil,
        headingFontFamily: String? = nil,
        cornerRadius: CGFloat = 16,
        showsLockup: Bool = true,
        colorScheme: ColorSchemePreference = .system
    ) {
        var light = Palette.light
        var dark = Palette.dark
        light.accent = accent
        dark.accent = accent
        self.init(light: light, dark: dark, fontFamily: fontFamily, headingFontFamily: headingFontFamily,
                  cornerRadius: cornerRadius, showsLockup: showsLockup, colorScheme: colorScheme)
    }
}

extension Color {
    /// `0xRRGGBB` in sRGB.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
