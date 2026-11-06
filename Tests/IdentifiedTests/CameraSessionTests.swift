import Foundation
import Testing
@testable import Identified

private actor StartGate {
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var started = false
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { pending = $0; started = true }
    }

    func release() { released = true; pending?.resume(); pending = nil }
}

private final class DelayedFrameSource: FrameSource, @unchecked Sendable {
    let gate = StartGate()
    private let lock = NSLock()
    private var running = false
    var isRunning: Bool { lock.withLock { running } }

    func start(onFrame: @escaping @Sendable (CameraFrame) -> Void) async throws {
        await gate.wait()
        lock.withLock { running = true }
    }

    func stop() { lock.withLock { running = false } }
    func capturePhoto() async throws -> CameraFrame { throw CancellationError() }
}

@MainActor @Test func closingDuringCameraStartDoesNotLeaveTheCameraRunning() async {
    let source = DelayedFrameSource()
    let camera = CameraSession(environment: CaptureEnvironment(makeSource: { _ in source }, needsPermission: false), position: .back)
    let start = Task { await camera.start { _ in } }
    while !(await source.gate.started) { await Task.yield() }
    camera.stop()
    await source.gate.release()
    await start.value
    #expect(camera.state == .idle)
    #expect(!source.isRunning)
}

@MainActor @Test func reopeningDuringCameraStartRestartsAfterTheOldAttemptStops() async {
    let source = DelayedFrameSource()
    let camera = CameraSession(environment: CaptureEnvironment(makeSource: { _ in source }, needsPermission: false), position: .back)
    let first = Task { await camera.start { _ in } }
    while !(await source.gate.started) { await Task.yield() }
    camera.stop()
    var restartRequested = false
    let restart = Task { restartRequested = true; await camera.start { _ in } }
    while !restartRequested { await Task.yield() }
    await source.gate.release()
    await first.value
    await restart.value
    #expect(camera.state == .running)
    #expect(source.isRunning)
    camera.stop()
}

@MainActor @Test func closingAgainInvalidatesAQueuedCameraRestart() async {
    let source = DelayedFrameSource()
    let camera = CameraSession(environment: CaptureEnvironment(makeSource: { _ in source }, needsPermission: false), position: .back)
    let first = Task { await camera.start { _ in } }
    while !(await source.gate.started) { await Task.yield() }
    camera.stop()
    var restartRequested = false
    let restart = Task { restartRequested = true; await camera.start { _ in } }
    while !restartRequested { await Task.yield() }
    camera.stop()
    await source.gate.release()
    await first.value
    await restart.value
    #expect(camera.state == .idle)
    #expect(!source.isRunning)
}
