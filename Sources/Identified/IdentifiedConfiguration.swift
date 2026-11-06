import Foundation

/// What the host app hands the SDK to start a verification.
///
/// `sessionToken` is the `session_token` your backend received from
/// `POST /api/v1/sessions`. Never put your API key in the app. Test versus live
/// is decided by the key that created the session, so there is no environment
/// switch here. `appearance` themes the flow to match your app.
public struct IdentifiedConfiguration: Sendable {
    public static let productionBaseURL = URL(string: "https://api.identified.cc")!

    public var sessionToken: String
    public var baseURL: URL
    public var appearance: Appearance

    public init(sessionToken: String, baseURL: URL = IdentifiedConfiguration.productionBaseURL, appearance: Appearance = Appearance()) {
        self.sessionToken = sessionToken
        self.baseURL = baseURL
        self.appearance = appearance
    }
}

