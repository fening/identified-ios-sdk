#if os(iOS)
import SwiftUI

struct IdentityHero: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(theme.coralHalo)
                .frame(width: 104, height: 104)
            RoundedRectangle(cornerRadius: 28).fill(theme.palette.accent)
                .frame(width: 88, height: 88)
                .shadow(color: theme.palette.accent.opacity(0.2), radius: 10, x: 0, y: 7)
            // SVG strokes scale with its 24-unit viewBox into the 42pt art.
            ShieldCheck().stroke(.white, style: StrokeStyle(lineWidth: 1.6 * 42 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 42, height: 42)
            ShieldCheck(drawsCheck: true).stroke(.white, style: StrokeStyle(lineWidth: 1.7 * 42 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 42, height: 42)
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
    }
}

private struct ShieldCheck: Shape {
    var drawsCheck = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if drawsCheck {
            p.move(to: CGPoint(x: 9, y: 11.8))
            p.addLine(to: CGPoint(x: 11.1, y: 13.9))
            p.addLine(to: CGPoint(x: 15, y: 10))
        } else {
            p.move(to: CGPoint(x: 12, y: 2.5))
            p.addLine(to: CGPoint(x: 4, y: 5.5)); p.addLine(to: CGPoint(x: 4, y: 10.9))
            p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 4, y: 15.5), control2: CGPoint(x: 7.1, y: 19.8))
            p.addCurve(to: CGPoint(x: 20, y: 10.9), control1: CGPoint(x: 16.9, y: 19.8), control2: CGPoint(x: 20, y: 15.5))
            p.addLine(to: CGPoint(x: 20, y: 5.5)); p.closeSubpath()
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

/// The same card/page/face comparison subjects as ProcessingScan.tsx.
struct ProcessingArt: View {
    enum Variant { case document, page, faceMatch }
    var variant: Variant
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanning = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 220, geometry.size.height / 150)
            ZStack {
                ScanOutline(variant: variant).stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if !reduceMotion {
                    Rectangle()
                        .fill(LinearGradient(colors: [theme.palette.accent.opacity(0), theme.palette.accent.opacity(0.28)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 30)
                        .overlay(alignment: .bottom) { Rectangle().frame(height: 2) }
                        .offset(y: scanning ? 58 : -58)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: 220, height: 150)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) { scanning = true }
            }
        }
    }
}

private struct ScanOutline: Shape {
    let variant: ProcessingArt.Variant
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ x: CGFloat, _ y: CGFloat, _ end: CGFloat) {
            p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: end, y: y))
        }
        func portrait(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            p.move(to: CGPoint(x: x - radius * 1.35, y: y + radius * 2.2))
            p.addCurve(to: CGPoint(x: x + radius * 1.35, y: y + radius * 2.2),
                       control1: CGPoint(x: x - radius * 1.35, y: y + radius * 0.8),
                       control2: CGPoint(x: x + radius * 1.35, y: y + radius * 0.8))
        }
        switch variant {
        case .document:
            p.addRoundedRect(in: CGRect(x: 14, y: 16, width: 192, height: 118), cornerSize: CGSize(width: 12, height: 12))
            portrait(66, 66, 18)
            line(112, 56, 186); line(112, 74, 170); line(112, 98, 132); line(140, 98, 156); line(164, 98, 186)
        case .page:
            p.addRoundedRect(in: CGRect(x: 52, y: 10, width: 116, height: 130), cornerSize: CGSize(width: 8, height: 8))
            for (y, end) in [(40, 148), (60, 148), (80, 130), (100, 136), (120, 112)] {
                line(72, CGFloat(y), CGFloat(end))
            }
        case .faceMatch:
            p.addEllipse(in: CGRect(x: 28, y: 41, width: 68, height: 68))
            portrait(62, 64, 12); line(104, 75, 116); line(124, 75, 136)
            p.addRoundedRect(in: CGRect(x: 144, y: 44, width: 62, height: 62), cornerSize: CGSize(width: 10, height: 10))
            portrait(164, 66, 8); line(184, 62, 198); line(184, 74, 194)
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 220, y: rect.height / 150))
    }
}
#endif
