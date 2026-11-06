#if os(iOS)
@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import Foundation
import IdentifiedCore

enum CameraError: Error, Equatable {
    case unavailable
    case permissionDenied
    case captureFailed
}

enum CameraPermission {
    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// An AVFoundation camera delivering upright, un-mirrored frames.
///
/// ID and front cameras prefer a bounded native 4:3 video format.
/// PoA retains its 1920x1080 preset. High-resolution photos are independently
/// mapped to the analysed video aspect after capture. The front camera uses a
/// format (at least 1280x960), falling back to 720p. Selfies use stream frames.
final class CameraController: NSObject, FrameSource, @unchecked Sendable {
    enum Position: Sendable { case back, front }

    // Set by the ID screen before starting; PoA retains its existing preset.
    var prefersFullFrameCard = false
    var prefersHighResolutionPhoto = false
    private var highResolutionPhoto: Bool { prefersFullFrameCard || prefersHighResolutionPhoto }
    let position: Position
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cc.identified.camera-session")
    private let frameQueue = DispatchQueue(label: "cc.identified.camera-frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let lock = NSLock()
    private var frameHandler: (@Sendable (CameraFrame) -> Void)?
    private var photoContinuation: CheckedContinuation<CameraFrame, Error>?
    private var configured = false

    init(position: Position) {
        self.position = position
    }

    static func isAvailable(_ position: CameraPosition) -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position == .back ? .back : .front) != nil
    }

    func start(onFrame: @escaping @Sendable (CameraFrame) -> Void) async throws {
        lock.withLock { frameHandler = onFrame }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    if !self.configured {
                        try self.configure()
                        self.configured = true
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        lock.withLock { frameHandler = nil }
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capturePhoto() async throws -> CameraFrame {
        guard position == .back else { throw CameraError.captureFailed }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { photoContinuation = continuation }
            sessionQueue.async {
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.isHighResolutionPhotoEnabled = self.highResolutionPhoto
                if self.highResolutionPhoto { settings.photoQualityPrioritization = .quality }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = position == .back ? .hd1920x1080 : .hd1280x720

        let devicePosition: AVCaptureDevice.Position = position == .back ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition) else {
            throw CameraError.unavailable
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            try device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.unavailable }
        session.addOutput(videoOutput)
        if position == .back, session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        if position == .front || prefersFullFrameCard { preferNativeSelfieFormat(device) }
        if position == .back && highResolutionPhoto {
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)].compactMap({ $0 }) {
            Self.makeUpright(connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    /// Apply after attaching the input/output, inside the session configuration
    /// transaction. Explicit activeFormat requires inputPriority on iOS.
    private func preferNativeSelfieFormat(_ device: AVCaptureDevice) {
        let formats = device.formats
        let candidates = formats.map { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return SelfieFormatCandidate(width: Int(dimensions.width), height: Int(dimensions.height),
                supports30FPS: format.videoSupportedFrameRateRanges.contains {
                    SelfieFormatSelection.supports30FPS(minimum: $0.minFrameRate, maximum: $0.maxFrameRate)
                })
        }
        guard let index = SelfieFormatSelection.preferredIndex(in: candidates,
            inputPrioritySupported: session.canSetSessionPreset(.inputPriority)) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let priorMin = device.activeVideoMinFrameDuration
            let priorMax = device.activeVideoMaxFrameDuration
            let format = formats[index]
            func supports(_ duration: CMTime) -> Bool {
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return false }
                let fps = 1 / seconds
                return format.videoSupportedFrameRateRanges.contains { fps >= $0.minFrameRate && fps <= $0.maxFrameRate }
            }
            // activeFormat resets frame durations. Restore the previous cadence
            // where supported; only use 30fps when the new format requires it.
            let preserveCadence = supports(priorMin) && supports(priorMax)
            let minDuration = preserveCadence ? priorMin : CMTime(value: 1, timescale: 30)
            let maxDuration = preserveCadence ? priorMax : CMTime(value: 1, timescale: 30)
            session.sessionPreset = .inputPriority
            device.activeFormat = format
            if CMTimeCompare(minDuration, device.activeVideoMaxFrameDuration) > 0 {
                device.activeVideoMaxFrameDuration = maxDuration
                device.activeVideoMinFrameDuration = minDuration
            } else {
                device.activeVideoMinFrameDuration = minDuration
                device.activeVideoMaxFrameDuration = maxDuration
            }
        } catch {
            // A device that cannot be configured keeps its existing session preset.
        }
    }

    static func makeUpright(_ connection: AVCaptureConnection) {
        if #available(iOS 17, *) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), let handler = lock.withLock({ frameHandler }) else { return }
        handler(CameraFrame(image: CIImage(cvPixelBuffer: buffer)))
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<CameraFrame, Error>? in
            defer { photoContinuation = nil }
            return photoContinuation
        }
        guard let continuation else { return }
        // The photo's pixels are not rotated; its orientation is metadata.
        if let data = photo.fileDataRepresentation(), let image = CIImage(data: data, options: [.applyOrientationProperty: true]) {
            continuation.resume(returning: CameraFrame(image: image))
        } else {
            continuation.resume(throwing: error ?? CameraError.captureFailed)
        }
    }
}
#endif
