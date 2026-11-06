import SwiftUI

/// The appearance resolved for the current colour scheme. Views read colours,
/// fonts and radii from here and never from literals.
struct Theme {
    let appearance: Appearance
    let palette: Appearance.Palette

    init(appearance: Appearance, scheme: ColorScheme) {
        self.appearance = appearance
        palette = scheme == .dark ? appearance.dark : appearance.light
    }

    var radius: CGFloat { appearance.cornerRadius }
    var progressEnd: Color {
        palette.accent == Appearance.Palette.light.accent ? Color(hex: 0xF6BB64) : palette.accent
    }

    /// Decorative web surfaces fall back to the host's surface for a custom
    /// canvas; these are internal tokens, not additions to the public palette.
    private var defaultLightCanvas: Bool { palette.background == Appearance.Palette.light.background }
    private var defaultDarkCanvas: Bool { palette.background == Appearance.Palette.dark.background }
    var cardSurface: Color {
        defaultLightCanvas && palette.surface == Appearance.Palette.light.surface ? palette.background : palette.surface
    }
    var warmSurface: Color {
        defaultLightCanvas ? Color(hex: 0xF5F0E7) : palette.surface
    }
    var lilacBadge: Color {
        defaultLightCanvas || defaultDarkCanvas ? Color(hex: 0xDCD6FF) : palette.surface
    }
    var lilacSurface: Color {
        defaultLightCanvas ? Color(hex: 0xF3F0FF) : palette.surface
    }
    var lilacBorder: Color {
        defaultLightCanvas ? Color(hex: 0xDCD6FF) : defaultDarkCanvas ? Color(hex: 0xDCD6FF).opacity(0.3) : palette.border
    }
    var coralHalo: Color {
        defaultLightCanvas && palette.accent == Appearance.Palette.light.accent ? Color(hex: 0xFFF0EA) : palette.accent.opacity(0.12)
    }

    /// Body text at the web's sizes, scaling with Dynamic Type.
    func body(_ size: CGFloat = 16, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        font(appearance.fontFamily, defaultName: Self.bodyFontName(weight), size: size, weight: weight, style: style)
    }

    /// Headings: the web's Outfit sizes, 30 for a screen title.
    func heading(_ size: CGFloat = 30, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        font(appearance.headingFontFamily ?? appearance.fontFamily, defaultName: weight == .bold ? "IdentifiedOutfit-Bold" : weight == .medium ? "IdentifiedOutfit-Medium" : "IdentifiedOutfit-SemiBold", size: size, weight: weight, style: style)
    }

    static func bodyFontName(_ weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return "IdentifiedDMSans-Bold" }
        if weight == .semibold { return "IdentifiedDMSans-SemiBold" }
        if weight == .medium { return "IdentifiedDMSans-Medium" }
        return "IdentifiedDMSans-Regular"
    }

    private func font(_ family: String?, defaultName: String, size: CGFloat, weight: Font.Weight, style: Font.TextStyle) -> Font {
        guard let family else {
            _ = BundledFonts.register
            return .custom(defaultName, size: size, relativeTo: style)
        }
        return .custom(family, size: size, relativeTo: style).weight(weight)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(appearance: Appearance(), scheme: .light)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Resolves the appearance against the scheme the flow is shown in, and pins
/// the scheme when the host asked for one.
struct Themed: ViewModifier {
    let appearance: Appearance
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let scheme: ColorScheme = switch appearance.colorScheme {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
        content
            .environment(\.theme, Theme(appearance: appearance, scheme: scheme))
            .preferredColorScheme(appearance.colorScheme == .system ? nil : scheme)
            .tint(Theme(appearance: appearance, scheme: scheme).palette.accent)
    }
}
