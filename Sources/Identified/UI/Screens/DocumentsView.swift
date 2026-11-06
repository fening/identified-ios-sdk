#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Documents.tsx` for the ID phase. Proof of address has its own screen.
struct DocumentsView: View {
    let startAt: String?
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @Environment(\.captureEnvironment) private var capture
    @State private var index = 0
    @State private var stage: Stage = .brief
    @State private var error: String?
    @State private var started = false
    @State private var uploadTask: Task<Void, Never>?

    private enum Stage: Equatable {
        case brief, camera
        case preview(Data)
        case uploading
    }

    var body: some View {
        let steps = FlowRules.documentSteps(flow.session?.requiredDocuments ?? [], phase: .documents)
        if steps.indices.contains(index) {
            let docType = steps[index]
            VStack(spacing: 0) {
                if stage == .uploading {
                    LoadingView(text: L10n.string("documents.uploading"))
                } else {
                    FlowScaffold(title: DocLabel.text(docType), subtitle: subtitle, step: .documents, onBack: index > 0 ? { index -= 1; stage = .brief; error = nil } : nil) {
                        VStack(alignment: .leading, spacing: 16) {
                            if case let .preview(data) = stage {
                                CapturePreview(image: data, label: DocLabel.text(docType), retake: { stage = .camera }) {
                                    uploadTask = Task { await upload(data, docType: docType, isLast: index == steps.count - 1) }
                                }
                            } else {
                                brief(docType)
                                PrimaryButton(title: L10n.string("brief.open_camera")) { stage = .camera }
                                    .padding(.top, 8)
                            }
                            if let error { ErrorText(message: error) }
                            CapturedStripView()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { stage == .camera }, set: { if !$0 && stage == .camera { stage = .brief } })) {
                CardCameraView(label: DocLabel.text(docType), environment: capture, onCapture: { stage = .preview($0) }, close: { stage = .brief })
                    .environmentObject(flow)
                    .environment(\.theme, theme)
            }
            .onDisappear { uploadTask?.cancel() }
            .onAppear {
                guard !started else { return }
                started = true
                index = startAt.flatMap { steps.firstIndex(of: $0) } ?? 0
            }
        }
    }

    private var subtitle: String? {
        if case .preview = stage { return L10n.string("documents.subtitle") }
        return nil
    }

    @ViewBuilder
    private func brief(_ docType: String) -> some View {
        let (lead, points) = Self.brief(for: docType)
        CaptureBriefView(lead: lead, points: points)
    }

    /// `captureBriefs.ts`.
    private static func brief(for docType: String) -> (String, [String]) {
        let card = [L10n.string("brief.card.point1"), L10n.string("brief.card.point2"), L10n.string("brief.card.point3")]
        switch docType {
        case DocType.licenseBack:
            return (L10n.string("brief.license_back.lead"),
                    [L10n.string("brief.license_back.point1"), L10n.string("brief.license_back.point2"), L10n.string("brief.license_back.point3")])
        case DocType.governmentId:
            return (L10n.string("brief.government_id.lead"), card)
        default:
            return (L10n.string("brief.license_front.lead"), card)
        }
    }

    private func upload(_ data: Data, docType: String, isLast: Bool) async {
        let sourcePath = flow.path
        stage = .uploading
        error = nil
        do {
            try await flow.upload(docType: docType, data: data, mimeType: "image/jpeg")
            guard !Task.isCancelled, flow.path == sourcePath else { return }
            if flow.mode == .resume || isLast {
                // NavigationStack retains this route for Back. Restore its
                // accepted preview before pushing the next screen.
                stage = .preview(data)
                flow.completed(.documents)
            } else {
                index += 1
                stage = .brief
            }
        } catch {
            guard !Task.isCancelled, flow.path == sourcePath else { return }
            // A refusal is shown verbatim; the web drops it for ID cards.
            self.error = flow.message(for: error) ?? L10n.string("documents.error")
            stage = .preview(data)
        }
    }
}
#endif
