#if os(iOS)
import IdentifiedCore
import SwiftUI

/// The flow for one configuration, delivering its result once.
struct IdentifiedFlow: View {
    let configuration: IdentifiedConfiguration
    let onFinish: @MainActor (IdentifiedResult) -> Void

    var body: some View {
        FlowView(
            model: FlowModel(client: APIClient(baseURL: configuration.baseURL, sessionToken: configuration.sessionToken), onFinish: onFinish),
            appearance: configuration.appearance,
            capture: .current
        )
    }
}
#endif
