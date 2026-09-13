import SwiftUI

extension Color {
    static let ink = Color(white: 0.08)
    static let paper = Color.white
    static let paperInset = Color(white: 0.965)
}

/// One static, decorative texture. No timers, procedural noise, or hit testing.
struct PaperSurface: View {
    @AppStorage("paperTextureEnabled") private var texture = true
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Color.paper.overlay {
            if texture && contrast != .increased && !reduceTransparency {
                GeometryReader { geometry in
                    Image("PaperTexture").resizable().scaledToFill().saturation(0)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.46)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct DaylineMark: View {
    var body: some View {
        Canvas { context, size in
            // Draw both strokes in one centered coordinate system. Padding a Circle
            // beside an absolute Path gave the ring and check different size proposals.
            let scale = min(size.width, size.height) / 480
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                // Match make_icon.swift's mark, including its upward-positive Y axis.
                CGPoint(x: center.x + (x - 512) * scale,
                        y: center.y + (512 - y) * scale)
            }
            var ring = Path()
            ring.addArc(center: center, radius: 215 * scale,
                        startAngle: .degrees(-17), endAngle: .degrees(284), clockwise: false)
            context.stroke(ring, with: .color(.ink),
                           style: StrokeStyle(lineWidth: 22 * scale, lineCap: .round))
            var check = Path()
            check.move(to: point(419, 518))
            check.addLine(to: point(496, 438))
            check.addLine(to: point(664, 625))
            context.stroke(check, with: .color(.ink),
                           style: StrokeStyle(lineWidth: 37 * scale, lineCap: .round, lineJoin: .round))
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: minimumTarget, minHeight: minimumTarget)
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
            // Immediate press feedback, including with Reduce Motion; never defer to release.
    }
    private var minimumTarget: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }
}
extension ButtonStyle where Self == InkButtonStyle { static var ink: InkButtonStyle { InkButtonStyle() } }

extension View {
    func paperSurface() -> some View { scrollContentBackground(.hidden).background { PaperSurface() } }
    func daylineTheme() -> some View {
        tint(Color.ink).accentColor(Color.ink).preferredColorScheme(.light).environment(\.colorScheme, .light)
    }
    func iconTarget() -> some View {
        #if os(iOS)
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        #else
        frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
        #endif
    }
}
