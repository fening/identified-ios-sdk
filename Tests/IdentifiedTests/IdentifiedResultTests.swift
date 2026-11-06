import Foundation
import Testing
@testable import Identified
import IdentifiedCore

@Test func defaultsToProduction() {
    let config = IdentifiedConfiguration(sessionToken: "tok")
    #expect(config.baseURL.absoluteString == "https://api.identified.cc")
}

@Test func mapsLaunchFailuresThatEndTheFlow() {
    #expect(IdentifiedError(launchFailure: .sessionInvalid) == .sessionInvalid)
    #expect(IdentifiedError(launchFailure: .sessionExpired) == .sessionExpired)
    #expect(IdentifiedError(launchFailure: .unavailable("offline")) == nil)
}

@Test func mapsMidFlowSessionFailures() {
    #expect(IdentifiedError(apiError: APIError.http(status: 401, message: "session expired")) == .sessionExpired)
    #expect(IdentifiedError(apiError: APIError.http(status: 401, message: "invalid session token")) == .sessionInvalid)
    #expect(IdentifiedError(apiError: APIError.http(status: 500, message: "boom")) == nil)
}

@Test func resultsCompareByValue() {
    #expect(IdentifiedResult.completed(caseId: "c", status: "approved") == .completed(caseId: "c", status: "approved"))
    #expect(IdentifiedResult.failed(.noCamera) != .cancelled)
}
