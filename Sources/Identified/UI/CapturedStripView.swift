#if os(iOS)
import SwiftUI
import UIKit

/// CapturedStrip.tsx: accepted local evidence only; never fetches remote URLs.
struct CapturedStripView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme

    var body: some View {
        if !flow.capturedItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("captured.title"))
                    .font(theme.body(12, weight: .medium))
                    .foregroundStyle(theme.palette.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(flow.capturedItems) { item in tile(item) }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { theme.palette.border.frame(height: 1) }
            .accessibilityIdentifier("identified.captured.strip")
        }
    }

    private func tile(_ item: AcceptedCapture) -> some View {
        let label = DocLabel.text(item.docType)
        return VStack(spacing: 4) {
            ZStack {
                theme.warmSurface
                if let data = item.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 96, height: 64)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: item.isPDF ? "doc" : "photo")
                            .font(.system(size: 22, weight: .regular))
                        if item.isPDF { Text(verbatim: "PDF").font(theme.body(10, weight: .semibold)).tracking(0.5) }
                    }
                    .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(width: 96, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.border, lineWidth: 1))
            .accessibilityLabel(item.isPDF ? L10n.format("captured.pdf", label) : label)
            .accessibilityAddTraits(.isImage)
            Text(label).font(theme.body(11)).foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1).frame(width: 96).multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
    }
}
#endif
