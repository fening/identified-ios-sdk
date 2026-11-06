#if os(iOS)
import IdentifiedCore
import Combine
import SwiftUI
import UIKit

@MainActor
final class SelfieCameraModel: ObservableObject {
    @Published private(set) var output: SelfieCaptureEngine.Output?
    @Published private(set) var sourceAspect = 0.75
    let camera: CameraSession
    private var cameraChanges: AnyCancellable?
    private let engine = SelfieCaptureEngine()
    private let onComplete: @MainActor ([String: Data]) -> Void

    init(environment: CaptureEnvironment, onComplete: @escaping @MainActor ([String: Data]) -> Void) {
        camera = CameraSession(environment: environment, position: .front)
        self.onComplete = onComplete
        cameraChanges = camera.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func start() async {
        engine.reset()
        output = nil
        await camera.start { [engine, weak self] frame in
            guard let output = engine.process(frame, at: ProcessInfo.processInfo.systemUptime) else { return }
            let size = frame.size
            Task { @MainActor in
                guard let self else { return }
                if size.height > 0 && self.sourceAspect != size.width / size.height {
                    self.sourceAspect = size.width / size.height
                }
                self.apply(output)
            }
        }
    }

    func setViewSize(_ size: CGSize) {
        engine.setViewSize(PixelSize(width: size.width, height: size.height))
    }

    func pressShutter() {
        _ = engine.pressShutter(at: ProcessInfo.processInfo.systemUptime)
    }

    func startTimed() {
        engine.startTimed(at: ProcessInfo.processInfo.systemUptime)
    }

    private func apply(_ output: SelfieCaptureEngine.Output) {
        self.output = output
        #if DEBUG
        if let role = output.update?.capture, let yaw = output.update?.yaw { DebugLog.yaw(role: role, yaw: yaw) }
        #endif
        if output.completed {
            #if DEBUG
            DebugLog.event("selfie.camera completed mode=\(output.mode) frames=\(engine.capturedFrames().keys.sorted().joined(separator: ","))")
            #endif
            camera.stop()
            onComplete(engine.capturedFrames())
        }
    }
}

/// `FluidTurnChallenge.tsx` full screen: the preview in a circle, the hint
/// under it, the countdown, the pose stepper, and the timed fallback.
struct SelfieCameraView: View {
    let close: () -> Void
    @StateObject private var model: SelfieCameraModel
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @State private var savedBrightness: CGFloat?

    init(environment: CaptureEnvironment, onComplete: @escaping @MainActor ([String: Data]) -> Void, close: @escaping () -> Void) {
        self.close = close
        _model = StateObject(wrappedValue: SelfieCameraModel(environment: environment, onComplete: onComplete))
    }

    var body: some View {
        let dark = model.output?.dark == true
        GeometryReader { safeGeometry in
            cameraLayout(safeArea: safeGeometry.safeAreaInsets)
                .ignoresSafeArea()
        }
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear {
            model.camera.stop()
            if let savedBrightness { UIScreen.main.brightness = savedBrightness }
        }
        .onChange(of: dark) { isDark in
            // The screen is the fill light: full brightness while it is white.
            if isDark {
                if savedBrightness == nil { savedBrightness = UIScreen.main.brightness }
                UIScreen.main.brightness = 1
            } else if let savedBrightness {
                UIScreen.main.brightness = savedBrightness
                self.savedBrightness = nil
            }
        }
        .onChange(of: model.camera.state) { state in
            if state == .unavailable { flow.failWithoutCamera() }
        }
    }

    private func cameraLayout(safeArea: EdgeInsets) -> some View {
        let output = model.output
        return GeometryReader { geometry in
            ZStack {
                SelfieCameraStage(
                    presentation: SelfiePresentation.from(output: output),
                    sourceAspect: model.sourceAspect,
                    safeArea: safeArea
                ) {
                    CameraPreview(source: model.camera.source, aspectFit: true)
                }
                if model.camera.state == .denied || model.camera.state == .failed {
                    CameraProblemView(state: model.camera.state) { Task { await model.start() } }
                        .background(.black.opacity(0.95))
                }
                VStack {
                    HStack { CameraBackButton(action: close); Spacer() }
                        .padding(.horizontal, 12)
                        .padding(.top, safeArea.top + 8)
                    Spacer()
                    if model.camera.state != .denied && model.camera.state != .failed {
                        if output?.mode == .timedWaiting {
                            PrimaryButton(title: L10n.string("selfie.timed.start")) { model.startTimed() }
                                .frame(maxWidth: 280).padding(.horizontal, 20)
                        } else if output?.update?.shutterAvailable == true {
                            ShutterButton(label: L10n.string("selfie.shutter")) { model.pressShutter() }
                                .frame(maxWidth: .infinity, alignment: geometry.size.width > geometry.size.height ? .trailing : .center)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.bottom, safeArea.bottom + 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { model.setViewSize(geometry.size) }
            .onChange(of: geometry.size) { model.setViewSize($0) }
        }
    }
}

/// A value-only rendering contract. No camera, timers, permissions or fixture hooks.
struct SelfiePresentation {
    var phase: TurnPhase = .position
    var status: TurnStatus = .noFace
    var yaw: Double = 0
    var countdown: Int? = nil
    var sweep: Double = 0
    var distanceLevel: Int = 2
    var fillLight = false
    var hintOverride: String? = nil
    /// Explicit timed progress is not a claim that any detected pose is good.
    var timedProgress: Double? = nil
    var showsPoseChips = true

    static func from(output: SelfieCaptureEngine.Output?) -> SelfiePresentation {
        let phase = output?.phase ?? .position
        let update = output?.update
        var value = SelfiePresentation(phase: phase, status: update?.status ?? .noFace,
                                      yaw: update?.yaw ?? 0, countdown: update?.countdown,
                                      sweep: update?.sweep ?? 0, distanceLevel: update?.distanceLevel ?? 2,
                                      fillLight: output?.dark == true)
        if output == nil { value.hintOverride = L10n.string("selfie.hint.preparing") }
        if let output, output.mode != .challenge {
            value.showsPoseChips = false
            if output.mode == .timed {
                value.timedProgress = min(1, max(0, output.timedProgress))
                value.sweep = value.timedProgress ?? 0
            }
            value.hintOverride = output.mode == .timedWaiting ? L10n.string("selfie.timed.ready")
                : output.timedProgress < 0.4 ? L10n.string("selfie.timed.left")
                : output.timedProgress < 0.55 ? L10n.string("selfie.timed.center")
                : L10n.string("selfie.timed.right")
        }
        return value
    }

    var good: Bool { status == .hold || status == .ok }
    // Positioning feedback is separate from facing the lens for the countdown.
    var aligned: Bool { good || (phase == .position && status == .lookStraight) }
    var leftDone: Bool { phase == .center || phase == .right || phase == .done }
    var rightDone: Bool { phase == .done }
    var frontDone: Bool { phase != .position }
    var turn: Double { min(1, max(0, phase == .left ? -yaw / TurnChallenge.side : phase == .right ? yaw / TurnChallenge.side : 0)) }
    var reached: Bool { good && turn >= 1 }
    var hint: String { hintOverride ?? SelfieHint.text(phase: phase, status: status, yaw: yaw) }
    var direction: String {
        if let timedProgress {
            return timedProgress < 0.4 ? "left" : timedProgress < 0.55 ? "center" : "right"
        }
        return phase == .left ? "left" : phase == .right ? "right" : "center"
    }
}

/// Shared live-picture bounds and overlay placement. The engine receives the
/// same bounded picture size; the hosted circle keeps the stage's shorter side.
/// Landscape feedback occupies a rail outside the face preview.
enum SelfieStageLayout {
    static func previewSize(size: CGSize) -> CGSize {
        CameraStageDimensions.size(size)
    }

    static func previewFrame(size proposedSize: CGSize) -> CGRect {
        let size = CameraStageDimensions.size(proposedSize)
        let preview = previewSize(size: size)
        return CGRect(x: (size.width - preview.width) / 2, y: (size.height - preview.height) / 2,
                      width: preview.width, height: preview.height)
    }

    /// Top-anchor rather than centring a potentially multi-row stepper at y27.
    /// Narrow portrait screens place it below the 44pt back-button hit area.
    static func poseChipsTop(size: CGSize, topInset: CGFloat = 0) -> CGFloat {
        CameraStageDimensions.length(topInset) + (CameraStageDimensions.length(size.width) < 360 ? 60 : 12)
    }

    static func hintFrame(size proposedSize: CGSize, bottomInset proposedBottomInset: CGFloat = 0, sourceAspect: Double = 0.75) -> CGRect {
        let size = CameraStageDimensions.size(proposedSize)
        let bottomInset = CameraStageDimensions.length(proposedBottomInset)
        let radius = CaptureGeometry.ringFraction * min(size.width, size.height)
        if size.width > size.height {
            let width = max(1, size.width / 2 - radius - 16)
            let height = max(1, size.height - 128 - bottomInset)
            return CGRect(x: size.width - width - 8, y: 16, width: width, height: height)
        }
        let top = CaptureGeometry.selfieCenterY(stage: PixelSize(width: size.width, height: size.height), sourceAspect: sourceAspect) + radius + 20
        return CGRect(x: 20, y: top, width: max(1, size.width - 40), height: max(1, size.height - bottomInset - 96 - top))
    }
}

/// SwiftPM processes these as loose PNG resources, not asset-catalog entries.
/// Decode their URLs directly so simulator/package test bundles use the same
/// artwork as an embedded SDK, without CoreUI name/catalog resolution.
@MainActor
enum CameraFaceGuideAssets {
    private static let images: [String: UIImage] = {
        var images: [String: UIImage] = [:]
        for direction in ["center", "left", "right"] {
            if let url = Bundle.module.url(forResource: "face-guide-\(direction)", withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                images[direction] = image
            }
        }
        return images
    }()

    static func image(direction: String) -> UIImage? { images[direction] }
}

/// This is the same stage used by the live camera and window-attached snapshot tests.
/// Preview fits the full source; the raised circular window is exposed by the scrim.
struct SelfieCameraStage<Preview: View>: View {
    let presentation: SelfiePresentation
    var sourceAspect: Double = 0.75
    var safeArea = EdgeInsets()
    @ViewBuilder var preview: () -> Preview
    @Environment(\.theme) private var theme

    @Environment(\.colorScheme) private var colorScheme
    private var colors: CameraStageColors { CameraStageColors(theme: theme, scheme: colorScheme) }
    @ScaledMetric(relativeTo: .body) private var poseBadgeSize: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let size = CameraStageDimensions.size(geometry.size)
            let previewFrame = SelfieStageLayout.previewFrame(size: size)
            let r = CaptureGeometry.ringFraction * min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: CaptureGeometry.selfieCenterY(stage: PixelSize(width: size.width, height: size.height), sourceAspect: sourceAspect))
            let compact = size.width > size.height
            let ring = presentation.aligned || presentation.phase == .done ? colors.success : colors.warning
            let guide = presentation.phase == .done ? (presentation.fillLight ? colors.positive : colors.doneGuide) : presentation.good ? (presentation.fillLight ? colors.positive : colors.success) : colors.warning
            let rail = max(0, size.width / 2 - r - 16)
            ZStack {
                (presentation.fillLight ? Color.white : Color.black)
                preview().frame(width: previewFrame.width, height: previewFrame.height).clipped()
                    .frame(width: size.width, height: size.height)
                    .offset(y: center.y - size.height / 2)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                }
                .fill(presentation.fillLight ? Color.white : Color.black,
                      style: FillStyle(eoFill: true))
                Circle().stroke(ring.opacity(presentation.aligned ? 0.95 : 0.4), lineWidth: size.width / 100)
                    .frame(width: r * 2, height: r * 2).position(center)
                if presentation.direction == "left" || presentation.direction == "right" {
                    turnDashes(radius: r, center: center)
                }
                if presentation.countdown != nil {
                    Circle().trim(from: 0, to: min(1, max(0, presentation.sweep)))
                        .stroke(.white, style: StrokeStyle(lineWidth: size.width / 100, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: r * 2, height: r * 2).position(center)
                }
                if presentation.countdown == nil {
                    if let image = CameraFaceGuideAssets.image(direction: presentation.direction) {
                        Image(uiImage: image)
                            .renderingMode(.template).resizable().scaledToFit()
                            .foregroundStyle(guide).opacity(presentation.good ? 0.12 : 0.28)
                            .frame(width: r * 1.5, height: r * 1.5).position(center)
                            .accessibilityHidden(true)
                    }
                    if (presentation.direction == "left" || presentation.direction == "right") && !presentation.reached {
                        Image(systemName: presentation.direction == "left" ? "chevron.left" : "chevron.right")
                            .font(theme.body(22, weight: .bold)).foregroundStyle(guide)
                            .position(x: center.x + (presentation.direction == "left" ? -1 : 1) * (r * 0.82 - 17), y: center.y)
                            .accessibilityHidden(true)
                    }
                }
                if presentation.showsPoseChips {
                    if compact {
                        poseChips.frame(maxWidth: rail)
                            .position(x: rail / 2 + 8, y: 150)
                    } else {
                        VStack(spacing: 0) {
                            poseChips
                                .frame(maxWidth: CameraStageDimensions.availableWidth(size.width, inset: 32))
                                .padding(.top, SelfieStageLayout.poseChipsTop(size: size, topInset: max(safeArea.top, geometry.safeAreaInsets.top)))
                            Spacer(minLength: 0)
                        }
                        .frame(width: size.width, height: size.height, alignment: .top)
                    }
                }
                let hintFrame = SelfieStageLayout.hintFrame(size: size, bottomInset: max(safeArea.bottom, geometry.safeAreaInsets.bottom), sourceAspect: sourceAspect)
                ScrollView { hints.padding(.vertical, compact ? 8 : 0) }
                    .frame(width: hintFrame.width, height: hintFrame.height)
                    .position(x: hintFrame.midX, y: hintFrame.midY)
                if presentation.phase == .done {
                    Color.black.opacity(0.55)
                    Text(L10n.string("selfie.hint.done"))
                        .font(theme.body(18, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: size.width, height: size.height).clipped()
        }
    }

    private func turnDashes(radius: CGFloat, center: CGPoint) -> some View {
        let left = presentation.direction == "left"
        let progress = presentation.timedProgress.map {
            left ? $0 / 0.4 : ($0 - 0.55) / 0.45
        } ?? (presentation.good ? presentation.turn : 0)
        return Canvas { context, _ in
            for index in 0..<25 {
                let fraction = Double(index) / 24
                let angle = (-36 + 72 * fraction) * Double.pi / 180
                let x = cos(angle) * (left ? -1 : 1)
                let y = sin(angle)
                var dash = Path()
                dash.move(to: CGPoint(x: center.x + x * radius * 0.88, y: center.y + y * radius * 0.88))
                dash.addLine(to: CGPoint(x: center.x + x * radius * 0.98, y: center.y + y * radius * 0.98))
                context.stroke(dash, with: .color(.white.opacity(progress > 0 && fraction <= progress ? 1 : 0.32)), lineWidth: 1.5)
            }
        }.accessibilityHidden(true)
    }

    private var poseChips: some View {
        ViewThatFits {
            HStack(spacing: 8) { chips }
            VStack(spacing: 6) { chips }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
    }

    @ViewBuilder private var chips: some View {
        let captured = [presentation.frontDone, presentation.leftDone, presentation.rightDone]
        let active = captured.firstIndex(of: false)
        ForEach(0..<3, id: \.self) { i in
            let done = captured[i]
            if i > 0 { Rectangle().fill(.white.opacity(0.25)).frame(width: 10, height: 1) }
            HStack(spacing: 6) {
                Text(done ? "✓" : "\(i + 1)").font(theme.body(10, weight: .semibold))
                    .foregroundStyle(done || active == i ? .white : .white.opacity(0.55))
                    .fixedSize()
                    .frame(width: poseBadgeSize, height: poseBadgeSize)
                    .background(done ? colors.positive : .clear, in: Circle())
                    .overlay(Circle().stroke(done ? colors.positive : active == i ? colors.success : .white.opacity(0.45), lineWidth: 1))
                Text([L10n.string("selfie.pose.front"), L10n.string("selfie.pose.left"), L10n.string("selfie.pose.right")][i])
                    .font(theme.body(12, weight: .semibold))
                    .foregroundStyle(done ? colors.success : active == i ? .white : .white.opacity(0.55))
            }
        }
    }

    private var hints: some View {
        VStack(spacing: 8) {
            if let countdown = presentation.countdown {
                Text("\(countdown)").font(theme.body(30, weight: .semibold))
                    .foregroundStyle(presentation.fillLight ? colors.positive : .white)
                    .accessibilityLabel(L10n.format("selfie.countdown", countdown))
            } else {
                Text(presentation.hint).font(theme.body(16, weight: .semibold))
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(presentation.reached ? colors.positive : .black.opacity(0.55), in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if presentation.status == .far || presentation.status == .near {
                HStack(alignment: .center, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(1..<4, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1).fill(bar <= presentation.distanceLevel ? colors.warning : .white.opacity(0.3))
                                .frame(width: 4, height: CGFloat(2 + bar * 4))
                        }
                    }.accessibilityHidden(true)
                    Text(presentation.status == .far ? L10n.string("selfie.too_far") : L10n.string("selfie.too_close"))
                        .font(theme.body(13, weight: .semibold))
                }.foregroundStyle(colors.warning).padding(.horizontal, 12).padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            if presentation.fillLight {
                Text(L10n.string("selfie.low_light")).font(theme.body(13, weight: .medium))
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            }
        }.frame(maxWidth: .infinity)
    }
}
#endif
