import Testing
@testable import IdentifiedCore

private let still = CardBounds(left: 30, top: 40, right: 290, bottom: 204)
private let moved = CardBounds(left: 45, top: 40, right: 305, bottom: 204)

private func assessment(ready: Bool, detected: Bool = true, bounds: CardBounds = still) -> CardAssessment {
    CardAssessment(
        detected: detected, ready: ready, bounds: bounds, edgeCoverage: 1, straightness: 0,
        interior: InteriorQuality(brightness: 150, glare: 0, sharpness: 20), hint: ready ? .capturing : .holdStillCloser
    )
}

private func run(_ gate: inout AutoCaptureGate, _ frames: [(CardAssessment, Double)]) -> [Double] {
    frames.compactMap { a, t in gate.observe(a, frameWidth: 320, frameHeight: 240, at: t) ? t : nil }
}

@Test func capturesAReadyCardAfterThreeQuartersOfASecondStill() {
    var gate = AutoCaptureGate()
    let fired = run(&gate, stride(from: 0.0, through: 1.2, by: 0.12).map { (assessment(ready: true), $0) })
    #expect(fired.count == 1)
    #expect(fired[0] >= 0.75 && fired[0] < 0.75 + 0.12 + 1e-9)
}

@Test func waitsFourSecondsForADetectedButImperfectCard() {
    var gate = AutoCaptureGate()
    let early = run(&gate, stride(from: 0.0, through: 3.9, by: 0.12).map { (assessment(ready: false), $0) })
    #expect(early.isEmpty)
    #expect(run(&gate, [(assessment(ready: false), 4.08)]) == [4.08])
}

@Test func movementRestartsTheClock() {
    var gate = AutoCaptureGate()
    #expect(run(&gate, [(assessment(ready: true), 0), (assessment(ready: true), 0.6), (assessment(ready: true, bounds: moved), 0.72)]).isEmpty)
    #expect(run(&gate, [(assessment(ready: true, bounds: moved), 1.2)]).isEmpty)
    #expect(run(&gate, [(assessment(ready: true, bounds: moved), 1.5)]) == [1.5])
}

@Test func losingTheCardRestartsTheClock() {
    var gate = AutoCaptureGate()
    #expect(run(&gate, [(assessment(ready: true), 0), (assessment(ready: false, detected: false), 0.5), (assessment(ready: true), 0.6), (assessment(ready: true), 1.0)]).isEmpty)
    #expect(run(&gate, [(assessment(ready: true), 1.4)]) == [1.4])
}

@Test func firesOnlyOnceUntilReset() {
    var gate = AutoCaptureGate()
    #expect(run(&gate, [(assessment(ready: true), 0), (assessment(ready: true), 1), (assessment(ready: true), 2)]) == [1])
    gate.reset()
    #expect(run(&gate, [(assessment(ready: true), 3), (assessment(ready: true), 4)]) == [4])
}
