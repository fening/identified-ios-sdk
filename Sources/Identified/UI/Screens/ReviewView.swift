#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `Review.tsx`.
struct ReviewView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @State private var optIn = false
    @State private var email = ""
    @State private var loaded = false
    @State private var submitting = false
    @State private var error: String?
    @State private var submitTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if submitting {
                ProcessingView(
                    messages: [
                        L10n.string("review.processing.scanning"), L10n.string("review.processing.checking"),
                        L10n.string("review.processing.running"), L10n.string("review.processing.almost"),
                    ],
                    detail: L10n.string("review.processing.detail"), step: .review
                )
                .navigationBarBackButtonHidden(true)
            } else {
                FlowScaffold(title: L10n.string("review.title"), subtitle: L10n.string("review.subtitle"), step: .review) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let session = flow.session, let current = flow.verificationCase, loaded {
                            VStack(spacing: 0) {
                                ForEach(items(session, current), id: \.key) { item in row(item) }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius))
                            .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.palette.border, lineWidth: 1))
                            CapturedStripView().padding(.top, 2)
                            emailChoice
                        } else if let error, !loaded {
                            ErrorText(message: error)
                        } else {
                            LoadingView(text: L10n.string("review.loading"), showsHeader: false).frame(height: 140)
                        }
                        if loaded, let error { ErrorText(message: error) }
                    }
                } footer: {
                    PrimaryButton(title: L10n.string("review.submit"), enabled: loaded && allCaptured) {
                        submitTask = Task { await submit() }
                    }
                }
                .task { await load() }
            }
        }
        .onDisappear { submitTask?.cancel() }
    }

    private func items(_ session: HostedSession, _ current: VerificationCase) -> [ChecklistItem] {
        FlowRules.checklist(current, requiredDocuments: FlowRules.orderedCaptureSteps(session.requiredDocuments))
    }

    private var allCaptured: Bool {
        guard let session = flow.session, let current = flow.verificationCase else { return false }
        return items(session, current).allSatisfy(\.complete)
    }

    private func row(_ item: ChecklistItem) -> some View {
        HStack {
            Text(DocLabel.text(item.key)).font(theme.body(16, weight: .medium)).foregroundStyle(theme.palette.textPrimary)
            Spacer()
            Label(item.complete ? L10n.string("review.captured") : L10n.string("review.missing"),
                  systemImage: item.complete ? "checkmark" : "exclamationmark.circle")
                .font(theme.body(14, weight: .medium))
                .foregroundStyle(item.complete ? theme.palette.success : theme.palette.error)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { theme.palette.border.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private var emailChoice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $optIn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("review.email.opt_in")).font(theme.body(15, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                    BodyText(L10n.string("review.email.detail"), secondary: true, size: 13).lineSpacing(3)
                }
            }
            .toggleStyle(InlineAgreementStyle())
            .onChange(of: optIn) { _ in error = nil }
            if optIn {
                TextField(L10n.string("review.email.placeholder"), text: $email)
                    .font(theme.body(15))
                    .foregroundStyle(theme.palette.textPrimary)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(theme.palette.background, in: RoundedRectangle(cornerRadius: theme.radius * 0.75))
                    .overlay(RoundedRectangle(cornerRadius: theme.radius * 0.75).stroke(theme.palette.border, lineWidth: 1))
                    .accessibilityLabel(L10n.string("review.email.label"))
                BodyText(L10n.string("review.email.note"), secondary: true, size: 12).lineSpacing(3)
            }
        }
        .padding(16)
        .background(theme.lilacSurface, in: RoundedRectangle(cornerRadius: theme.radius))
        .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.lilacBorder, lineWidth: 1))
        .padding(.top, 22)
    }

    private func load() async {
        if !loaded {
            optIn = flow.session?.reportEmailOptIn ?? false
            email = flow.session?.reportEmail ?? ""
        }
        do {
            try await flow.loadCase()
            loaded = true
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("review.load_error")
        }
    }

    private func submit() async {
        error = nil
        if optIn && !ReviewInput.isValidEmail(email) {
            error = L10n.string("review.email.invalid")
            return
        }
        submitting = true
        do {
            try await flow.submit(reportOptIn: optIn, email: email)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            submitting = false
            self.error = flow.message(for: error) ?? L10n.string("review.error")
        }
    }
}
#endif
