import SwiftUI
import UIKit

extension RingColor {
    /// Gradient from the ring start to its end. Everyring's own palette: deliberately not Apple's Activity colours.
    var gradient: (start: Color, end: Color) {
        switch self {
        case .sunrise: (Color(hex: 0xFF7A45), Color(hex: 0xFFB86B))
        case .tangerine: (Color(hex: 0xE8562E), Color(hex: 0xFF9152))
        case .magenta: (Color(hex: 0xB0278F), Color(hex: 0xE46CC9))
        case .violet: (Color(hex: 0x6B4BEF), Color(hex: 0xA98CFF))
        case .indigo: (Color(hex: 0x2F4FD8), Color(hex: 0x7A92FF))
        case .lagoon: (Color(hex: 0x0B7F9E), Color(hex: 0x41C0D2))
        case .fern: (Color(hex: 0x23874F), Color(hex: 0x62C98A))
        case .citrus: (Color(hex: 0xD99A00), Color(hex: 0xFFD447))
        }
    }

    var color: Color { gradient.end }

    var title: String {
        switch self {
        case .sunrise: String(localized: "Sunrise")
        case .tangerine: String(localized: "Tangerine")
        case .magenta: String(localized: "Magenta")
        case .violet: String(localized: "Violet")
        case .indigo: String(localized: "Indigo")
        case .lagoon: String(localized: "Lagoon")
        case .fern: String(localized: "Fern")
        case .citrus: String(localized: "Citrus")
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// One ring to draw.
struct RingDisplay: Identifiable, Hashable {
    var id: UUID
    var start: Color
    var end: Color
    /// Fraction of the goal; may exceed 1 (the ring wraps around).
    var fraction: Double
    /// A limit ring past its limit: drawn in the warning colours.
    var warning = false
    /// SF Symbol shown at the ring's start when the stack draws labels.
    var symbol: String?

    init(id: UUID, start: Color, end: Color, fraction: Double, warning: Bool = false, symbol: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.fraction = fraction
        self.warning = warning
        self.symbol = symbol
    }

    init(id: UUID, color: RingColor, fraction: Double, warning: Bool = false) {
        self.init(id: id, start: color.gradient.start, end: color.gradient.end, fraction: fraction, warning: warning)
    }

    /// Warm red, used only for limits that were exceeded (no ring colour can be picked to look like it).
    static let warningGradient = (start: Color(hex: 0xC4282D), end: Color(hex: 0xFF6A5C))
}

extension RingTint {
    var color: Color { Color(red: red, green: green, blue: blue) }

    /// The ring's gradient from a picked colour: a darker start and a lighter end, like the palette's.
    var gradient: (start: Color, end: Color) {
        func mix(_ c: Double, _ toward: Double, _ amount: Double) -> Double { c + (toward - c) * amount }
        return (Color(red: mix(red, 0, 0.18), green: mix(green, 0, 0.18), blue: mix(blue, 0, 0.18)),
                Color(red: mix(red, 1, 0.22), green: mix(green, 1, 0.22), blue: mix(blue, 1, 0.22)))
    }
}

extension Ring {
    /// The ring's gradient: from a freely picked colour, or the palette's.
    var gradient: (start: Color, end: Color) { customTint?.gradient ?? color.gradient }

    /// The ring's main colour for icons, text and highlights.
    var accent: Color { customTint.map { $0.gradient.end } ?? color.color }

    /// The ring as drawn for `value`.
    func display(_ value: Double) -> RingDisplay {
        let (start, end) = gradient
        return RingDisplay(id: id, start: start, end: end, fraction: fraction(value), warning: isOverLimit(value),
                           symbol: symbol)
    }

    /// The colour for the ring's text and icons at `value`: the warning colour past a limit.
    func tint(_ value: Double) -> Color {
        isOverLimit(value) ? RingDisplay.warningGradient.end : accent
    }
}

/// Concentric rings, outermost first. Stroke width scales with the ring count so up to five rings stay readable in a
/// small widget or a complication.
struct RingStackView: View {
    var rings: [RingDisplay]
    /// Background track opacity.
    var trackOpacity = 0.18
    /// Each ring's icon and percentage written on the ring at its start (small widget).
    var showsLabels = false

    /// Free space in the middle, in ring widths, by ring count.
    static func holeUnits(_ count: Int) -> CGFloat {
        switch count {
        case ...1: 3.0
        case 2: 1.8
        case 3: 1.2
        case 4: 0.9
        default: 0.7
        }
    }

    static let gapUnits: CGFloat = 0.14

    static func lineWidth(diameter: CGFloat, count: Int) -> CGFloat {
        let n = CGFloat(max(1, count))
        return diameter / 2 / (n + (n - 1) * gapUnits + holeUnits(count))
    }

    var body: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            let lw = Self.lineWidth(diameter: diameter, count: rings.count)
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let radius = diameter / 2 - lw / 2 - CGFloat(index) * lw * (1 + Self.gapUnits)
                    SingleRing(start: ring.start, end: ring.end, fraction: ring.fraction, lineWidth: lw,
                               trackOpacity: trackOpacity,
                               warning: ring.warning)
                        .frame(width: radius * 2, height: radius * 2)
                    if showsLabels {
                        RingStartLabel(ring: ring, radius: radius, lineWidth: lw)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A ring's icon and percentage written on the ring just after its start (12 o'clock), so a small widget needs no
/// legend. White on the filled ring; in the ring's colour when too little of the ring is filled under the text.
struct RingStartLabel: View {
    let ring: RingDisplay
    let radius: CGFloat
    let lineWidth: CGFloat

    /// One glyph on the ring: a symbol or a character, with roughly how much arc it takes.
    private struct Glyph: Identifiable {
        var id: Int
        var symbol: String?
        var text: String
        /// Angle of the glyph's centre, clockwise from 12 o'clock.
        var angle: Double
    }

    var body: some View {
        let size = lineWidth * 0.62
        let percent = max(0, ring.fraction).formatted(.percent.precision(.fractionLength(0)))
        let (glyphs, end) = layout(percent: percent, size: size)
        // White on the filled arc; where too little is filled under the text, the system's text colour (the track is
        // too light for the ring's own colour, e.g. yellow).
        let filledUnder = ring.fraction * 2 * .pi >= end
        ZStack {
            ForEach(glyphs) { glyph in
                Group {
                    if let symbol = glyph.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.9, weight: .bold))
                    } else {
                        Text(glyph.text)
                            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
                .fixedSize()
                .offset(y: -radius)
                .rotationEffect(.radians(glyph.angle))
            }
        }
        .foregroundStyle(filledUnder ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .accessibilityHidden(true)
    }

    /// Each glyph's centre angle along the ring, starting just after 12 o'clock, and the angle where the text ends.
    private func layout(percent: String, size: CGFloat) -> ([Glyph], Double) {
        let r = Double(max(radius, 1))
        var angle = Double(lineWidth) * 0.35 / r
        var glyphs: [Glyph] = []
        func add(symbol: String?, text: String, advance: CGFloat) {
            let a = Double(advance) / r
            glyphs.append(Glyph(id: glyphs.count, symbol: symbol, text: text, angle: angle + a / 2))
            angle += a
        }
        // On a tight inner ring the glyphs' inner edges crowd together; space them a little more.
        let curve = 1 + lineWidth * 0.25 / max(radius, 1)
        if let symbol = ring.symbol {
            add(symbol: symbol, text: "", advance: (Self.symbolWidth(symbol, size: size * 0.9) + size * 0.3) * curve)
        }
        for character in percent {
            let advance: CGFloat
            switch character {
            case "%": advance = size * 0.82
            case " ", "\u{00A0}", "\u{202F}": advance = size * 0.22
            default: advance = size * 0.6
            }
            if character.isWhitespace { angle += Double(advance * curve) / r; continue }
            add(symbol: nil, text: String(character), advance: advance * curve)
        }
        return (glyphs, angle)
    }

    /// A symbol's drawn width at `size` points (wide symbols such as a dumbbell take much more than a square).
    private static func symbolWidth(_ name: String, size: CGFloat) -> CGFloat {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
        return UIImage(systemName: name, withConfiguration: config)?.size.width ?? size
    }
}

/// One ring: a track, a gradient arc with round caps, and past 100 % a full lap plus the end cap with a shadow over the
/// ring's start, like a ring that wraps around itself.
struct SingleRing: View {
    var start: Color
    var end: Color
    var fraction: Double
    var lineWidth: CGFloat
    var trackOpacity = 0.18
    var warning = false

    var body: some View {
        let (start, end) = warning ? RingDisplay.warningGradient : (self.start, self.end)
        let f = max(0, fraction)
        let wraps = f > 1
        // Position of the ring end within its last lap.
        let tip = wraps ? (f.truncatingRemainder(dividingBy: 1) == 0 ? 1 : f.truncatingRemainder(dividingBy: 1)) : f
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Circle()
                    .stroke(end.opacity(trackOpacity), lineWidth: lineWidth)

                if wraps {
                    // A whole lap whose gradient ends at the tip.
                    Circle()
                        .stroke(AngularGradient(colors: [start, end], center: .center,
                                                startAngle: .degrees(360 * tip - 360), endAngle: .degrees(360 * tip)),
                                lineWidth: lineWidth)
                        .rotationEffect(.degrees(-90))
                    // End cap with a shadow falling on the ring behind it.
                    Circle()
                        .fill(end)
                        .frame(width: lineWidth, height: lineWidth)
                        .shadow(color: .black.opacity(0.35), radius: lineWidth * 0.18, x: 0, y: 0)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(360 * tip))
                } else if f > 0 {
                    Circle()
                        .trim(from: 0, to: f)
                        .stroke(AngularGradient(colors: [start, end], center: .center,
                                                startAngle: .degrees(0), endAngle: .degrees(360 * max(f, 0.001))),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    // The arc's round start cap would take the end colour from the gradient; cover it.
                    Circle()
                        .fill(start)
                        .frame(width: lineWidth, height: lineWidth)
                        .offset(y: -radius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

#Preview("Rings") {
    RingStackView(rings: [
        RingDisplay(id: UUID(), color: .sunrise, fraction: 0.72),
        RingDisplay(id: UUID(), color: .violet, fraction: 1.25),
        RingDisplay(id: UUID(), color: .lagoon, fraction: 0.4),
        RingDisplay(id: UUID(), color: .fern, fraction: 1),
        RingDisplay(id: UUID(), color: .citrus, fraction: 0.1),
    ])
    .padding()
}
