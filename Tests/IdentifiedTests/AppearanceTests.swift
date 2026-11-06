import SwiftUI
import Testing
@testable import Identified

@Test func defaultsReproduceTheWebFlow() {
    let appearance = Appearance()
    #expect(appearance.light.accent == Color(hex: 0xEF6D5B))
    #expect(appearance.light.background == Color(hex: 0xFBFAF6))
    #expect(appearance.dark.background == Color(hex: 0x102A28))
    #expect(appearance.cornerRadius == 16)
    #expect(appearance.showsLockup)
    #expect(appearance.colorScheme == .system)
    #expect(appearance.fontFamily == nil)
}

@Test func anAccentAppliesToBothSchemes() {
    let appearance = Appearance(accent: .indigo, fontFamily: "Inter", showsLockup: false)
    #expect(appearance.light.accent == .indigo)
    #expect(appearance.dark.accent == .indigo)
    #expect(appearance.light.background == Appearance.Palette.light.background)
    #expect(appearance.fontFamily == "Inter")
    #expect(!appearance.showsLockup)
}

@Test func theThemePicksThePaletteForTheScheme() {
    let appearance = Appearance()
    #expect(Theme(appearance: appearance, scheme: .light).palette.background == appearance.light.background)
    #expect(Theme(appearance: appearance, scheme: .dark).palette.background == appearance.dark.background)
}

@Test func theConfigurationDefaultsToTheDefaultAppearance() {
    let config = IdentifiedConfiguration(sessionToken: "tok")
    #expect(config.appearance.light.accent == Appearance().light.accent)
}
