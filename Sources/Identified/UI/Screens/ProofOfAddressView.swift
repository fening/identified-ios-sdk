#if os(iOS)
import IdentifiedCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// `ProofOfAddressCapture.tsx` as its own screen: Documents' proof of
/// address phase on the web.
struct ProofOfAddressView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @Environment(\.captureEnvironment) private var capture
    @State private var address: StatedAddress?
    @State private var lookupUnavailable = false
    @State private var pages = 0
    @State private var busy = false
    @State private var refusal: String?
    @State private var exhausted = false
    @State private var error: String?
    @State private var choosingSource = false
    @State private var importingFile = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var usingCamera = false
    @State private var pendingCameraData: Data?

    private var policy: ProofOfAddressPolicy { flow.session?.proofOfAddressPolicy ?? .standard }

    var body: some View {
        FlowScaffold(title: DocLabel.text(DocType.proofOfAddress),
                     subtitle: address == nil ? nil : L10n.string("poa.subtitle"),
                     step: .proofOfAddress, showsFooter: address != nil && pendingCameraData == nil) {
            if address == nil {
                AddressStepView { stated, unavailable in
                    guard !busy else { return }
                    busy = true
                    Task {
                        // Finish the metadata write before offering an upload.
                        await flow.saveAddress(stated)
                        address = stated
                        lookupUnavailable = unavailable
                        busy = false
                    }
                }
            } else {
                documentStep
            }
        } footer: {
            if address != nil && pendingCameraData == nil {
                if pages > 0 {
                    PrimaryButton(title: L10n.string("flow.continue"), enabled: !busy) { flow.completed(.proofOfAddress) }
                }
                if !exhausted && pages < ProofOfAddressRules.maxPages {
                    if pages == 0 {
                        PrimaryButton(title: L10n.string("poa.choose_file"), busy: busy) { choosingSource = true }
                    } else {
                        SecondaryButton(title: L10n.string("poa.choose_file"), enabled: !busy) { choosingSource = true }
                    }
                    SecondaryButton(title: pages == 0 ? L10n.string("poa.take_photo") : L10n.string("poa.add_page"), enabled: !busy) {
                        usingCamera = true
                    }
                }
            }
        }
        .confirmationDialog(L10n.string("poa.choose_file"), isPresented: $choosingSource) {
            Button(L10n.string("poa.source.files")) { importingFile = true }
            Button(L10n.string("poa.source.photos")) { choosingPhoto = true }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: allowedTypes) { result in
            guard case let .success(url) = result else { return }
            Task { await importFile(url) }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { item in
            guard let item else { return }
            photo = nil
            Task { await importPhoto(item) }
        }
        .fullScreenCover(isPresented: $usingCamera) {
            DocumentCameraView(label: DocLabel.text(DocType.proofOfAddress), environment: capture, onCapture: { data in
                guard !busy, !exhausted, pages < ProofOfAddressRules.maxPages else {
                    usingCamera = false
                    return
                }
                pendingCameraData = data
                refusal = nil
                error = nil
                usingCamera = false
            }, close: { usingCamera = false })
            .environmentObject(flow)
            .environment(\.theme, theme)
        }
    }

    private var documentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            requirements
            if let address {
                Card {
                    Text(L10n.string("poa.your_address").uppercased()).font(theme.body(11, weight: .medium)).tracking(1.3).foregroundStyle(theme.palette.textSecondary)
                    HStack {
                        Text(DigitalAddressCode.displayForm(address.code)).font(theme.heading(17)).foregroundStyle(theme.palette.textPrimary)
                        Spacer()
                        if pages == 0 && pendingCameraData == nil { LinkButton(title: L10n.string("poa.change")) { self.address = nil } }
                    }
                    if lookupUnavailable { BodyText(L10n.string("poa.address.unchecked"), secondary: true, size: 13) }
                }
            }
            if let data = pendingCameraData {
                CapturePreview(image: data, label: DocLabel.text(DocType.proofOfAddress), retake: {
                    guard !busy else { return }
                    pendingCameraData = nil
                    refusal = nil
                    error = nil
                    usingCamera = true
                }) {
                    Task { await upload(PreparedFile(data: data, mimeType: "image/jpeg")) }
                }
                .disabled(busy || exhausted || pages >= ProofOfAddressRules.maxPages)
            }
            if pages > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    BodyText(pages == 1 ? L10n.string("poa.pages.one") : L10n.format("poa.pages.many", pages), size: 15)
                    BodyText(pages < ProofOfAddressRules.maxPages ? L10n.string("poa.pages.more") : L10n.string("poa.pages.max"), secondary: true, size: 14)
                }
                .accessibilityElement(children: .combine)
            }
            if busy { LoadingView(text: L10n.string("documents.uploading"), showsHeader: false).frame(height: 80) }
            if let refusal { ErrorText(message: refusal) }
            if let error { ErrorText(message: error) }
            CapturedStripView()
        }
    }

    private var requirements: some View {
        Card {
            if !policy.acceptedTypes.isEmpty {
                Text(L10n.string("poa.requirements.title")).font(theme.heading(17)).foregroundStyle(theme.palette.textPrimary)
                ForEach(policy.acceptedTypes, id: \.key) { type in
                    BodyText(type.hint.map { L10n.format("poa.requirements.type", type.label, $0) } ?? type.label, size: 15)
                }
            }
            BodyText(L10n.format("poa.requirements.age", ProofOfAddressRules.months(policy.maxAgeDays)), secondary: true, size: 14)
            BodyText(L10n.format("poa.requirements.formats", formatList, ProofOfAddressRules.megabytes(policy.maxSizeBytes)), secondary: true, size: 14)
        }
    }

    /// "photo or PDF".
    private var formatList: String {
        let names = ProofOfAddressRules.formatNames(policy.acceptedFormats).map { name in
            name == .pdf ? L10n.string("poa.format.pdf") : L10n.string("poa.format.photo")
        }
        guard let last = names.last else { return L10n.string("poa.format.any") }
        return names.count == 1 ? last : L10n.format("poa.format.or", names.dropLast().joined(separator: ", "), last)
    }

    private var allowedTypes: [UTType] {
        let types = policy.acceptedFormats.compactMap { UTType(mimeType: $0) }
        return types.isEmpty ? [.image, .pdf] : types
    }

    private func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = L10n.string("poa.unreadable")
            return
        }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension) ?? .data
        await prepareAndUpload(data, type: type)
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            error = L10n.string("poa.unreadable")
            return
        }
        await prepareAndUpload(data, type: item.supportedContentTypes.first ?? .jpeg)
    }

    private func prepareAndUpload(_ data: Data, type: UTType) async {
        error = nil
        do {
            await upload(try FilePreparation.prepare(data, contentType: type, maxBytes: policy.maxSizeBytes))
        } catch let failure as FilePreparationError {
            error = switch failure {
            case let .tooLarge(megabytes): L10n.format("poa.too_large", megabytes)
            case .unreadable: L10n.string("poa.unreadable")
            case .failed: L10n.string("poa.prepare_failed")
            }
        } catch {
            self.error = L10n.string("poa.prepare_failed")
        }
    }

    private func upload(_ file: PreparedFile) async {
        guard !busy, !exhausted, pages < ProofOfAddressRules.maxPages else { return }
        busy = true
        error = nil
        refusal = nil
        defer { busy = false }
        do {
            try await flow.upload(docType: DocType.proofOfAddress, captureRole: ProofOfAddressRules.captureRole(forPage: pages + 1),
                                  data: file.data, mimeType: file.mimeType)
            pages += 1
            pendingCameraData = nil
        } catch let APIError.documentRefused(message, isExhausted) {
            refusal = message.isEmpty ? L10n.string("poa.refused") : message
            exhausted = isExhausted
            if isExhausted { pendingCameraData = nil }
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("documents.error")
        }
    }
}
#endif
