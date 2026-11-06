import Foundation
import IdentifiedCore

/// How the verification flow ended.
///
/// Use this only to restore your app's UI. The decision on a verification comes
/// from the signed webhook or `GET /api/v1/cases/:id` on your backend.
public enum IdentifiedResult: Equatable, Sendable {
    /// The subject submitted (or had already submitted) and closed the status
    /// screen. `status` is the last case status the SDK saw.
    case completed(caseId: String, status: String)
    /// The subject closed the flow before submitting.
    case cancelled
    /// Something the subject cannot fix inside the flow.
    case failed(IdentifiedError)
}

public enum IdentifiedError: Error, Equatable, Sendable {
    /// The session token is unknown or no longer matches its case.
    case sessionInvalid
    /// The session token has expired. Create a new session.
    case sessionExpired
    /// The device has no camera a required step needs.
    case noCamera
    /// Anything else that ended the flow.
    case unexpected(String)
}

extension IdentifiedError {
    /// The launch failures that end the flow. `unavailable` is retried inside it.
    init?(launchFailure: LaunchFailure) {
        switch launchFailure {
        case .sessionInvalid: self = .sessionInvalid
        case .sessionExpired: self = .sessionExpired
        case .unavailable: return nil
        }
    }

    /// A 401 on any call after launch ends the flow; other errors do not.
    init?(apiError: APIError) {
        switch apiError.sessionFailure {
        case .invalid: self = .sessionInvalid
        case .expired: self = .sessionExpired
        case nil: return nil
        }
    }
}
