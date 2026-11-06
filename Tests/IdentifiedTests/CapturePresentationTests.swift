#if os(iOS)
import SwiftUI
import UIKit
import QuartzCore
import Testing
@testable import Identified
import IdentifiedCore

@MainActor
@Test func cameraFaceGuidesDecodeFromLoosePNGsAndContainVisibleLineArt() throws {
    for direction in ["center", "left", "right"] {
        let image = try #require(CameraFaceGuideAssets.image(direction: direction))
        let pixels = try #require(image.cgImage)
        #expect(pixels.width == 1024 && pixels.height == 1024)
        var rgba = [UInt8](repeating: 0, count: 64 * 64 * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: 64, height: 64,
                                                 bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(pixels, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        #expect(alpha.contains(where: { $0 > 0 }), "Missing line art for \(direction)")
        #expect(alpha.contains(0), "Guide must preserve the transparent camera window")
    }
    #expect(CameraFaceGuideAssets.image(direction: "unsupported") == nil)
}

private func cameraSnapshotDirectory() throws -> URL {
    let directory = ProcessInfo.processInfo.environment["IDENTIFIED_CAPTURE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("capture-presentation")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    print("IDENTIFIED_CAPTURE_SNAPSHOT_DIR=\(directory.path)")
    return directory
}

/// Render the UIKit-backed hierarchy, including SwiftUI ScrollView's
/// UIScrollView. ImageRenderer intentionally omits those platform subviews.
/// Window mutation is synchronous on MainActor and restored before returning.
@MainActor
private func attachedCameraSnapshot<V: View>(_ view: V, size: CGSize, preferLayerRendering: Bool = false) throws -> UIImage {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let priorKey = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
    let bounds = CGRect(origin: .zero, size: size)
    let window = priorKey?.windowScene.map { UIWindow(windowScene: $0) }
        ?? scenes.first.map { UIWindow(windowScene: $0) }
        ?? UIWindow(frame: bounds)
    let host = UIHostingController(rootView: view.frame(width: size.width, height: size.height).ignoresSafeArea())
    defer {
        window.resignKey()
        window.isHidden = true
        window.rootViewController = nil
        priorKey?.makeKey()
    }
    UIView.performWithoutAnimation {
        window.frame = bounds
        window.backgroundColor = .black
        window.rootViewController = host
        window.makeKeyAndVisible()
        // Scene attachment can reset the frame to its screen's bounds.
        window.frame = bounds
        host.view.frame = bounds
        host.view.backgroundColor = .black
        window.setNeedsLayout()
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Library test runners may have no scene committed to the render
        // server. Realize the attached view/layer tree before either backend.
        func displayTree(_ view: UIView) {
            view.layoutIfNeeded()
            for child in view.subviews { displayTree(child) }
            view.setNeedsDisplay()
            view.layer.displayIfNeeded()
        }
        displayTree(host.view)
        window.layer.layoutIfNeeded()
        CATransaction.flush()
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    if !preferLayerRendering {
        var renderedHierarchy = false
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(bounds)
            renderedHierarchy = host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        if renderedHierarchy { return image }
    }
    // In an app-less package runner drawHierarchy can return false because
    // the view has never been committed to the render server. CALayer renders
    // the same attached hierarchy, including UIScrollView and its children,
    // without requiring that server commit. Pixel assertions remain mandatory
    // at the call sites; a successfully allocated blank bitmap is not proof.
    print("IDENTIFIED_CAMERA_SNAPSHOT_RENDERER=CALayer.render \(Int(size.width))x\(Int(size.height))")
    host.view.layoutIfNeeded()
    host.view.layer.displayIfNeeded()
    CATransaction.flush()
    return renderer.image { context in
        UIColor.black.setFill()
        context.fill(bounds)
        host.view.layer.render(in: context.cgContext)
    }
}

/// Count contrasting pixels in a feedback-only area. The circle, guide and
/// top chips are outside this region, so a missing ScrollView cannot pass.
private func feedbackPixelCount(_ image: UIImage, in region: CGRect, fillLight: Bool = false) throws -> Int {
    let source = try #require(image.cgImage)
    let cropBounds = region.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
    let cropped = try #require(source.cropping(to: cropBounds))
    let width = cropped.width
    let height = cropped.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    try rgba.withUnsafeMutableBytes { bytes in
        let context = try #require(CGContext(data: bytes.baseAddress, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return stride(from: 0, to: rgba.count, by: 4).filter { index in
        if fillLight { return min(rgba[index], rgba[index + 1], rgba[index + 2]) < 180 }
        return max(rgba[index], rgba[index + 1], rgba[index + 2]) > 40
    }.count
}

@MainActor
@Test func feedbackPixelAssertionRejectsBlankStage() throws {
    let size = CGSize(width: 390, height: 844)
    let black = try attachedCameraSnapshot(Color.black, size: size)
    let belowRing = SelfieStageLayout.hintFrame(size: size)
    #expect(try feedbackPixelCount(black, in: belowRing) == 0)
    let hint = try attachedCameraSnapshot(
        SelfieCameraStage(presentation: .init(phase: .left, status: .ok, yaw: -0.2)) { Color.black }, size: size)
    #expect(try feedbackPixelCount(hint, in: belowRing) > 24,
            "Window-attached ScrollView hint must produce pixels below the ring")
}

@MainActor
@Test func cameraLayerSnapshotFallbackIncludesScrollViewHint() throws {
    let size = CGSize(width: 390, height: 844)
    let stage = SelfieCameraStage(presentation: .init(phase: .left, status: .ok, yaw: -0.2)) { Color.black }
    let image = try attachedCameraSnapshot(stage, size: size, preferLayerRendering: true)
    #expect(image.size == size)
    #expect(try feedbackPixelCount(image, in: SelfieStageLayout.hintFrame(size: size)) > 24,
            "CALayer fallback must include the attached ScrollView hint")
}

@Test func cameraFramesStayFiniteAndNonnegativeDuringInitialLayout() {
    let sizes = [CGSize.zero, CGSize(width: 1, height: 1), CGSize(width: 80, height: 120),
                 CGSize(width: 120, height: 80), CGSize(width: -1, height: -10),
                 CGSize(width: CGFloat.nan, height: CGFloat.infinity),
                 CGSize(width: CGFloat.infinity, height: 360)]
    for proposed in sizes {
        let size = CameraStageDimensions.size(proposed)
        let preview = cameraPhotoPreviewSize(in: proposed)
        let hints = SelfieStageLayout.hintFrame(size: proposed, bottomInset: .nan)
        for dimension in [size.width, size.height, preview.width, preview.height, hints.width, hints.height,
                          CameraStageDimensions.availableWidth(proposed.width, inset: 90),
                          CameraStageDimensions.availableWidth(proposed.width, inset: 40)] {
            #expect(dimension.isFinite && dimension >= 0)
        }
        #expect(hints.minX.isFinite && hints.minY.isFinite)
    }
    // Finite screen geometry keeps the hosted ring/framing rules unchanged.
    let portrait = CGSize(width: 390, height: 844)
    #expect(CameraStageDimensions.size(portrait) == portrait)
    #expect(cameraPhotoPreviewSize(in: portrait) == portrait)
    #expect(CameraStageDimensions.availableWidth(390, inset: 90) == 300)
}

@MainActor
@Test func narrowPortraitPoseChipsAreTopAnchoredAndNotClipped() throws {
    let size = CGSize(width: 320, height: 568)
    let top = SelfieStageLayout.poseChipsTop(size: size)
    #expect(top >= 56, "Narrow portrait chips leave the 44pt back button clear")
    #expect(CameraStageDimensions.availableWidth(size.width, inset: 32) == 288)
    let directory = try cameraSnapshotDirectory()
    for (name, typeSize) in [("standard", DynamicTypeSize.large), ("large", DynamicTypeSize.accessibility1)] {
        let view = SelfieCameraStage(presentation: .init(status: .hold, countdown: 2, sweep: 0.5)) { Color.black }
            .environment(\.theme, Theme(appearance: Appearance(), scheme: .dark))
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
        let image = try attachedCameraSnapshot(view, size: size)
        let category: UIContentSizeCategory = name == "large" ? .accessibilityMedium : .large
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let badgeSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: 18, compatibleWith: traits)
        for glyph in ["1", "2", "3", "✓"] {
            let glyphRenderer = ImageRenderer(content: Text(glyph)
                .font(Theme(appearance: Appearance(), scheme: .dark).body(10, weight: .semibold))
                .fixedSize().dynamicTypeSize(typeSize))
            glyphRenderer.scale = 1
            let glyphImage = try #require(glyphRenderer.uiImage)
            #expect(glyphImage.size.width <= badgeSize && glyphImage.size.height <= badgeSize,
                    "Pose badge must contain the entire \(glyph) glyph at \(name) text size")
        }
        // This band contains only the stepper: the ring begins below y173.
        #expect(try feedbackPixelCount(image, in: CGRect(x: 16, y: top, width: 288, height: 100)) > 24,
                "Narrow \(name) portrait snapshot must contain visible pose-chip text")
        #expect(try feedbackPixelCount(image, in: CGRect(x: 0, y: 0, width: 320, height: 4)) == 0,
                "Top-anchored pose chips must not bleed across the screenshot's top edge")
        try #require(image.pngData()).write(to: directory.appendingPathComponent("dark-camera-countdown-chips-\(name)-320x568.png"))
    }
}

@Test func selfiePreviewFillsTheStageUnderItsSeparateMask() {
    for size in [CGSize(width: 1080, height: 2400), CGSize(width: 2400, height: 1080),
                 CGSize(width: 320, height: 568), CGSize(width: 100, height: 110)] {
        #expect(SelfieStageLayout.previewSize(size: size) == size)
        #expect(SelfieStageLayout.previewFrame(size: size) == CGRect(origin: .zero, size: size))
    }
}

@Test func cameraDefaultColorsMatchWebInBothSchemes() {
    for defaults in [Appearance.Palette.light, .dark] {
        let colors = CameraStageColors(palette: defaults, defaults: defaults)
        #expect(colors.success == Color(hex: 0x40A99A))
        #expect(colors.turn == Color(hex: 0x5FD4C2))
        #expect(colors.positive == Color(hex: 0x237F74))
        #expect(colors.doneGuide == Color(hex: 0xE8F6F0))
        #expect(colors.warning == Color(hex: 0xF59E0B))
    }
}

@Test func cameraSemanticOverridesWinBeforeAccentFallback() {
    for defaults in [Appearance.Palette.light, .dark] {
        var host = defaults
        host.accent = Color(hex: 0x4455CC)
        host.success = Color(hex: 0x117733)
        host.warning = Color(hex: 0xCC8822)
        let colors = CameraStageColors(palette: host, defaults: defaults)
        #expect(colors.success == host.success && colors.turn == host.success)
        #expect(colors.positive == host.success && colors.doneGuide == host.success)
        #expect(colors.warning == host.warning)
        host.success = defaults.success
        let accent = CameraStageColors(palette: host, defaults: defaults)
        #expect(accent.success == host.accent && accent.turn == host.accent)
        #expect(accent.positive == host.accent && accent.doneGuide == host.accent)
        #expect(accent.warning == host.warning)
        host.accent = defaults.accent
        let warningOnly = CameraStageColors(palette: host, defaults: defaults)
        #expect(warningOnly.turn == Color(hex: 0x5FD4C2) && warningOnly.warning == host.warning)
    }
}

@Test func cameraOverridesAreComparedToTheActiveSchemeDefaults() {
    var host = Appearance.Palette.dark
    // Light's semantic defaults explicitly supplied in the dark palette are
    // still overrides, rather than being mistaken for untouched dark defaults.
    host.success = Appearance.Palette.light.success
    host.warning = Appearance.Palette.light.warning
    let colors = CameraStageColors(palette: host, defaults: .dark)
    #expect(colors.success == host.success && colors.turn == host.success)
    #expect(colors.warning == host.warning)
}

@MainActor
@Test func selfiePresentationUsesOnlyActiveTurnAndConfirmedPoseFacts() {
    let left = SelfiePresentation(phase: .left, status: .ok, yaw: -TurnChallenge.side)
    #expect(left.reached && left.frontDone && !left.leftDone && !left.rightDone)
    #expect(left.turn == 1)
    let bad = SelfiePresentation(phase: .left, status: .far, yaw: -TurnChallenge.side)
    #expect(!bad.reached && bad.hint == "Come closer")
    #expect(SelfiePresentation(phase: .center, status: .ok, yaw: -TurnChallenge.side).turn == 0)
    #expect(SelfiePresentation(phase: .right, status: .ok, yaw: TurnChallenge.side).leftDone)
    #expect(SelfiePresentation(phase: .done).rightDone)
}

@MainActor
@Test func timedFallbackPreservesProgressAndPoseCueWithoutInventingDetectedPoses() {
    for (progress, direction) in [(0.1, "left"), (0.4, "center"), (0.55, "right"), (0.9, "right")] {
        let output = SelfieCaptureEngine.Output(mode: .timed, phase: .position, update: nil,
                                                timedProgress: progress, dark: false, completed: false)
        let value = SelfiePresentation.from(output: output)
        #expect(value.sweep == progress)
        #expect(value.timedProgress == progress)
        #expect(value.direction == direction)
        #expect(!value.showsPoseChips && !value.frontDone && !value.leftDone && !value.rightDone)
        #expect(!value.good && !value.reached)
        #expect(value.hint == (direction == "left" ? L10n.string("selfie.timed.left")
                              : direction == "center" ? L10n.string("selfie.timed.center")
                              : L10n.string("selfie.timed.right")))
    }
    let waiting = SelfieCaptureEngine.Output(mode: .timedWaiting, phase: .position, update: nil,
                                             timedProgress: 0, dark: false, completed: false)
    let value = SelfiePresentation.from(output: waiting)
    #expect(value.timedProgress == nil && value.sweep == 0 && !value.showsPoseChips)
    #expect(value.direction == "center" && value.hint == L10n.string("selfie.timed.ready"))
}

/// The live stage uses this layout, including the countdown. At 360pt high the
/// old below-ring digit was off screen; the side rail stays clear of both face
/// and bottom controls even with accessibility text larger than fontScale 1.5.
@MainActor
@Test func landscapeCountdownLargeTextStaysInBoundedRail() throws {
    let size = CGSize(width: 640, height: 360)
    let bounds = CGRect(origin: .zero, size: size)
    let rail = SelfieStageLayout.hintFrame(size: size)
    let radius = CaptureGeometry.ringFraction * size.height
    #expect(bounds.contains(rail))
    #expect(rail.minX > size.width / 2 + radius)
    #expect(rail.maxY <= size.height - 112)
    let digit = ImageRenderer(content: Text("2")
        .font(Theme(appearance: Appearance(), scheme: .light).body(30, weight: .semibold))
        .dynamicTypeSize(.accessibility1))
    digit.scale = 1
    let measuredDigit = try #require(digit.uiImage)
    let digitBounds = CGRect(x: rail.midX - measuredDigit.size.width / 2, y: rail.minY + 8,
                             width: measuredDigit.size.width, height: measuredDigit.size.height)
    #expect(rail.contains(digitBounds))
    let stage = SelfieCameraStage(presentation: .init(status: .hold, countdown: 2, sweep: 0.5, fillLight: true)) { Color.black }
        .dynamicTypeSize(.accessibility1).frame(width: size.width, height: size.height)
    let image = try attachedCameraSnapshot(stage, size: size)
    #expect(image.size == size)
    #expect(try feedbackPixelCount(image, in: rail, fillLight: true) > 24,
            "Large-text countdown/low-light rail must appear in the attached screenshot")
    let directory = try cameraSnapshotDirectory()
    try #require(image.pngData()).write(to: directory.appendingPathComponent("camera-countdown-light-large-text-640x360.png"))
}

/// Runs on an iOS test destination, not macOS. Export with
/// IDENTIFIED_CAPTURE_SNAPSHOT_DIR=/absolute/path; otherwise uses app Documents.
/// A temporary UIWindow hosts the live stage and its UIKit scroll view over a black preview.
@MainActor
@Test func exportCameraPresentationSnapshots() throws {
    let directory = try cameraSnapshotDirectory()
    let scenes: [(String, SelfiePresentation)] = [
        ("position", .init(status: .noFace)),
        ("far", .init(status: .far, distanceLevel: 1)),
        ("near", .init(status: .near, distanceLevel: 3)),
        ("left", .init(phase: .left, status: .ok, yaw: -TurnChallenge.side * 0.55)),
        ("left-reached", .init(phase: .left, status: .ok, yaw: -TurnChallenge.side)),
        ("right", .init(phase: .right, status: .ok, yaw: TurnChallenge.side * 0.55)),
        ("countdown", .init(status: .hold, countdown: 2, sweep: 0.5)),
        ("done", .init(phase: .done, status: .ok)),
        ("light", .init(status: .hold, fillLight: true)),
        ("timed-left", .from(output: .init(mode: .timed, phase: .position, update: nil, timedProgress: 0.2, dark: false, completed: false))),
        ("timed-center", .from(output: .init(mode: .timed, phase: .position, update: nil, timedProgress: 0.45, dark: false, completed: false))),
        ("timed-right", .from(output: .init(mode: .timed, phase: .position, update: nil, timedProgress: 0.75, dark: false, completed: false))),
    ]
    for (schemeName, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 320, height: 568), CGSize(width: 844, height: 390)] {
            for (name, presentation) in scenes {
                let view = SelfieCameraStage(presentation: presentation) { Color.black }
                    .frame(width: size.width, height: size.height)
                let image = try attachedCameraSnapshot(view.environment(\.theme, Theme(appearance: Appearance(), scheme: scheme)).environment(\.colorScheme, scheme), size: size)
                #expect(image.size == size)
                if presentation.phase != .done {
                    let feedback = SelfieStageLayout.hintFrame(size: size)
                    #expect(try feedbackPixelCount(image, in: feedback, fillLight: presentation.fillLight) > 24,
                            "Missing rendered feedback for camera-\(name) at \(size)")
                }
                let data = try #require(image.pngData())
                try data.write(to: directory.appendingPathComponent("\(schemeName)-camera-\(name)-\(Int(size.width))x\(Int(size.height)).png"))
            }
            for card in [true, false] {
                let view = CameraPhotoStage(card: card, ready: card, hint: card ? "Fit all four edges inside the frame" : "Looks sharp — take the photo") { Color.black }
                    .frame(width: size.width, height: size.height)
                let image = try attachedCameraSnapshot(view.environment(\.theme, Theme(appearance: Appearance(), scheme: scheme)).environment(\.colorScheme, scheme), size: size)
                let data = try #require(image.pngData())
                try data.write(to: directory.appendingPathComponent("\(schemeName)-camera-\(card ? "card" : "document")-\(Int(size.width))x\(Int(size.height)).png"))
            }
            let error = ZStack {
                SelfieCameraStage(presentation: .init()) { Color.black }
                CameraProblemView(state: .denied, retry: {}).background(.black)
            }.frame(width: size.width, height: size.height)
            let image = try attachedCameraSnapshot(error.environment(\.theme, Theme(appearance: Appearance(), scheme: scheme)).environment(\.colorScheme, scheme), size: size)
            let data = try #require(image.pngData())
            try data.write(to: directory.appendingPathComponent("\(schemeName)-camera-error-\(Int(size.width))x\(Int(size.height)).png"))
        }
    }
}
@Test func fittedCardGuideAndRaisedSelfieStayWithinStageBounds() {
    for size in [CGSize(width: 390, height: 844), CGSize(width: 320, height: 568), CGSize(width: 844, height: 390)] {
        let guide = cardGuideSize(stage: size, sourceAspect: 0.75)
        #expect(abs(guide.width - min(size.width, size.height * 0.75) * 0.82) < 1e-9)
        #expect(guide.width <= size.width && guide.height <= size.height)
        let center = CaptureGeometry.selfieCenterY(stage: .init(width: size.width, height: size.height))
        // Compare in Double with subpixel tolerance across CGFloat conversion.
        let expectedCenter: Double = size.height > size.width ? min(Double(size.height), Double(size.width) / 0.75) / 2 : Double(size.height) / 2
        #expect(abs(expectedCenter - center) < 1e-9)
        let radius = CaptureGeometry.ringFraction * min(size.width, size.height)
        #expect(center - radius >= 0 && center + radius <= size.height)
        let hint = SelfieStageLayout.hintFrame(size: size)
        #expect(CGRect(origin: .zero, size: size).contains(hint))
        if size.height > size.width { #expect(hint.minY > center + radius) }
    }
}

/// Sample rendered pixels rather than accepting a correctly sized but opaque stage.
private func stagePixel(_ image: UIImage, x: Int, y: Int) throws -> [UInt8] {
    let cg = try #require(image.cgImage)
    let patch = try #require(cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
    var rgba = [UInt8](repeating: 0, count: 4)
    try rgba.withUnsafeMutableBytes { bytes in
        let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return rgba
}

@MainActor @Test func selfieGuideHidesColoredFeedOutsideCircle() throws {
    let size = CGSize(width: 390, height: 844)
    for fillLight in [false, true] {
        let stage = SelfieCameraStage(presentation: .init(phase: .position, fillLight: fillLight)) {
            Color(red: 0.2, green: 0.4, blue: 0.8)
        }
        let image = try attachedCameraSnapshot(
            stage.frame(width: size.width, height: size.height), size: size)
        let outside = try stagePixel(image, x: 20, y: 260)
        #expect(outside.prefix(3).allSatisfy { fillLight ? $0 > 245 : $0 < 10 })
        let feed = try stagePixel(image, x: 110, y: 260)
        #expect(feed[2] > 150 && feed[2] > feed[0] + 60)
        let radius = CaptureGeometry.ringFraction * size.width
        let centerY = CaptureGeometry.selfieCenterY(stage: .init(width: size.width, height: size.height))
        let stroke = try stagePixel(image, x: 195, y: Int(centerY - radius))
        let inside = try stagePixel(image, x: 195, y: Int(centerY - radius + 8))
        #expect(zip(stroke.prefix(3), inside.prefix(3)).contains { abs(Int($0.0) - Int($0.1)) > 15 },
                "Positioning ring stroke must remain visible over the feed")
    }
}

@MainActor @Test func cardGuidePreservesColoredFeedOutsideGuide() throws {
    let image = try attachedCameraSnapshot(CameraPhotoStage(card: true) {
        Color(red: 0.2, green: 0.4, blue: 0.8)
    }, size: CGSize(width: 390, height: 844))
    let pixel = try stagePixel(image, x: 10, y: 100)
    #expect(pixel[2] > 150 && pixel[1] > 65 && pixel[2] > pixel[0] + 60)
}
#endif
