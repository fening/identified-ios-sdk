#if os(iOS)
import SwiftUI
import UIKit

extension Identified {
    /// Presents the flow full screen over `presenter` and calls `completion`
    /// once, after the flow has been dismissed.
    @MainActor
    public static func start(
        _ configuration: IdentifiedConfiguration,
        from presenter: UIViewController,
        completion: @escaping @MainActor (IdentifiedResult) -> Void
    ) {
        if let problem = configurationProblem() {
            completion(.failed(problem))
            return
        }
        weak var presented: UIViewController?
        let host = UIHostingController(rootView: IdentifiedFlow(configuration: configuration) { result in
            if let presented {
                presented.dismiss(animated: true) { completion(result) }
            } else {
                completion(result)
            }
        })
        host.modalPresentationStyle = .fullScreen
        presented = host
        presenter.present(host, animated: true)
    }
}

extension View {
    /// Presents the flow full screen while `isPresented` is true. When it
    /// ends, `isPresented` goes false and `onCompletion` is called.
    public func identifiedVerification(
        isPresented: Binding<Bool>,
        configuration: IdentifiedConfiguration,
        onCompletion: @escaping @MainActor (IdentifiedResult) -> Void
    ) -> some View {
        modifier(IdentifiedVerification(isPresented: isPresented, configuration: configuration, onCompletion: onCompletion))
    }
}

private struct IdentifiedVerification: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: IdentifiedConfiguration
    let onCompletion: @MainActor (IdentifiedResult) -> Void
    @State private var result: IdentifiedResult?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(
                get: { isPresented && Identified.configurationProblem() == nil },
                set: { isPresented = $0 }
            ), onDismiss: {
                onCompletion(result ?? .cancelled)
                result = nil
            }) {
                IdentifiedFlow(configuration: configuration) { finished in
                    result = finished
                    isPresented = false
                }
            }
            .onAppear { validatePresentation() }
            .onChange(of: isPresented) { presented in
                if presented { validatePresentation() }
            }
    }

    private func validatePresentation() {
        if isPresented, let problem = Identified.configurationProblem() {
            isPresented = false
            onCompletion(.failed(problem))
        }
    }
}
#endif
