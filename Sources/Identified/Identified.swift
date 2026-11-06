import Foundation

/// The Identified verification flow.
///
/// ```swift
/// Identified.start(IdentifiedConfiguration(sessionToken: token), from: viewController) { result in
///     // Restore your UI. Decide on the verification from the webhook or
///     // GET /api/v1/cases/:id on your backend, not from this result.
/// }
/// ```
public enum Identified {
    /// Without the usage string iOS terminates the app the moment the camera
    /// is touched; failing the flow says why instead.
    static func configurationProblem(info: [String: Any]? = Bundle.main.infoDictionary) -> IdentifiedError? {
        info?["NSCameraUsageDescription"] == nil ? .unexpected("Info.plist is missing NSCameraUsageDescription") : nil
    }
}
