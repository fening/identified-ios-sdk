import Foundation

/// The seam between the API client and the network, so tests replay canned
/// responses instead of starting a server.
package protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

package struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// An ephemeral session: responses carry personal data and signed document
    /// URLs, and nothing about the flow may be cached on disk.
    package init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
