import Foundation
import SwiftUI

enum CameraPosition: Sendable {
    case back, front
}

/// How camera screens get a frame source. Live builds use the device camera;
/// debug builds launched with `-IdentifiedFixtureCamera YES` replay generated
/// scenes, so the flow runs end to end on a simulator with no camera.
struct CaptureEnvironment: Sendable {
    /// Nil when the device has no camera at that position.
    let makeSource: @Sendable (CameraPosition) -> FrameSource?
    /// False for fixtures, which need no camera permission.
    let needsPermission: Bool

    static var current: CaptureEnvironment {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "IdentifiedFixtureCamera") { return .fixture }
        #endif
        return .live
    }

    static var live: CaptureEnvironment {
        #if os(iOS)
        CaptureEnvironment(makeSource: { position in
            CameraController.isAvailable(position) ? CameraController(position: position == .back ? .back : .front) : nil
        }, needsPermission: true)
        #else
        CaptureEnvironment(makeSource: { _ in nil }, needsPermission: true)
        #endif
    }

    #if DEBUG
    static var fixture: CaptureEnvironment {
        CaptureEnvironment(makeSource: { position in
            FixtureFrameSource(images: [position == .back ? FixtureScenes.card() : FixtureScenes.noFace()])
        }, needsPermission: false)
    }
    #endif
}

private struct CaptureEnvironmentKey: EnvironmentKey {
    static let defaultValue = CaptureEnvironment.live
}

extension EnvironmentValues {
    var captureEnvironment: CaptureEnvironment {
        get { self[CaptureEnvironmentKey.self] }
        set { self[CaptureEnvironmentKey.self] = newValue }
    }
}
