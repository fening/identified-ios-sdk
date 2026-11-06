@preconcurrency import CoreImage
import Foundation

/// Where camera screens get their frames. `CameraController` on a device;
/// `FixtureFrameSource` in debug builds, so a simulator with no camera can run
/// the flow end to end.
protocol FrameSource: AnyObject, Sendable {
    /// Frames arrive upright and un-mirrored on a background queue. Handle
    /// each synchronously: holding one starves the camera's buffer pool.
    func start(onFrame: @escaping @Sendable (CameraFrame) -> Void) async throws
    func stop()
    /// A full-resolution upright still. For the back camera; the selfie takes
    /// its frames from the stream.
    func capturePhoto() async throws -> CameraFrame
}

#if DEBUG
/// Replays still images as a stream. Debug builds only.
final class FixtureFrameSource: FrameSource, @unchecked Sendable {
    private let images: [CameraFrame]
    private let interval: DispatchTimeInterval
    private let queue = DispatchQueue(label: "cc.identified.fixture-frames")
    private var timer: DispatchSourceTimer?
    private var index = 0

    init(images: [CIImage], framesPerSecond: Double = 15) {
        precondition(!images.isEmpty, "FixtureFrameSource needs at least one image")
        self.images = images.map(CameraFrame.init(image:))
        interval = .milliseconds(Int(1000 / framesPerSecond))
    }

    func start(onFrame: @escaping @Sendable (CameraFrame) -> Void) async throws {
        queue.sync {
            timer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: interval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                onFrame(self.images[self.index % self.images.count])
                self.index += 1
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    func capturePhoto() async throws -> CameraFrame {
        queue.sync { images[index % images.count] }
    }

    /// What the preview shows in place of a live camera.
    var stillImage: CIImage { images[0].image }
}
#endif
