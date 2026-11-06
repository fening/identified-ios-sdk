import IdentifiedCore

enum StepLabel {
    /// "Step 2 of 5", as the web's progress header reads.
    static func text(_ position: StepPosition) -> String {
        L10n.format("flow.step", position.step, position.total)
    }
}
