import Foundation
import Testing
@testable import IdentifiedCore
import IdentifiedTestSupport

private func osu() -> [String: Any] { ["code": "GA1839124", "latitude": 5.556, "longitude": -0.182, "area": "Osu", "district": "Accra Metropolitan", "region": "Greater Accra"] }

@Test func resolvesATypedCode() async throws {
    let transport = StubTransport(.data(osu()))
    let address = try await client(transport).resolveDigitalAddress(code: "GA-183-9124")
    let url = try #require(transport.lastRequest?.url)
    #expect(address.area == "Osu")
    #expect(url.path == "/api/v1/addresses/ghanapost/resolve")
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "code", value: "GA-183-9124")])
}

@Test func encodesACoordinate() async throws {
    let transport = StubTransport(.data(osu()))
    _ = try await client(transport).encodeDigitalAddress(latitude: 5.556, longitude: -0.182)
    let url = try #require(transport.lastRequest?.url)
    #expect(url.path == "/api/v1/addresses/ghanapost/encode")
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
        URLQueryItem(name: "lat", value: "5.556"),
        URLQueryItem(name: "lng", value: "-0.182"),
    ])
}

@Test func reportsALookupOutage() async {
    let transport = StubTransport(.error(503, "address lookup unavailable"))
    await #expect(throws: APIError.http(status: 503, message: "address lookup unavailable")) {
        try await client(transport).resolveDigitalAddress(code: "GA-183-9124")
    }
}
