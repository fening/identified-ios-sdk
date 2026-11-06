import Foundation
import Testing
@testable import Identified
import IdentifiedCore
import IdentifiedTestSupport

/// Deliberately ignores cancellation, like a response already in flight.
private actor DelayedBusyResponse: HTTPTransport {
    let base: StubTransport
    let suffix: String
    private var paused = false
    private var responseGate: CheckedContinuation<Void, Never>?
    private var pauseObserver: CheckedContinuation<Void, Never>?

    init(base: StubTransport, suffix: String) {
        self.base = base
        self.suffix = suffix
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = try await base.send(request)
        if request.url?.path.hasSuffix(suffix) == true {
            paused = true
            pauseObserver?.resume()
            pauseObserver = nil
            await withCheckedContinuation { responseGate = $0 }
        }
        return response
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { pauseObserver = $0 }
    }

    func release() {
        responseGate?.resume()
        responseGate = nil
    }
}

@MainActor @Test(arguments: [false, true])
func lateBusyResponseDoesNotUndoBack(submitting: Bool) async {
    let base = StubTransport(.data(Fixtures.sessionJSON(["case_id": "case-1", "consent_recorded": true])))
    if submitting {
        base.enqueue([.data([:]), .data(["case_id": "case-1", "status": "submitted"])])
    } else {
        base.enqueue([
            .json(200, ["success": true]), .json(200, ["success": true]), .json(200, ["success": true]),
            .data(["check_type": "biometric_face_match", "status": "completed"]),
        ])
    }
    let transport = DelayedBusyResponse(base: base, suffix: submitting ? "/submit" : "/checks/biometric")
    let model = FlowModel(client: APIClient(baseURL: URL(string: "https://api.test")!, sessionToken: "tok", transport: transport)) { _ in }
    await model.load()
    model.path = [.checklist, submitting ? .review : .selfie]
    let operation = Task {
        do {
            if submitting {
                try await model.submit(reportOptIn: false, email: "")
            } else {
                let frame = Data([0xFF, 0xD8])
                try await model.uploadSelfie([SelfieRole.center: frame, SelfieRole.left: frame, SelfieRole.right: frame])
            }
            return false
        } catch is CancellationError {
            return true
        } catch {
            Issue.record("Unexpected busy-operation error: \(error)")
            return false
        }
    }
    await transport.waitUntilPaused()
    model.path.removeLast()
    await transport.release()
    let abandoned = await operation.value
    #expect(abandoned)
    #expect(model.path == [.checklist])
}

@MainActor @Test func aLateAcceptedUploadCannotRepopulateAFinishedFlowsThumbnails() async throws {
    let base = StubTransport(
        .data(Fixtures.sessionJSON(["case_id": "case-1"])),
        .json(200, ["success": true])
    )
    let transport = DelayedBusyResponse(base: base, suffix: "/documents")
    let model = FlowModel(client: APIClient(baseURL: URL(string: "https://api.test")!, sessionToken: "tok", transport: transport)) { _ in }
    await model.load()
    let operation = Task {
        try await model.upload(docType: DocType.proofOfAddress, data: Data("%PDF".utf8), mimeType: "application/pdf")
    }
    await transport.waitUntilPaused()
    model.close()
    #expect(model.capturedItems.isEmpty)
    await transport.release()
    try await operation.value
    #expect(model.capturedItems.isEmpty)
}

@MainActor @Test func selfieRestoresItsRetainedScreenBeforeAdvancing() async throws {
    let base = StubTransport(
        .data(Fixtures.sessionJSON()), .data([:]), .data(Fixtures.caseJSON()),
        .json(200, ["success": true]), .json(200, ["success": true]), .json(200, ["success": true]),
        .data(["check_type": "biometric_face_match", "status": "completed"])
    )
    let model = FlowModel(client: client(base)) { _ in }
    await model.load()
    try await model.consent()
    let sourcePath: [FlowRoute] = [.checklist, .selfie]
    model.path = sourcePath
    var readyForBack = false
    let frame = Data([0xFF, 0xD8])
    try await model.uploadSelfie([SelfieRole.center: frame, SelfieRole.left: frame, SelfieRole.right: frame]) {
        #expect(model.path == sourcePath)
        readyForBack = true
    }
    #expect(readyForBack)
    #expect(model.path == sourcePath + [.review])
    model.path.removeLast()
    #expect(model.path == sourcePath)
}
