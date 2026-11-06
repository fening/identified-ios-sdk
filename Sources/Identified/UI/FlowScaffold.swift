#if os(iOS)
import IdentifiedCore
import SwiftUI
import UIKit

/// `FlowShell.tsx`: the lockup, the step bar for numbered screens, a title and
/// subtitle, scrolling content, and a footer pinned above the home indicator.
struct FlowScaffold<Content: View, Footer: View>: View {
    var title: String?
    var subtitle: String?
    /// The numbered screen this is, for "Step N of M". Nil hides the bar.
    var step: FlowScreen?
    var compactTitle = false
    /// Consent hides the lockup, as the web's does.
    var showsLockup = true
    /// False hides the footer bar when a screen has nothing to put in it.
    var showsFooter = true
    var onBack: (() -> Void)?
    var allowsBack = true
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    private var hasFooter = true

    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme

    init(title: String? = nil, subtitle: String? = nil, step: FlowScreen? = nil, compactTitle: Bool = false,
         showsLockup: Bool = true, showsFooter: Bool = true, onBack: (() -> Void)? = nil, allowsBack: Bool = true,
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.step = step
        self.compactTitle = compactTitle
        self.showsLockup = showsLockup
        self.showsFooter = showsFooter
        self.onBack = onBack
        self.allowsBack = allowsBack
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(showsLockup: showsLockup, allowsBack: allowsBack, onBack: onBack)
            if let position {
                StepBar(position: position).padding(.horizontal, 20).padding(.top, 8)
            }
            // Content flows from the top at its natural height and scrolls when it exceeds
            // the viewport. It is never stretched to the viewport or centred in it.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let title {
                        Text(title)
                            .font(theme.heading(compactTitle ? 22 : 30)).tracking(-0.5)
                            .foregroundStyle(theme.palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let subtitle {
                        BodyText(subtitle, secondary: true).lineSpacing(4).padding(.top, 10)
                    }
                    content().padding(.top, title == nil && subtitle == nil ? 0 : (compactTitle ? 16 : 28))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, compactTitle ? 16 : 28)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            if hasFooter && showsFooter {
                VStack(spacing: 10, content: footer)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(.ultraThinMaterial)
                    .background(theme.palette.background.opacity(0.85))
                    .overlay(alignment: .top) { theme.palette.border.frame(height: 1) }
                    .accessibilityIdentifier("identified.flow.footer")
            }
        }
        .background(theme.palette.background.ignoresSafeArea())
    }

    private var position: StepPosition? {
        guard let step, let session = flow.session else { return nil }
        return FlowRules.position(of: step, requiredDocuments: session.requiredDocuments, collectName: FlowRules.collectsName(session))
    }
}

extension FlowScaffold where Footer == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, step: FlowScreen? = nil, compactTitle: Bool = false, allowsBack: Bool = true, onBack: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, step: step, compactTitle: compactTitle, onBack: onBack, allowsBack: allowsBack, content: content, footer: { EmptyView() })
        hasFooter = false
    }
}

/// Raw SPM PNGs are decoded by URL rather than looked up as image-catalog
/// names. Retain the original colours inside the header's foreground style.
@MainActor
enum BrandMarkAsset {
    static let image: UIImage? = {
        guard let url = Bundle.module.url(forResource: "brand-mark", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysOriginal)
    }()
}

/// The shell owns the native hit areas; its glyphs retain the web dimensions.
struct FlowHeader: View {
    var showsLockup = true
    var allowsBack = true
    var onBack: (() -> Void)?
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme

    private var canGoBack: Bool {
        allowsBack && (onBack != nil || flow.path.last?.showsBack == true)
    }

    var body: some View {
        HStack(spacing: 0) {
            if canGoBack {
                Button {
                    if let onBack { onBack() } else if !flow.path.isEmpty { flow.path.removeLast() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.string("camera.back"))
                .padding(.leading, -12)
            }
            if showsLockup && theme.appearance.showsLockup {
                HStack(spacing: 6) {
                    if let mark = BrandMarkAsset.image {
                        Image(uiImage: mark).renderingMode(.original)
                            .resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                    Text(verbatim: "identified.cc").font(theme.heading(13)).tracking(-0.2)
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Button { flow.close() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.string("flow.close"))
            .padding(.trailing, -12)
        }
        // Keep the web's 24pt header line. The un-clipped 44pt button
        // labels extend 10pt above/below it for native touch targets.
        .frame(height: 24)
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.textSecondary)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("identified.flow.header")
    }
}

private struct StepBar: View {
    let position: StepPosition
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let count = max(position.total, 1)
                let width = max(0, (geometry.size.width - CGFloat(count - 1) * 6) / CGFloat(count))
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule().fill(theme.palette.border)
                            .overlay(alignment: .leading) {
                                if index < position.step {
                                    LinearGradient(colors: [theme.palette.accent, theme.progressEnd], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: geometry.size.width)
                                        .offset(x: -CGFloat(index) * (width + 6))
                                }
                            }
                            .frame(width: width, height: 6)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(height: 6)
            Text(StepLabel.text(position).uppercased())
                .font(theme.body(11, weight: .medium)).tracking(1.3)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StepLabel.text(position))
    }
}
#endif
