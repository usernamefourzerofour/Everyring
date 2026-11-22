import SwiftUI
import UIKit
import WidgetKit

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
    /// A closed ring drawn pale and matte (the ring's "when closed: fade").
    var faded = false
    /// A closed ring not drawn at all (the ring's "when closed: hide"); its place stays empty.
    var hidden = false

    init(id: UUID, start: Color, end: Color, fraction: Double, warning: Bool = false, symbol: String? = nil,
         faded: Bool = false, hidden: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.fraction = fraction
        self.warning = warning
        self.symbol = symbol
        self.faded = faded
        self.hidden = hidden
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

    /// The ring as drawn for `value`. With `glance` (home screen, widgets, watch), a closed ring fades or hides if
    /// the ring says so; details and history always show it as it is.
    func display(_ value: Double, glance: Bool = false) -> RingDisplay {
        let (start, end) = gradient
        let closed = glance && !isLimit && isMetInProgress(value)
        return RingDisplay(id: id, start: start, end: end, fraction: fraction(value),
                           warning: marksOverLimit && isOverLimit(value),
                           symbol: symbol, faded: closed && whenClosed == .fade, hidden: closed && whenClosed == .hide)
    }

    /// The colour for the ring's text and icons at `value`: the warning colour past a limit (unless turned off).
    func tint(_ value: Double) -> Color {
        marksOverLimit && isOverLimit(value) ? RingDisplay.warningGradient.end : accent
    }
}

/// Concentric rings, outermost first. Stroke width scales with the ring count so up to five rings stay readable in a
/// small widget or a complication.
struct RingStackView: View {
    var rings: [RingDisplay]
    /// Each ring's icon and percentage written on the ring at its start (small widget).
    var showsLabels = false
    /// Tinted and clear Home Screens, Lock Screen and watch faces draw widgets in one colour: then the rings are drawn
    /// for that (see `ToneRing`).
    @Environment(\.widgetRenderingMode) private var renderingMode

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
        // Hidden rings (closed, set to hide) are left out entirely: the rest close up and grow, as if it was never
        // there.
        let shown = rings.filter { !$0.hidden }
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            let lw = Self.lineWidth(diameter: diameter, count: shown.count)
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, ring in
                    let radius = diameter / 2 - lw / 2 - CGFloat(index) * lw * (1 + Self.gapUnits)
                    let monochrome = renderingMode != .fullColor
                    ZStack {
                        // Drawn as in Heart Minutes: light at the start building to deep at the tip, a white dot
                        // where you have reached (see ToneRing).
                        // Past a limit the ring keeps its own colours; a red ! at its tip says it is over.
                        ToneRing(light: ring.end, deep: ring.start, fraction: ring.fraction, lineWidth: lw,
                                 // In one colour, neighbouring rings alternate strong and softer to tell them apart.
                                 emphasis: index.isMultiple(of: 2) ? 1 : 0.72,
                                 warning: ring.warning,
                                 // The tip's dot stays behind the label: not drawn where the text is.
                                 dotHiddenUntil: showsLabels
                                    ? RingStartLabel(ring: ring, radius: radius, lineWidth: lw).span : 0)
                            .frame(width: (radius + lw / 2) * 2, height: (radius + lw / 2) * 2)
                        if showsLabels {
                            RingStartLabel(ring: ring, radius: radius, lineWidth: lw, monochrome: monochrome)
                        }
                    }
                    // In one colour the label is cut out of the ring (see RingStartLabel), within this ring only.
                    .compositingGroup()
                    // A closed ring steps back: matte (no colour) and see-through.
                    .saturation(ring.faded ? 0.15 : 1)
                    .opacity(ring.faded ? 0.3 : 1)
                }
            }
            .overlay {
                // Every ring closed and hidden: a quiet check in their place.
                if !rings.isEmpty && shown.isEmpty {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: diameter * 0.35, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
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
    var ring: RingDisplay
    let radius: CGFloat
    let lineWidth: CGFloat
    /// One-colour widgets: on the filled arc the text is cut out of the ring (the background shows through), since
    /// white on a tinted white ring can't be read.
    var monochrome = false

    /// One glyph on the ring: a symbol or a character, with roughly how much arc it takes.
    private struct Glyph: Identifiable {
        var id: Int
        var symbol: String?
        var text: String
        /// Angle of the glyph's centre, clockwise from 12 o'clock.
        var angle: Double
    }

    var body: some View {
        let percent = max(0, ring.fraction).formatted(.percent.precision(.fractionLength(0)))
        let size = fittedSize(percent: percent)
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
        .foregroundStyle(filledUnder || monochrome ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .blendMode(monochrome && filledUnder ? .destinationOut : .normal)
        .accessibilityHidden(true)
    }

    /// A limit past its limit whose tip lies under the label: the label carries the ! in place of the ring's icon
    /// (the tip's badge would cover the text).
    private var shownSymbol: String? {
        guard ring.warning else { return ring.symbol }
        let f = max(0, ring.fraction)
        let tip = f > 1 ? f - (f - 0.0005).rounded(.down) : f
        var plain = self
        plain.ring.warning = false
        return tip <= plain.span ? "exclamationmark.circle.fill" : ring.symbol
    }

    /// How far round the ring the label reaches, as a fraction of a lap (with a little room after it).
    var span: Double {
        let percent = max(0, ring.fraction).formatted(.percent.precision(.fractionLength(0)))
        let end = layout(percent: percent, size: fittedSize(percent: percent)).1
        return (end + Double(lineWidth) * 0.4 / Double(max(radius, 1))) / (2 * .pi)
    }

    /// The text size: on a small inner ring a full-size label would run far around it, so shrink it to fit about 100°.
    private func fittedSize(percent: String) -> CGFloat {
        let size = lineWidth * 0.62
        let maxAngle = Double.pi * 100 / 180
        let natural = layout(percent: percent, size: size).1
        return natural > maxAngle ? size * max(0.7, maxAngle / natural) : size
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
        let curve = 1 + lineWidth * 0.12 / max(radius, 1)
        if let symbol = shownSymbol {
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
