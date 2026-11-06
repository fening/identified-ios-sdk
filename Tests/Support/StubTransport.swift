import Foundation
import IdentifiedCore

/// Replays canned responses in order and records every request.
package final class StubTransport: HTTPTransport, @unchecked Sendable {
    package struct Reply {
        package var status: Int
        package var body: Data

        package init(status: Int, body: Data) {
            self.status = status
            self.body = body
        }

        package static func json(_ status: Int, _ object: Any) -> Reply { Reply(status: status, body: Fixtures.data(object)) }
        package static func data(_ object: Any) -> Reply { json(200, ["data": object]) }
        package static func error(_ status: Int, _ message: String) -> Reply { json(status, ["error": message]) }
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [URLRequest] = []
    package var failure: URLError?

    package init(_ replies: Reply...) {
        self.replies = replies
    }

    package func enqueue(_ more: [Reply]) {
        lock.withLock { replies.append(contentsOf: more) }
    }

    package var requests: [URLRequest] { lock.withLock { recorded } }
    package var lastRequest: URLRequest? { requests.last }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock {
            recorded.append(request)
            if let failure { throw failure }
            let reply = replies.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (reply.body, response)
        }
    }
}

extension URLRequest {
    package var bodyString: String { String(decoding: httpBody ?? Data(), as: UTF8.self) }
}

package func client(_ transport: StubTransport) -> APIClient {
    APIClient(baseURL: URL(string: "https://api.test")!, sessionToken: "tok_123", transport: transport)
}
