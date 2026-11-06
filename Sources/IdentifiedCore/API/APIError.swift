import Foundation

package enum APIError: Error, Equatable, Sendable {
    /// A non-2xx response. `message` is the server's `{"error": ...}` text.
    case http(status: Int, message: String)
    /// A 422 refusal of a proof of address. `exhausted` means no more attempts.
    case documentRefused(message: String, exhausted: Bool)
    /// The request never got an HTTP response.
    case transport(String)
    /// A 2xx response the client could not decode.
    case decoding(String)

    package var message: String {
        switch self {
        case let .http(_, message), let .documentRefused(message, _), let .transport(message), let .decoding(message):
            return message
        }
    }

    /// Whether this error means the session token is no longer usable, which
    /// ends the flow instead of offering a retry. `middleware/sessiontoken.go`
    /// answers 401 with "missing session token", "invalid session token" or
    /// "session expired".
    package var sessionFailure: SessionFailure? {
        guard case let .http(401, message) = self else { return nil }
        return message.localizedCaseInsensitiveContains("expired") ? .expired : .invalid
    }
}

package enum SessionFailure: Equatable, Sendable {
    case invalid
    case expired
}
