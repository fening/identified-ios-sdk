#if os(iOS)
import IdentifiedCore
import Combine
import SwiftUI

@MainActor
final class CardCameraModel: ObservableObject {
    @Published private(set) var hint: CardHint = .fitEdges
    @Published private(set) var ready = false
    @Published private(set) var sourceAspect = 3.0 / 4.0
    @Published private(set) var capturing = false
    let camera: CameraSession
    private var cameraChanges: AnyCancellable?
    private let engine = CardCaptureEngine()
    private var generation: UUID?
    private let onCapture: @MainActor (Data) -> Void

    init(environment: CaptureEnvironment, onCapture: @escaping @MainActor (Data) -> Void) {
        camera = CameraSession(environment: environment, position: .back)
        (camera.source as? CameraController)?.prefersFullFrameCard = true
        self.onCapture = onCapture
        cameraChanges = camera.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func start() async {
        let attempt = UUID()
        generation = attempt
        capturing = false
        engine.reset()
        await camera.start { [engine, weak self] frame in
            guard let output = engine.process(frame, at: ProcessInfo.processInfo.systemUptime) else { return }
            Task { @MainActor in
                guard let self, self.generation == attempt else { return }
                self.apply(output, generation: attempt)
            }
        }
    }

    /// Invalidate before navigation: physical photo delivery can outlive stop().
    func stop() {
        generation = nil
        capturing = false
        camera.stop()
    }

    func setViewSize(_ size: CGSize) {
        engine.setViewSize(PixelSize(width: size.width, height: size.height))
    }

    /// The shutter, or auto-capture firing.
    func capture() async {
        guard let attempt = generation, !Task.isCancelled, !capturing, camera.state == .running, let source = camera.source else { return }
        capturing = true
        do {
            let still = try await source.capturePhoto()
            guard generation == attempt, !Task.isCancelled else { return }
            if let jpeg = engine.crop(still) {
                stop()
                onCapture(jpeg)
                return
            }
        } catch {}
        guard generation == attempt, !Task.isCancelled else { return }
        capturing = false
        engine.reset()
    }

    private func apply(_ output: CardCaptureEngine.Output, generation attempt: UUID) {
        sourceAspect = output.sourceAspect
        hint = output.hint
        ready = output.ready
        if output.fire {
            Task {
                guard generation == attempt else { return }
                await capture()
            }
        }
    }
}

/// `CameraCapture.tsx` with the card guide: back camera, a mask with an ID
/// sized window, the detector's hint, auto-capture and a manual shutter.
struct CardCameraView: View {
    let label: String
    let close: () -> Void
    @StateObject private var model: CardCameraModel
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme

    init(label: String, environment: CaptureEnvironment, onCapture: @escaping @MainActor (Data) -> Void, close: @escaping () -> Void) {
        self.label = label
        self.close = close
        _model = StateObject(wrappedValue: CardCameraModel(environment: environment, onCapture: onCapture))
    }

    var body: some View {
        // The geometry is the whole screen, which is what the preview fills:
        // the guide drawn here must be the rect the detector analyses.
        GeometryReader { geometry in
            ZStack {
                CameraPhotoStage(card: true, ready: model.ready, sourceAspect: model.sourceAspect,
                                 hint: model.camera.state == .denied || model.camera.state == .failed ? nil : hintText) {
                    CameraPreview(source: model.camera.source, aspectFit: true)
                }
                if model.camera.state == .denied || model.camera.state == .failed {
                    CameraProblemView(state: model.camera.state) { Task { await model.start() } }
                }
                VStack {
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
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }
            }
            .onAppear { model.setViewSize(geometry.size) }
            .onChange(of: geometry.size) { model.setViewSize($0) }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.camera.state) { state in
            if state == .unavailable { flow.failWithoutCamera() }
        }
    }

    private var hintText: String {
        switch model.hint {
        case .fitEdges: L10n.string("card.hint.fit_edges")
        case .moveToLight: L10n.string("card.hint.light")
        case .removeGlare: L10n.string("card.hint.glare")
        case .holdStillCloser: L10n.string("card.hint.closer")
        case .capturing: L10n.string("card.hint.capturing")
        }
    }

}
#endif
