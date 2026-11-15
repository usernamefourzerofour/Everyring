import Foundation

/// The first day of the week. Defaults to the device region; the user can override it in Settings.
enum WeekStart: String, Codable, CaseIterable, Sendable {
    case system, sunday, monday, saturday

    /// `Calendar.firstWeekday` value (1 = Sunday … 7 = Saturday), or `nil` for the region default.
    var firstWeekday: Int? {
        switch self {
        case .system: nil
        case .sunday: 1
        case .monday: 2
        case .saturday: 7
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "Region default")
        case .sunday: String(localized: "Sunday")
        case .monday: String(localized: "Monday")
        case .saturday: String(localized: "Saturday")
        }
    }

    /// `base` with this week start applied. Time zone and locale stay as in `base`.
    func calendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        if let firstWeekday { calendar.firstWeekday = firstWeekday }
        return calendar
    }
}
