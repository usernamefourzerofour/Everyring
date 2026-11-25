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
