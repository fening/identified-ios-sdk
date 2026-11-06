import Testing
@testable import Identified
import IdentifiedCore

@Test func framingProblemsComeBeforePoseInstructions() {
    #expect(SelfieHint.text(phase: .left, status: .far, yaw: 0) == "Come closer")
    #expect(SelfieHint.text(phase: .position, status: .lookStraight, yaw: 0.3) == "Look straight at the camera")
    #expect(SelfieHint.text(phase: .position, status: .hold, yaw: 0) == "Hold still — taking your photo…")
}

@Test func turnsAreEncouragedAsTheyProgress() {
    #expect(SelfieHint.text(phase: .left, status: .ok, yaw: 0) == "Slowly turn your head to the left")
    #expect(SelfieHint.text(phase: .left, status: .ok, yaw: -0.2) == "Good — keep turning left")
    #expect(SelfieHint.text(phase: .left, status: .ok, yaw: -0.5) == "Perfect — hold it there")
    #expect(SelfieHint.text(phase: .right, status: .ok, yaw: -0.4) == "Now turn your head to the right")
    #expect(SelfieHint.text(phase: .center, status: .ok, yaw: -0.4) == "Back to centre")
}
