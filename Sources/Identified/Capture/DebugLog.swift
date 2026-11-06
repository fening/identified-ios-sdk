#if DEBUG
import Foundation

/// Debug builds only. Appends to `tmp/identified-yaw.log` in the host app's
/// container: the client's yaw for each captured selfie pose, to compare with
/// the yaw the face service measures on the same frame when tuning
/// `TurnChallenge.side`, and the selfie screen's steps, to see on a device
/// where a capture stops short of the upload. A file rather than the console:
/// a device's stdout is only visible with a debugger or console attached.
enum DebugLog {
    static let url = FileManager.default.temporaryDirectory.appendingPathComponent("identified-yaw.log")

    static func yaw(role: String, yaw: Double) {
        append("\(role) \(String(format: "%.3f", yaw))")
    }

    static func event(_ text: String) {
        append("event \(text)")
    }

    private static func append(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
#endif
