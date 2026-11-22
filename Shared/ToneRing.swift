import SwiftUI
import WidgetKit

// Rings drawn the way the Heart Minutes app draws its round complication: a dark track, the colour building from light
// at 12 o'clock to deep at the tip along the stroke, a white dot at the tip, and past 100 % the new lap lying on top of
// the previous one. On tinted and clear faces the colour scale becomes the opacity of one accented colour.

/// One ring in the Heart Minutes style.
struct ToneRing: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    /// The colour at the start (12 o'clock).
    let light: Color
    /// The colour at the tip.
    let deep: Color
    /// Fraction of the goal; past 1 the ring goes round again.
    let fraction: Double
    let lineWidth: CGFloat
    /// How strong the ring is in one colour (neighbouring rings alternate).
    var emphasis = 1.0

    /// Pieces per lap: enough that the steps in colour can't be seen.
    private static let piecesPerLap = 160.0

    private var fullColor: Bool { renderingMode == .fullColor }

    /// The colour at `x` (0…1) of the whole way: light at the start, deep where you have reached. In one colour: a grey
    /// level that becomes the opacity through a luminance mask.
    private func tone(_ x: Double) -> Color {
        let t = min(max(x, 0), 1)
        return fullColor ? light.mix(with: deep, by: t) : Color(white: 0.22 + 0.78 * t)
    }

    var body: some View {
        let f = max(fraction, 0)
        // Where on the current lap the tip is, also after the 2nd, 3rd … lap.
        let laps = f > 1 ? (f - 0.0005).rounded(.down) : 0
        let pos = f > 1 ? min(max(f - laps, 0.001), 0.999) : f
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - lineWidth / 2
            ZStack {
                // The track: the deep colour, very dark (fainter in one colour).
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(deep.opacity(fullColor ? 0.28 : 0.12), lineWidth: lineWidth)
                if f > 0 {
                    if fullColor {
                        progress(f: f, laps: laps, pos: pos)
                    } else {
                        Rectangle().fill(Color.white.opacity(emphasis))
                            .mask(progress(f: f, laps: laps, pos: pos).luminanceToAlpha())
                            .widgetAccentable()
                    }
                    // A small white dot where you have reached.
                    let angle = (pos * 2 - 0.5) * .pi
                    Circle()
                        .fill(Color.white)
                        .frame(width: lineWidth * 0.38, height: lineWidth * 0.38)
                        .position(x: geo.size.width / 2 + radius * cos(angle), y: geo.size.height / 2 + radius * sin(angle))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Below the goal: light at the start to deep at the tip. Past it, one scale over the whole way: the rest of the
    /// previous lap, then the new lap on top from 12 o'clock to the tip. Round ends drawn as dots in their colour.
    private func progress(f: Double, laps: Double, pos: Double) -> some View {
        let darkEdge = fullColor && colorScheme == .dark
        let lw = lineWidth
        return Canvas { context, canvasSize in
            let r = min(canvasSize.width, canvasSize.height) / 2 - lw / 2
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            var path = Path()
            path.addArc(center: center, radius: r, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
            let style = StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .miter)
            func point(_ u: Double) -> CGPoint {
                let a = (u * 2 - 0.5) * .pi
                return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            }
            func dot(_ u: Double, radius: CGFloat, _ color: Color) {
                let p = point(u)
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius)),
                             with: .color(color))
            }
            // Short pieces, each in the colour at its middle, each reaching a little into the next (no hairlines).
            func stroke(from u0: Double, to u1: Double, _ color: (Double) -> Color) {
                let count = max(1, Int(((u1 - u0) * Self.piecesPerLap).rounded(.up)))
                let step = (u1 - u0) / Double(count)
                for n in 0..<count {
                    let a = u0 + step * Double(n)
                    let b = min(a + step * 1.6, u1)
                    context.stroke(path.trimmedPath(from: a, to: b), with: .color(color(a + step / 2)), style: style)
                }
            }
            if f <= 1 {
                dot(0, radius: lw / 2, tone(0))
                stroke(from: 0, to: f) { tone($0 / f) }
                dot(f, radius: lw / 2, tone(1))
            } else {
                stroke(from: pos, to: 1) { tone((laps - 1 + $0) / f) }   // the rest of the previous lap
                // A dark edge under the tip so the new lap clearly lies on top (dark backgrounds only).
                if darkEdge { dot(pos, radius: lw / 2 + 2, .black) }
                dot(0, radius: lw / 2, tone(laps / f))
                stroke(from: 0, to: pos) { tone((laps + $0) / f) }       // the new lap
                dot(pos, radius: lw / 2, tone(1))
            }
        }
    }
}

/// The round complication (and Lock Screen circle): one ring thick with its percentage in the middle, as in Heart
/// Minutes; several rings concentric, each in the same style.
struct ToneRingStack: View {
    let rings: [RingDisplay]

    var body: some View {
        let shown = rings.filter { !$0.hidden }
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            ZStack {
                if shown.count == 1, let ring = shown.first {
                    let (deep, light) = colours(ring)
                    ToneRing(light: light, deep: deep, fraction: ring.fraction, lineWidth: diameter * 0.14)
                        .saturation(ring.faded ? 0.15 : 1)
                        .opacity(ring.faded ? 0.3 : 1)
                    Text(max(0, ring.fraction), format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: diameter * 0.26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(width: diameter * 0.62)
                } else {
                    // Several rings (or every ring hidden: a check in their place).
                    RingStackView(rings: rings)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The ring's deep (start of its gradient) and light (end) colour; a limit past its limit in the warning colours.
    private func colours(_ ring: RingDisplay) -> (deep: Color, light: Color) {
        ring.warning ? (RingDisplay.warningGradient.start, RingDisplay.warningGradient.end) : (ring.start, ring.end)
    }
}
