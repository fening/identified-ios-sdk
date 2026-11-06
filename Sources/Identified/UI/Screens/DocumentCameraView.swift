#if os(iOS)
import IdentifiedCore
import Combine
import SwiftUI

@MainActor
final class DocumentCameraModel: ObservableObject {
    @Published private(set) var analysis: DocumentPhotoEngine.Output?
    @Published private(set) var capturing = false
    let camera: CameraSession
    private var cameraChanges: AnyCancellable?
    private let engine = DocumentPhotoEngine()
    private var generation: UUID?
    private var previewSize: PixelSize?
    private let onCapture: @MainActor (Data) -> Void

    init(environment: CaptureEnvironment, onCapture: @escaping @MainActor (Data) -> Void) {
        camera = CameraSession(environment: environment, position: .back)
        (camera.source as? CameraController)?.prefersHighResolutionPhoto = true
        self.onCapture = onCapture
        cameraChanges = camera.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func start() async {
        guard camera.state != .running else { return }
        let attempt = UUID()
        generation = attempt
        analysis = nil
        engine.reset()
        await camera.start { [engine, weak self] frame in
            let now = ProcessInfo.processInfo.systemUptime
            guard let output = engine.process(frame, at: now) else { return }
            Task { @MainActor in
                guard let self, self.generation == attempt, !self.capturing,
                      self.previewSize == output.viewSize else { return }
                guard ProcessInfo.processInfo.systemUptime - now <= 0.5, self.camera.state == .running else {
                    if output.fire { engine.reset() }
                    return
                }
                self.analysis = output
                if output.fire { await self.capture() }
            }
        }
    }

    func stop() {
        generation = nil
        capturing = false
        camera.stop()
    }

    func setViewSize(_ size: CGSize) {
        let preview = PixelSize(width: size.width, height: size.height)
        guard preview.width > 0, preview.height > 0, preview != previewSize else { return }
        previewSize = preview
        analysis = nil
        engine.setViewSize(preview)
    }

    func capture() async {
        guard let attempt = generation, !capturing, camera.state == .running, let source = camera.source else { return }
        capturing = true
        if let still = try? await source.capturePhoto(), generation == attempt {
            let photo = await Task.detached(priority: .userInitiated) { [engine] in
                autoreleasepool { engine.crop(still) }
            }.value
            guard generation == attempt else { return }
            if let photo {
                stop()
                onCapture(photo)
                return
            }
        }
        guard generation == attempt else { return }
        engine.reset()
        analysis = nil
        capturing = false
    }
}

struct DocumentCameraView: View {
    let label: String
    let close: () -> Void
    @StateObject private var model: DocumentCameraModel
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    init(label: String, environment: CaptureEnvironment, onCapture: @escaping @MainActor (Data) -> Void, close: @escaping () -> Void) {
        self.label = label
        self.close = close
        _model = StateObject(wrappedValue: DocumentCameraModel(environment: environment, onCapture: onCapture))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPhotoStage(card: false, hint: model.camera.state == .running ? hintText : nil) {
                    CameraPreview(source: model.camera.source)
                        .overlay {
                            if let page = model.analysis?.page {
                                DocumentPageOutline(page: page)
                                    .stroke(outlineColor, lineWidth: 2.5)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                if model.camera.state == .denied || model.camera.state == .failed {
                    CameraProblemView(state: model.camera.state) { Task { await model.start() } }
                }
                VStack(spacing: 16) {
                    HStack { CameraBackButton { model.stop(); close() }; Spacer() }
                        .padding(.horizontal, 16)
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                    Spacer()
                    ShutterButton(
                        label: model.camera.state == .running ? L10n.format("camera.capture", label) : L10n.string("camera.starting"),
                        enabled: model.camera.state == .running && !model.capturing
                    ) { Task { await model.capture() } }
                    .frame(maxWidth: .infinity, alignment: geometry.size.width > geometry.size.height ? .trailing : .center)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
            }
            .onAppear { model.setViewSize(cameraPhotoPreviewSize(in: geometry.size)) }
            .onChange(of: geometry.size) { model.setViewSize(cameraPhotoPreviewSize(in: $0)) }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.camera.state) { state in
            if state == .unavailable { flow.failWithoutCamera() }
        }
    }

    private var outlineColor: Color {
        model.analysis?.hint == .looksSharp
            ? CameraStageColors(theme: theme, scheme: colorScheme).success
            : .white.opacity(0.9)
    }

    private var hintText: String {
        if model.capturing { return L10n.string("card.hint.capturing") }
        switch model.analysis?.hint {
        case .tooDark: return L10n.string("poa.hint.dark")
        case .tooMuchGlare: return L10n.string("poa.hint.glare")
        case .tooBright: return L10n.string("poa.hint.bright")
        case .blurry where model.analysis?.page != nil: return L10n.string("poa.hint.blurry")
        case .looksSharp where model.analysis?.page != nil: return L10n.string("poa.hint.hold")
        default: return L10n.string("poa.hint.fit_page")
        }
    }
}

private struct DocumentPageOutline: Shape {
    let page: DocumentPage

    func path(in rect: CGRect) -> Path {
        let points = page.corners.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + (1 - $0.y) * rect.height)
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
#endif
