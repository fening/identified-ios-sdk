import Testing
@testable import Identified

@Test func aMissingCameraUsageStringFailsTheFlowUpFront() {
    #expect(Identified.configurationProblem(info: [:]) == .unexpected("Info.plist is missing NSCameraUsageDescription"))
    #expect(Identified.configurationProblem(info: nil) == .unexpected("Info.plist is missing NSCameraUsageDescription"))
    #expect(Identified.configurationProblem(info: ["NSCameraUsageDescription": "To photograph your ID"]) == nil)
}
