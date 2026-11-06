#if os(iOS)
import IdentifiedCore
import SwiftUI

/// The web's primary button: accent fill, 54 pt, half opacity when disabled.
struct PrimaryButton: View {
    let title: String
    var busyTitle: String?
    var busy = false
    var enabled = true
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(theme.palette.onAccent) }
                Text(busy ? busyTitle ?? title : title)
            }
            .font(theme.body(17, weight: .semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .foregroundStyle(theme.palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(theme.palette.accent, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .shadow(color: theme.palette.accent.opacity(enabled ? 0.2 : 0), radius: 10, x: 0, y: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrimaryPressStyle())
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// An outlined button for the second choice on a screen.
struct SecondaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.body(17, weight: .semibold))
                .foregroundStyle(theme.palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(theme.palette.border, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// A text-only action, for links such as "Change" or "Learn more".
struct LinkButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(title, action: action)
            .font(theme.body(15, weight: .semibold))
            .foregroundStyle(theme.palette.accent)
            .buttonStyle(.plain)
    }
}

struct ErrorText: View {
    let message: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(message)
            .font(theme.body(15))
            .foregroundStyle(theme.palette.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct BodyText: View {
    let text: String
    var secondary = false
    var size: CGFloat = 16
    @Environment(\.theme) private var theme

    init(_ text: String, secondary: Bool = false, size: CGFloat = 16) {
        self.text = text
        self.secondary = secondary
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(theme.body(size))
            .foregroundStyle(secondary ? theme.palette.textSecondary : theme.palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A bordered surface, as the web's cards are.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(theme.palette.border, lineWidth: 1))
    }
}

/// A labelled field on the web's surface.
struct FieldBox<Field: View>: View {
    let label: String
    var isFilled = true
    @ViewBuilder let field: () -> Field
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    private var floating: Bool { isFilled || focused }

    var body: some View {
        field()
            .focused($focused)
            .font(theme.body(18))
            .foregroundStyle(theme.palette.textPrimary)
            .accessibilityLabel(label)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(minHeight: 64)
            .background(theme.palette.background, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
                // Web: 1pt accent border plus a 2pt outward accent ring.
                .inset(by: focused ? -1 : 0)
                .stroke(focused ? theme.palette.accent : theme.palette.border, lineWidth: focused ? 3 : 1))
            .overlay(alignment: floating ? .topLeading : .leading) {
                Text(label)
                    .font(theme.body(floating ? 13 : 18, weight: floating ? .medium : .regular))
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.horizontal, floating ? 6 : 0)
                    .background(theme.palette.background)
                    .padding(.leading, 16)
                    .offset(y: floating ? -9 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// A full-screen spinner with a line of text, as `LoadingBlock` on the web.
struct LoadingView: View {
    let text: String
    var showsHeader = true
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { FlowHeader() }
            VStack(spacing: 14) {
                ProgressView().tint(theme.palette.accent)
                Text(text).font(theme.body(15)).foregroundStyle(theme.palette.textSecondary)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
        .background(theme.palette.background.ignoresSafeArea())
    }
}

/// The web's `ProcessingScan` messages: one every three seconds, holding on
/// the last, with a detail line underneath.
struct ProcessingView: View {
    let messages: [String]
    let detail: String
    @State private var index = 0
    @Environment(\.theme) private var theme

    var variant: ProcessingArt.Variant = .document
    var step: FlowScreen? = nil

    var body: some View {
        FlowScaffold(step: step) {
            VStack(spacing: 0) {
                ProcessingArt(variant: variant)
                    .foregroundStyle(theme.palette.accent)
                    .frame(maxWidth: 240).frame(height: 164)
                    .padding(.bottom, 28)
                Text(messages.isEmpty ? detail : messages[min(index, messages.count - 1)])
                    .font(theme.body(19, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(detail).font(theme.body(15)).foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center).padding(.top, 6)
            }
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .task {
            while index < messages.count - 1 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                index += 1
            }
        }
    }
}

struct InlineAgreementStyle: ToggleStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { configuration.isOn.toggle() } label: {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(configuration.isOn ? theme.palette.accent : theme.palette.textSecondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(-12)
            .accessibilityLabel(L10n.string("review.email.opt_in"))
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
            configuration.label
        }
        .padding(.top, 2)
    }
}

private struct PrimaryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CaptureBriefView: View {
    let lead: String
    let points: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BodyText(lead, secondary: true).lineSpacing(4).padding(.horizontal, 4).padding(.bottom, 20)
            VStack(spacing: 12) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(theme.palette.accent).frame(width: 6, height: 6).padding(.top, 8)
                        BodyText(point, size: 15).lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.palette.border, lineWidth: 1))
                }
            }
        }
    }
}
#endif
