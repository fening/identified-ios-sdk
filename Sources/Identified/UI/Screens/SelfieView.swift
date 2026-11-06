#if os(iOS)
import IdentifiedCore
import SwiftUI
import UIKit

/// `Selfie.tsx`.
struct SelfieView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @Environment(\.captureEnvironment) private var capture
    @State private var stage: Stage = .brief
    @State private var error: String?
    @State private var uploadTask: Task<Void, Never>?
    #if DEBUG
    @State private var debugID = String(UUID().uuidString.prefix(4))
    #endif

    private enum Stage: Equatable {
        case brief, camera
        case preview([String: Data])
        case processing

        var debugName: String {
            switch self {
            case .brief: "brief"
            case .camera: "camera"
            case let .preview(frames): "preview(\(frames.keys.sorted().joined(separator: ",")))"
            case .processing: "processing"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if stage == .processing {
                ProcessingView(
                    messages: [L10n.string("selfie.processing.scanning"), L10n.string("selfie.processing.matching")],
                    detail: L10n.string("selfie.processing.detail"), variant: .faceMatch, step: .selfie
                )
                .navigationBarBackButtonHidden(true)
            } else {
                FlowScaffold(title: L10n.string("selfie.title"), step: .selfie, compactTitle: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        if case let .preview(frames) = stage {
                            preview(frames)
                            HStack(spacing: 12) {
                                SelfieReviewButton(title: L10n.string("camera.retake")) { stage = .camera }
                                SelfieReviewButton(title: L10n.string("camera.use"), primary: true) { uploadTask = Task { await upload(frames) } }
                            }
                        } else {
                            brief
                            PrimaryButton(title: L10n.string("brief.open_camera")) { error = nil; stage = .camera }
                                .padding(.top, 8)
                        }
                        if let error { ErrorText(message: error) }
                        CapturedStripView()
                    }
                }
            }
        }
        .onDisappear { uploadTask?.cancel() }
        #if DEBUG
        .onAppear { DebugLog.event("selfie.view \(debugID) appear stage=\(stage.debugName)") }
        .onDisappear { DebugLog.event("selfie.view \(debugID) disappear stage=\(stage.debugName)") }
        .onChange(of: stage) { DebugLog.event("selfie.view \(debugID) stage=\($0.debugName)") }
        #endif
        .fullScreenCover(isPresented: Binding(get: { stage == .camera }, set: { if !$0 && stage == .camera { stage = .brief } })) {
            SelfieCameraView(environment: capture, onComplete: finished, close: {
                #if DEBUG
                DebugLog.event("selfie.camera close")
                #endif
                stage = .brief
            })
                .environmentObject(flow)
                .environment(\.theme, theme)
        }
    }

    private var brief: some View {
        CaptureBriefView(lead: L10n.string("brief.selfie.lead"), points: [
            L10n.string("brief.selfie.point1"), L10n.string("brief.selfie.point2"), L10n.string("brief.selfie.point3"),
        ])
    }

    private func preview(_ frames: [String: Data]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = frames[SelfieRole.center], let image = UIImage(data: data) {
                SelfieReviewImage(image: image)
                    .accessibilityLabel(L10n.string("selfie.review.alt"))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            BodyText(L10n.string("selfie.review.text"), secondary: true, size: 15)
                .padding(.horizontal, 4)
        }
    }

    private func finished(_ frames: [String: Data]) {
        #if DEBUG
        DebugLog.event("selfie.finished frames=\(frames.keys.sorted().joined(separator: ","))")
        #endif
        guard frames.count == SelfieRole.all.count else {
            error = L10n.string("selfie.too_few")
            stage = .brief
            return
        }
        stage = .preview(frames)
    }

    private func upload(_ frames: [String: Data]) async {
        stage = .processing
        error = nil
        #if DEBUG
        DebugLog.event("selfie.upload start")
        #endif
        do {
            try await flow.uploadSelfie(frames) {
                #if DEBUG
                DebugLog.event("selfie.upload accepted")
                #endif
                // The next route can navigate Back to this accepted preview.
                stage = .preview(frames)
            }
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            DebugLog.event("selfie.upload failed \(error)")
            #endif
            guard !Task.isCancelled else { return }
            self.error = flow.message(for: error) ?? L10n.string("selfie.error")
            stage = .preview(frames)
        }
    }
}
/// Preserve the captured image's natural aspect ratio, as the hosted img does.
/// Bound portrait height so review actions remain reachable.
struct SelfieReviewImage: View {
    let image: UIImage
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius)
        return SelfieReviewLayout(aspect: image.size.width / max(1, image.size.height)) {
            Image(uiImage: image).resizable()
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.palette.border, lineWidth: 1))
        }
    }
}

private struct SelfieReviewLayout: Layout {
    let aspect: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxHeight = min(320, proposal.height ?? 320)
        let width = min(proposal.width ?? maxHeight * aspect, maxHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private struct SelfieReviewButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title).font(theme.body(15, weight: primary ? .semibold : .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(primary ? theme.palette.onAccent : theme.palette.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(primary ? theme.palette.accent : .clear, in: RoundedRectangle(cornerRadius: theme.radius * 0.75))
                .overlay(RoundedRectangle(cornerRadius: theme.radius * 0.75)
                    .stroke(primary ? .clear : theme.palette.border, lineWidth: 1))
                .shadow(color: theme.palette.accent.opacity(primary ? 0.2 : 0), radius: 10, x: 0, y: 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
