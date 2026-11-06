#if os(iOS)
@preconcurrency import AVFoundation
import CoreImage
import IdentifiedCore
import SwiftUI
import UIKit

/// Capture-specific web hues for defaults; explicit host semantic colours win.
/// A custom accent remains the fallback for success/turn feedback, preserving
/// the SDK's camera-overlay accent contract without recolouring warnings.
struct CameraStageColors {
    let success: Color
    let turn: Color
    let positive: Color
    let doneGuide: Color
    let warning: Color

    init(palette: Appearance.Palette, defaults: Appearance.Palette) {
        let hostSuccess: Color? = palette.success != defaults.success ? palette.success
            : palette.accent != defaults.accent ? palette.accent : nil
        success = hostSuccess ?? Color(hex: 0x40A99A)
        turn = hostSuccess ?? Color(hex: 0x5FD4C2)
        positive = hostSuccess ?? Color(hex: 0x237F74)
        doneGuide = hostSuccess ?? Color(hex: 0xE8F6F0)
        warning = palette.warning != defaults.warning ? palette.warning : Color(hex: 0xF59E0B)
    }

    init(theme: Theme, scheme: ColorScheme) {
        let dark: Bool
        switch theme.appearance.colorScheme {
        case .system: dark = scheme == .dark
        case .light: dark = false
        case .dark: dark = true
        }
        self.init(palette: theme.palette, defaults: dark ? .dark : .light)
    }
}

/// GeometryReader may briefly propose a tiny or invalid size while a camera
/// enters the hierarchy. Never hand negative/nonfinite lengths to SwiftUI.
enum CameraStageDimensions {
    static func length(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
    static func size(_ size: CGSize) -> CGSize {
        CGSize(width: length(size.width), height: length(size.height))
    }
    static func availableWidth(_ width: CGFloat, inset: CGFloat) -> CGFloat {
        length(length(width) - length(inset))
    }
}

/// The live preview. Selfies fit the complete frame beneath a separate mask;
/// document cameras fill their guide. Front previews mirror; their frames do not.
struct CameraPreview: UIViewRepresentable {
    let source: FrameSource?
    var aspectFit = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        if let camera = source as? CameraController {
            view.previewLayer.session = camera.session
            view.previewLayer.videoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        }
        #if DEBUG
        if let fixture = source as? FixtureFrameSource {
            view.showStill(fixture.stillImage, aspectFit: aspectFit)
        }
        #endif
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        private let still = CALayer()

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        func showStill(_ image: CIImage, aspectFit: Bool = false) {
            still.contents = CIContext().createCGImage(image, from: image.extent)
            still.contentsGravity = aspectFit ? .resizeAspect : .resizeAspectFill
            still.masksToBounds = true
            layer.addSublayer(still)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            still.frame = bounds
        }
    }
}

/// What a camera screen shows when its camera is not running.
struct CameraProblemView: View {
    let state: CameraSession.State
    let retry: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
                    Text(state == .denied ? L10n.string("camera.denied.title") : L10n.string("camera.failed.title"))
                        .font(.headline).foregroundStyle(.white)
                    Text(state == .denied ? L10n.string("camera.denied.body") : L10n.string("camera.failed.body"))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    if state == .denied {
                        Button(L10n.string("camera.denied.settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(L10n.string("camera.retry"), action: retry).buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 64)
                .frame(maxWidth: .infinity, minHeight: CameraStageDimensions.length(geometry.size.height))
            }
            .background(.black.opacity(0.95))
        }
    }
}

/// The full-screen camera's back button.
struct CameraBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel(L10n.string("camera.back"))
    }
}

/// A round shutter.
struct ShutterButton: View {
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.white.opacity(enabled ? 0.14 : 0), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(enabled ? 1 : 0.32), lineWidth: 4))
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The captured image with Retake and Use this photo, as on the web.
struct CapturePreview: View {
    let image: Data
    let label: String
    let retake: () -> Void
    let use: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let uiImage = UIImage(data: image) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(L10n.format("camera.preview", label))
            }
            PrimaryButton(title: L10n.string("camera.use"), action: use)
            SecondaryButton(title: L10n.string("camera.retake"), action: retake)
        }
    }
}
/// Keep a landscape photo preview clear of the side controls. The capture engines
/// receive this exact size, so aspect-fill analysis and upload crop agree.
func cameraPhotoPreviewSize(in proposedSize: CGSize) -> CGSize {
    let size = CameraStageDimensions.size(proposedSize)
    return size.width > size.height ? CGSize(width: min(size.width, size.height * 1.25), height: size.height) : size
}

func cardGuideSize(stage proposed: CGSize, sourceAspect: Double) -> CGSize {
    let stage = CameraStageDimensions.size(proposed)
    guard sourceAspect.isFinite, sourceAspect > 0 else { return .zero }
    let width = min(stage.width, stage.height * sourceAspect) * CardDetector.guideWidthFraction
    return CGSize(width: width, height: width / CardDetector.aspectRatio)
}

struct CameraPhotoStage<Preview: View>: View {
    var card: Bool
    var ready = false
    var sourceAspect: Double = 3.0 / 4.0
    var hint: String?
    @ViewBuilder var preview: () -> Preview
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    private var colors: CameraStageColors { CameraStageColors(theme: theme, scheme: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            let size = CameraStageDimensions.size(geometry.size)
            let frame = card ? size : cameraPhotoPreviewSize(in: size)
            let guide = cardGuideSize(stage: size, sourceAspect: sourceAspect)
            let width = guide.width
            let height = width / CardDetector.aspectRatio
            let compact = size.width > size.height
            let railWidth = card ? max(0, (size.width - guide.width) / 2) : (size.width - frame.width) / 2
            ZStack {
                Color.black
                preview().frame(width: frame.width, height: frame.height).clipped()
                if card {
                    // Opaque outside the guide, as the hosted flow's card mask (`CameraCapture.tsx`), so only the card area shows.
                    PhotoStageMask(guide: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height))
                        .fill(.black, style: FillStyle(eoFill: true))
                    RoundedRectangle(cornerRadius: 10).stroke(ready ? colors.success : .white.opacity(0.9), lineWidth: 2.5)
                        .frame(width: width, height: height)
                }
                if let hint {
                    Text(hint).font(theme.body(15, weight: .semibold))
                        .foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                        .frame(width: CameraStageDimensions.availableWidth(compact ? railWidth : size.width, inset: compact ? 16 : 40))
                        .position(x: compact ? size.width - railWidth / 2 : size.width / 2,
                                  y: compact ? size.height / 2 : size.height - geometry.safeAreaInsets.bottom - 144)
                }
            }
        }
    }
}

private struct PhotoStageMask: Shape {
    let guide: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: guide, cornerSize: CGSize(width: 10, height: 10))
        return path
    }
}
#endif
