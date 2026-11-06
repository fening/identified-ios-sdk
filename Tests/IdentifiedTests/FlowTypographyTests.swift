import CoreText
import SwiftUI
import Testing
@testable import Identified

@Test func bundledStaticFacesResolveByTheirPostScriptNames() {
    _ = BundledFonts.register
    for name in BundledFonts.names {
        let font = CTFontCreateWithName(name as CFString, 16, nil)
        #expect(CTFontCopyPostScriptName(font) as String == name)
    }
}

@Test func progressUsesAmberOnlyWithTheDefaultCoralAccent() {
    for scheme in [ColorScheme.light, .dark] {
        let standard = Theme(appearance: Appearance(), scheme: scheme)
        #expect(standard.progressEnd == Color(hex: 0xF6BB64))
        let custom = Theme(appearance: Appearance(accent: .indigo), scheme: scheme)
        #expect(custom.progressEnd == custom.palette.accent)
    }
}

@Test func explicitHostFontsOverrideBundledDefaults() {
    let theme = Theme(appearance: Appearance(fontFamily: "HostBody", headingFontFamily: "HostHeading"), scheme: .light)
    #expect(theme.body(16) == Font.custom("HostBody", size: 16, relativeTo: .body).weight(.regular))
    #expect(theme.heading(30) == Font.custom("HostHeading", size: 30, relativeTo: .largeTitle).weight(.semibold))
    let bodyOnly = Theme(appearance: Appearance(fontFamily: "HostBody"), scheme: .dark)
    #expect(bodyOnly.heading(22) == Font.custom("HostBody", size: 22, relativeTo: .largeTitle).weight(.semibold))
}

#if os(iOS)
import UIKit

@MainActor @Test func headerBrandMarkDecodesFromTheSDKBundle() throws {
    let image = try #require(BrandMarkAsset.image)
    #expect(image.cgImage != nil)
    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    #expect(image.renderingMode == .alwaysOriginal)
}

@MainActor @Test func selfieReviewPreservesNaturalImageRatioAtFullWidth() {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
    }
    let host = UIHostingController(rootView: SelfieReviewImage(image: image))
    let size = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
    #expect(abs(size.width - 320) < 1)
    #expect(abs(size.height - 240) < 1)
}

@MainActor @Test func portraitSelfieReviewFitsTheFullImageWithinBoundedHeight() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1280)).image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 720, height: 1280))
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 720, height: 80))
        UIColor.green.setFill()
        context.fill(CGRect(x: 0, y: 1200, width: 720, height: 80))
    }
    let view = SelfieReviewImage(image: image).frame(width: 320)
    let host = UIHostingController(rootView: view)
    let size = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
    #expect(size.height <= 320)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let rendered = try #require(renderer.uiImage?.cgImage)
    // Both source ends survive fitting; clipping/zoom would discard these bands.
    for (y, channel) in [(8, 0), (Int(rendered.height) - 9, 1)] {
        let patch = try #require(rendered.cropping(to: CGRect(x: rendered.width / 2, y: y, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(pixel[channel] > 200)
    }
}

@MainActor @Test func primaryActionExpandsForAccessibilityType() {
    let normal = UIHostingController(rootView: PrimaryButton(title: "Submit for review", action: {})
        .environment(\.dynamicTypeSize, .large))
    let accessible = UIHostingController(rootView: PrimaryButton(title: "Submit for review", action: {})
        .environment(\.dynamicTypeSize, .accessibility5))
    let normalSize = normal.sizeThatFits(in: CGSize(width: 240, height: 1000))
    let accessibleSize = accessible.sizeThatFits(in: CGSize(width: 240, height: 1000))
    #expect(normalSize.height >= 54)
    #expect(accessibleSize.height > normalSize.height)
}

@MainActor @Test func captureBriefWrapsInsteadOfClippingOnNarrowViewports() {
    let brief = CaptureBriefView(lead: "Take a clear photo of the front of your ID.", points: [
        "Keep all four corners visible and make sure the details can be read.",
        "Avoid glare and hold your phone steady.",
    ])
    let host = UIHostingController(rootView: brief.environment(\.dynamicTypeSize, .accessibility1))
    let wide = host.sizeThatFits(in: CGSize(width: 390, height: 2000))
    let narrow = host.sizeThatFits(in: CGSize(width: 240, height: 2000))
    #expect(narrow.height > wide.height)
    #expect(narrow.width <= 240)
}

@Test func hubAndStatusDoNotExposeNavigationBack() {
    #expect(!FlowRoute.checklist.showsBack)
    #expect(!FlowRoute.status.showsBack)
    #expect(FlowRoute.consent.showsBack)
    #expect(FlowRoute.documents(startAt: nil).showsBack)
}
#endif
