import Foundation
import IdentifiedCore

enum FlowError: LocalizedError {
    /// A step that needs the case was reached before one exists.
    case noCase
    case incompleteSelfie

    var errorDescription: String? {
        switch self {
        case .noCase: L10n.string("status.no_case")
        case .incompleteSelfie: L10n.string("selfie.too_few")
        }
    }
}

/// The state of one verification flow: the session, the case, where the
/// subject is, and how the flow ends. Routing comes from `FlowRouting`; this
/// type applies it to the navigation path.
@MainActor
final class FlowModel: ObservableObject {
    enum Stage: Equatable {
        case loading
        /// The service could not be reached. Entry offers a retry.
        case unavailable(String)
        case ready
    }

    @Published private(set) var stage: Stage = .loading
    @Published var path: [FlowRoute] = []
    @Published private(set) var session: HostedSession?
    @Published private(set) var verificationCase: VerificationCase?
    @Published private(set) var statusError: String?
    @Published private(set) var capturedItems: [AcceptedCapture] = []
    private(set) var mode: NavigationMode = .firstRun
    private(set) var entryDestination: EntryDestination = .consent

    let client: APIClient
    private let onFinish: @MainActor (IdentifiedResult) -> Void
    private var launchHadCase = false
    private var finished = false

    init(client: APIClient, onFinish: @escaping @MainActor (IdentifiedResult) -> Void) {
        self.client = client
        self.onFinish = onFinish
    }

    var caseId: String? { verificationCase?.id ?? session?.caseId }

    // MARK: Launch

    func load() async {
        stage = .loading
        switch await Launch.load(using: client) {
        case let .success(state):
            session = state.session
            mode = state.mode
            launchHadCase = state.session.caseId != nil
            switch state.route {
            case let .entry(destination): entryDestination = destination
            case .status: path = [.status]
            }
            stage = .ready
        case let .failure(failure):
            if let error = IdentifiedError(launchFailure: failure) {
                finish(.failed(error))
            } else if case let .unavailable(message) = failure {
                stage = .unavailable(message)
            }
        }
    }

    /// Entry's button.
    func begin() {
        switch entryDestination {
        case .consent: path = [.consent]
        case .checklist: path = [.checklist]
        }
    }

    // MARK: Steps

    /// Review reads the case to show what is captured.
    func loadCase() async throws {
        guard let caseId else { throw FlowError.noCase }
        verificationCase = try await client.getCase(id: caseId)
    }


    func consent() async throws {
        guard let session else { return }
        try await client.recordConsent(scopes: FlowRouting.consentScopes(session))
        verificationCase = try await client.getOrCreateCase(for: session)
        path = [.checklist]
    }

    /// The checklist reads the case, and the session too when resuming: a
    /// change request or an earlier visit may have changed what is complete.
    func refreshForChecklist() async throws {
        guard let caseId else { throw FlowError.noCase }
        let latest = try await client.getCase(id: caseId)
        verificationCase = latest
        if launchHadCase || latest.status == CaseStatus.changesRequested {
            session = try await client.currentSession()
        }
        mode = FlowRouting.navigationMode(launchHadCase: launchHadCase, caseStatus: latest.status)
    }

    func continueFromChecklist() {
        guard let session, let verificationCase,
              let destination = FlowRouting.checklistContinue(case: verificationCase, session: session, mode: mode)
        else { return }
        go(destination)
    }

    /// A checklist row's Replace link after a change request.
    func replace(_ docType: String) {
        switch docType {
        case DocType.selfie: go(.selfie)
        case DocType.proofOfAddress: go(.proofOfAddress)
        default: go(.documents(startAt: docType))
        }
    }

    /// The checklist's Update name and Update ID details links.
    func open(_ destination: Destination) {
        go(destination)
    }

    func saveName(first: String, middle: String, last: String) async throws {
        try await save(.name(first: first, middle: middle, last: last))
        try await refetchAndComplete(.yourName)
    }

    func saveIDDetails(dob: String, idType: String, idNumber: String) async throws {
        try await save(.idDetails(dob: dob, idType: idType, idNumber: idNumber, idTypeDisplay: IDDetailsInput.label(for: idType)))
        try await refetchAndComplete(.idDetails)
    }

    func upload(docType: String, captureRole: String? = nil, data: Data, mimeType: String) async throws {
        guard let caseId else { throw FlowError.noCase }
        try await client.uploadDocument(caseId: caseId, docType: docType, captureRole: captureRole, data: data, mimeType: mimeType)
        guard !finished, !Task.isCancelled else { return }
        // The left/right liveness evidence is not an additional submission.
        guard docType != DocType.selfie || captureRole == SelfieRole.center else { return }
        let item = AcceptedCapture(docType: docType, data: data, mimeType: mimeType)
        if let index = capturedItems.firstIndex(where: { $0.docType == docType }) {
            capturedItems[index] = item
        } else {
            if capturedItems.count == AcceptedCapture.maximumItems { capturedItems.removeFirst() }
            capturedItems.append(item)
        }
    }

    /// The three turn-challenge frames, centre last, then liveness and face match.
    func uploadSelfie(_ frames: [String: Data], beforeAdvancing: @MainActor () -> Void = {}) async throws {
        let sourcePath = path
        try requireCurrentOperation(sourcePath)
        guard let caseId else { throw FlowError.noCase }
        guard SelfieRole.all.allSatisfy({ frames[$0]?.isEmpty == false }) else {
            throw FlowError.incompleteSelfie
        }
        let roles = [SelfieRole.left, SelfieRole.right, SelfieRole.center]
        for role in SelfieRole.uploadOrder(of: roles) {
            try await upload(docType: DocType.selfie, captureRole: role, data: frames[role]!, mimeType: "image/jpeg")
            try requireCurrentOperation(sourcePath)
        }
        _ = try await client.runBiometricCheck(caseId: caseId)
        try requireCurrentOperation(sourcePath)
        // Let the retained screen leave its busy state before navigation.
        beforeAdvancing()
        completed(.selfie)
    }

    /// Saved before the document, as the web does. A failure other than a
    /// dead session is not shown: the address is supporting evidence.
    func saveAddress(_ address: StatedAddress) async {
        do {
            try await save(.statedAddress(address))
        } catch {
            _ = message(for: error)
        }
    }

    func submit(reportOptIn: Bool, email: String) async throws {
        let sourcePath = path
        try requireCurrentOperation(sourcePath)
        guard let caseId else { throw FlowError.noCase }
        let address = reportOptIn ? email.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        try await save(.reportDelivery(optIn: reportOptIn, email: address))
        try requireCurrentOperation(sourcePath)
        let result = try await client.submitCase(id: caseId)
        try requireCurrentOperation(sourcePath)
        verificationCase?.status = result.status
        session?.caseStatus = result.status
        go(.status)
    }

    /// A response may arrive after Back/Close even if the transport ignores
    /// cancellation. It must not restart work or restore the abandoned route.
    private func requireCurrentOperation(_ sourcePath: [FlowRoute]) throws {
        try Task.checkCancellation()
        guard !finished, path == sourcePath else { throw CancellationError() }
    }

    /// A screen finished its work: go where the flow goes next.
    func completed(_ screen: FlowScreen) {
        guard let session else { return }
        go(FlowRouting.afterCompleting(screen, session: session, mode: mode))
    }

    // MARK: Status

    /// Reads the case every `interval` until it reaches a final status. Errors
    /// show on the screen and retry on the same interval.
    func pollStatus(every interval: Duration = .seconds(5)) async {
        guard let caseId else {
            statusError = FlowError.noCase.errorDescription
            return
        }
        while !Task.isCancelled {
            do {
                let latest = try await client.getCase(id: caseId)
                verificationCase = latest
                statusError = nil
                if !FlowRouting.shouldKeepPolling(status: latest.status) { return }
            } catch {
                statusError = message(for: error)
                if finished { return }
            }
            try? await Task.sleep(for: interval)
        }
    }

    /// Status's "Update & resubmit".
    func resubmit() {
        mode = .resume
        path = [.checklist]
    }

    // MARK: Ending

    /// The close button. On the status screen the subject has finished;
    /// anywhere else they left before submitting.
    func close() {
        if path.last == .status, let caseId {
            finish(.completed(caseId: caseId, status: verificationCase?.status ?? session?.caseStatus ?? ""))
        } else {
            finish(.cancelled)
        }
    }

    func failWithoutCamera() {
        finish(.failed(.noCamera))
    }

    /// The text a screen shows for an error, or nil when the error ended the
    /// flow (a dead session) or was a cancellation.
    func message(for error: Error) -> String? {
        if error is CancellationError { return nil }
        if let apiError = error as? APIError {
            if let failure = IdentifiedError(apiError: apiError) {
                finish(.failed(failure))
                return nil
            }
            return apiError.message
        }
        return error.localizedDescription
    }

    private func finish(_ result: IdentifiedResult) {
        guard !finished else { return }
        finished = true
        capturedItems.removeAll()
        onFinish(result)
    }

    // MARK: Navigation

    /// A concurrent edit makes the server refuse a save with "verification
    /// details changed" (a 500): refetch the session so the subject's retry
    /// starts from what is saved, then report the error as usual.
    private func save(_ patch: MetadataPatch) async throws {
        do {
            try await client.saveMetadata(patch)
        } catch let APIError.http(status, message) where status == 500 && message.localizedCaseInsensitiveContains("verification details changed") {
            if let latest = try? await client.currentSession() { session = latest }
            throw APIError.http(status: status, message: message)
        }
    }

    /// Metadata saves refetch the session, so the next screen's guard sees
    /// the names and details just saved.
    private func refetchAndComplete(_ screen: FlowScreen) async throws {
        session = try await client.currentSession()
        completed(screen)
    }

    private func go(_ destination: Destination) {
        switch destination {
        case .checklist: path = [.checklist]
        case .status: path = [.status]
        default: path.append(FlowRoute(destination))
        }
    }
}
