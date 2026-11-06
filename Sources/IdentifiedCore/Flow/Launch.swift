import Foundation

package enum LaunchFailure: Error, Equatable, Sendable {
    /// The token is unknown or does not match its case. Ends the flow.
    case sessionInvalid
    /// The token has expired. Ends the flow.
    case sessionExpired
    /// Anything else. The entry screen offers a retry.
    case unavailable(String)
}

package struct LaunchState: Equatable, Sendable {
    package var session: HostedSession
    package var route: LaunchRoute
    package var mode: NavigationMode
}

package enum Launch {
    package static func load(using client: APIClient) async -> Result<LaunchState, LaunchFailure> {
        do {
            let session = try await client.currentSession()
            let mode = FlowRouting.navigationMode(launchHadCase: session.caseId != nil, caseStatus: session.caseStatus)
            return .success(LaunchState(session: session, route: FlowRouting.launchRoute(session), mode: mode))
        } catch {
            return .failure(failure(for: error))
        }
    }

    package static func failure(for error: Error) -> LaunchFailure {
        guard let apiError = error as? APIError else { return .unavailable(error.localizedDescription) }
        switch apiError.sessionFailure {
        case .expired: return .sessionExpired
        case .invalid: return .sessionInvalid
        case nil: break
        }
        if case .http(404, _) = apiError { return .sessionInvalid }
        return .unavailable(apiError.message)
    }
}
