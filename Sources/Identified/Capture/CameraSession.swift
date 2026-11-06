import Foundation

/// One camera for one screen: permission, start, stop, and what went wrong.
@MainActor
final class CameraSession: ObservableObject {
    enum State: Equatable {
        case idle, starting, running
        /// The subject refused camera access; the screen offers Settings.
        case denied
        /// No camera at this position. Ends the flow with `noCamera`.
        case unavailable
        /// The camera would not start; the screen offers a retry.
        case failed
    }

    @Published private(set) var state: State = .idle
    let source: FrameSource?
    private let needsPermission: Bool
    private var starting = false
    private var startID: UUID?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(environment: CaptureEnvironment, position: CameraPosition) {
        source = environment.makeSource(position)
        needsPermission = environment.needsPermission
    }

    func start(onFrame: @escaping @Sendable (CameraFrame) -> Void) async {
        guard state != .running, !Task.isCancelled else { return }
        let attempt = UUID()
        startID = attempt
        // A returning screen may request a restart before an old start finishes.
        // Wait for its cleanup, then start only if this request is still wanted.
        while starting {
            await withCheckedContinuation { startWaiters.append($0) }
        }
        guard startID == attempt, !Task.isCancelled else { return }
        guard let source else {
            state = .unavailable
            return
        }
        starting = true
        defer {
            starting = false
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        state = .starting
        #if os(iOS)
        if needsPermission {
            switch CameraPermission.status {
            case .authorized: break
            case .notDetermined:
                let granted = await CameraPermission.request()
                guard startID == attempt, !Task.isCancelled else {
                    stopSource()
                    return
                }
                guard granted else {
                    state = .denied
                    return
                }
            default:
                state = .denied
                return
            }
        }
        #endif
        guard startID == attempt, !Task.isCancelled else {
            stopSource()
            return
        }
        do {
            try await source.start(onFrame: onFrame)
            guard startID == attempt, !Task.isCancelled else {
                stopSource()
                return
            }
            state = .running
        } catch {
            guard startID == attempt, !Task.isCancelled else {
                stopSource()
                return
            }
            #if os(iOS)
            state = (error as? CameraError) == .unavailable ? .unavailable : .failed
            #else
            state = .failed
            #endif
        }
    }

    func stop() {
        startID = nil
        stopSource()
    }

    private func stopSource() {
        source?.stop()
        if state == .running || state == .starting { state = .idle }
    }
}
