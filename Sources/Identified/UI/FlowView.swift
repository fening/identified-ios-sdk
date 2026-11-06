#if os(iOS)
import IdentifiedCore
import SwiftUI
import UIKit

/// The whole flow: a navigation stack with Entry at its root, themed, with a
/// close button on every screen and a blank cover in the app switcher so ID
/// images do not appear in its snapshot.
struct FlowView: View {
    @StateObject private var flow: FlowModel
    let appearance: Appearance
    let capture: CaptureEnvironment
    @State private var obscured = false

    init(model: @autoclosure @escaping () -> FlowModel, appearance: Appearance, capture: CaptureEnvironment) {
        _flow = StateObject(wrappedValue: model())
        self.appearance = appearance
        self.capture = capture
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            root
                .flowChrome()
                .navigationDestination(for: FlowRoute.self) { route in
                    screen(route).flowChrome()
                }
        }
        .environmentObject(flow)
        .environment(\.captureEnvironment, capture)
        .modifier(Themed(appearance: appearance))
        .overlay { if obscured { PrivacyCover() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in obscured = true }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in obscured = false }
        .task {
            if flow.stage == .loading { await flow.load() }
        }
        #if DEBUG
        .onChange(of: flow.path) { DebugLog.event("flow.path \($0)") }
        #endif
    }

    @ViewBuilder private var root: some View {
        switch flow.stage {
        case .loading:
            LoadingView(text: L10n.string("entry.checking"))
        case .unavailable:
            EntryUnavailableView { Task { await flow.load() } }
        case .ready:
            EntryView()
        }
    }

    @ViewBuilder private func screen(_ route: FlowRoute) -> some View {
        switch route {
        case .consent: ConsentView()
        case .checklist: ChecklistView()
        case .yourName: YourNameView()
        case .idDetails: IDDetailsView()
        case let .documents(startAt): DocumentsView(startAt: startAt)
        case .selfie: SelfieView()
        case .proofOfAddress: ProofOfAddressView()
        case .review: ReviewView()
        case .status: StatusView()
        }
    }
}

private struct FlowChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    func flowChrome() -> some View { modifier(FlowChrome()) }
}

private struct PrivacyCover: View {
    @Environment(\.theme) private var theme

    var body: some View {
        theme.palette.background.ignoresSafeArea()
    }
}
#endif
