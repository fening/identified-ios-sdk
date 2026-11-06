import Identified
import SwiftUI

@main
struct IdentifiedExampleApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Paste a session token your backend created with `POST /api/v1/sessions`.
/// Never put an API key in an app.
///
/// For automated runs, launch arguments fill the form and start the flow:
/// `-IdentifiedExampleBaseURL <url> -IdentifiedExampleToken <token> -IdentifiedExampleAutostart YES`,
/// plus `-IdentifiedFixtureCamera YES` in debug builds to replay generated
/// camera scenes on a simulator.
struct ContentView: View {
    // Remembered between launches, so the app works when opened from the home
    // screen. Launch arguments of the same name override them for one launch
    // and are saved on appear.
    @AppStorage("IdentifiedExampleBaseURL") private var baseURL = IdentifiedConfiguration.productionBaseURL.absoluteString
    @AppStorage("IdentifiedExampleToken") private var token = ""
    @State private var verifying = false
    @State private var lastResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Session token", text: $token, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Session token")
                } footer: {
                    Text("Create one on your backend with POST /api/v1/sessions and paste its session_token here.")
                }
                Section {
                    Button("Start verification") { verifying = true }
                        .disabled(configuration == nil)
                }
                if let lastResult {
                    Section("Last result") { Text(lastResult).font(.footnote.monospaced()) }
                }
            }
            .navigationTitle("Identified example")
        }
        .identifiedVerification(isPresented: $verifying, configuration: configuration ?? IdentifiedConfiguration(sessionToken: "")) { result in
            lastResult = String(describing: result)
        }
        .onAppear {
            for key in ["IdentifiedExampleBaseURL", "IdentifiedExampleToken"] {
                if let value = UserDefaults.standard.string(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
            }
            if UserDefaults.standard.bool(forKey: "IdentifiedExampleAutostart"), configuration != nil { verifying = true }
        }
    }

    private var configuration: IdentifiedConfiguration? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        var appearance = Appearance()
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "IdentifiedExampleAppearance") {
        case "light": appearance.colorScheme = .light
        case "dark": appearance.colorScheme = .dark
        default: break
        }
        #endif
        return IdentifiedConfiguration(sessionToken: trimmed, baseURL: url, appearance: appearance)
    }
}
