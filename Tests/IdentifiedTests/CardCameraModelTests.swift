#if os(iOS)
import Foundation
import Testing
@testable import Identified

/// Holds physical photo responses even after stop, as AVFoundation can do.
private actor CardPhotoGate {
    private var pending: [Int: CheckedContinuation<CameraFrame, Error>] = [:]
    private var requests = 0
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func capture() async throws -> CameraFrame {
        let id = requests
        requests += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let ready = observers.filter { $0.0 <= requests }
            observers.removeAll { $0.0 <= requests }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func release(_ id: Int, failing: Bool = false) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if failing { continuation.resume(throwing: CancellationError()) }
        else { continuation.resume(returning: flatFrame(width: 960, height: 1280)) }
    }
}

private final class DelayedCardPhotoSource: FrameSource, @unchecked Sendable {
    let photos = CardPhotoGate()
    func start(onFrame: @escaping @Sendable (CameraFrame) -> Void) async throws {
        onFrame(flatFrame(width: 960, height: 1280))
    }
    func stop() {}
    func capturePhoto() async throws -> CameraFrame { try await photos.capture() }
}

@MainActor @Test(arguments: [false, true])
func dismissedCardCameraIgnoresDelayedPhoto(failing: Bool) async {
    let source = DelayedCardPhotoSource()
    var captures = 0
    let model = CardCameraModel(environment: .init(makeSource: { _ in source }, needsPermission: false)) { _ in captures += 1 }
    model.setViewSize(CGSize(width: 390, height: 844))
    await model.start()
    let capture = Task { await model.capture() }
    await source.photos.waitForRequests(1)
    #expect(model.capturing)
    model.stop()
    #expect(!model.capturing && model.camera.state == .idle)
    await source.photos.release(0, failing: failing)
    await capture.value
    #expect(captures == 0)
    #expect(!model.capturing && model.camera.state == .idle)
}

@MainActor @Test(arguments: [false, true])
func staleCardPhotoCannotAffectReopenedCamera(failing: Bool) async {
    let source = DelayedCardPhotoSource()
    var captures = 0
    let model = CardCameraModel(environment: .init(makeSource: { _ in source }, needsPermission: false)) { _ in captures += 1 }
    model.setViewSize(CGSize(width: 390, height: 844))
    await model.start()
    let stale = Task { await model.capture() }
    await source.photos.waitForRequests(1)
    model.stop()
    await model.start()
    let current = Task { await model.capture() }
    await source.photos.waitForRequests(2)
    await source.photos.release(0, failing: failing)
    await stale.value
    #expect(captures == 0)
    #expect(model.capturing && model.camera.state == .running)
    await source.photos.release(1)
    await current.value
    #expect(captures == 1)
    #expect(!model.capturing && model.camera.state == .idle)
}
#endif
