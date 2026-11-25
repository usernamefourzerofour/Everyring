import SwiftUI

/// The mark on a day in a History calendar, always in the same place (the ring's lower right): a green check when the
/// day reached its goal (or, for a limit, ended under it), a red cross when it went over a limit.
///
/// In this folder so the Screen Time report extension, which builds only this folder, draws the same mark as the app.
struct DayMark: View {
    enum Kind {
        case reached
        case over
    }

    let kind: Kind
    var size: CGFloat = 12

    static let reachedColor = Color(red: 0.20, green: 0.66, blue: 0.33)
    static let overColor = Color(red: 0.77, green: 0.16, blue: 0.18)
    static func color(_ kind: Kind) -> Color { kind == .reached ? reachedColor : overColor }

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle()
                .fill(Self.color(kind))
                .padding(size * 0.1)
            Image(systemName: kind == .reached ? "checkmark" : "xmark")
                .font(.system(size: size * 0.48, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Puts a day's mark at the lower right of a day ring, slightly outside it.
    func dayMark(_ kind: DayMark.Kind?, size: CGFloat = 12) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let kind {
                DayMark(kind: kind, size: size).offset(x: size * 0.2, y: size * 0.2)
            }
        }
    }
}

/// A stretch of a loop drawn round the days of one period in a History calendar: closed at the ends where the period
/// starts or ends in a week row, open where it carries on into the next or previous day.
struct LoopSegment: Shape {
    var closedLeading: Bool
    var closedTrailing: Bool
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = min(radius, h / 2)
        var p = Path()
        p.move(to: CGPoint(x: closedLeading ? r : 0, y: 0))
        p.addLine(to: CGPoint(x: closedTrailing ? w - r : w, y: 0))
        if closedTrailing {
            p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
            p.addLine(to: CGPoint(x: w, y: h - r))
            p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
        } else {
            p.move(to: CGPoint(x: w, y: h))
        }
        p.addLine(to: CGPoint(x: closedLeading ? r : 0, y: h))
        if closedLeading {
            p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
