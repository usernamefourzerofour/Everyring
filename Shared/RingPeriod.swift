import Foundation

/// The period a ring measures its goal over.
///
/// Fixed periods (`today`, `thisWeek`, `thisMonth`, `everyDays`, `everyWeeks`) are aligned to calendar boundaries in the
/// calendar's time zone and reset when the next period starts. Rolling periods (`rollingDays`) never reset: they always
/// cover today plus the previous N − 1 calendar days, so old days drop out as new ones begin.
///
/// Whole-day periods move in calendar days (`Calendar.date(byAdding: .day …)`), so daylight saving time never shifts
/// them; such a day can be 23 or 25 hours long.
enum RingPeriod: Codable, Hashable, Sendable {
    case today, thisWeek, thisMonth
    /// Every N days, counted from the day that contains `from`.
    case everyDays(Int, from: Date)
    /// Every N weeks, counted from the day that contains `from` (the anchor's weekday, not the week start setting).
    case everyWeeks(Int, from: Date)
    /// The last N calendar days including today.
    case rollingDays(Int)

    /// Presets offered first in the period picker.
    static let fixedPresets: [RingPeriod] = [.today, .thisWeek, .thisMonth]
    static let rollingPresets: [RingPeriod] = [.rollingDays(3), .rollingDays(7), .rollingDays(14), .rollingDays(30)]
    /// Allowed N for custom rolling periods. One day would just be "today".
    static let rollingRange = 2...90
    /// Allowed N for custom fixed periods.
    static let customDaysRange = 1...365
    static let customWeeksRange = 1...52

    var isRolling: Bool {
        if case .rollingDays = self { true } else { false }
    }

    /// Number of days in a custom fixed period, or `nil`.
    private var customLength: (days: Int, anchor: Date)? {
        switch self {
        case .everyDays(let n, let from): (days: max(1, n), anchor: from)
        case .everyWeeks(let n, let from): (days: 7 * max(1, n), anchor: from)
        default: nil
        }
    }

    private var rollingLength: Int? {
        if case .rollingDays(let n) = self { max(1, n) } else { nil }
    }

    // MARK: Intervals

    /// The period that contains `date`.
    ///
    /// Fixed periods: the whole period, so `end` may lie in the future (today's midnight, next week start, …).
    /// Rolling periods: the N whole days ending with the day that contains `date`. Use `interval(now:)` for the live
    /// window that ends now.
    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        let dayStart = calendar.startOfDay(for: date)
        switch self {
        case .today:
            return Self.days(from: dayStart, count: 1, calendar: calendar)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: date)
                ?? Self.days(from: dayStart, count: 7, calendar: calendar)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: date)
                ?? Self.days(from: dayStart, count: 30, calendar: calendar)
        case .everyDays, .everyWeeks:
            let (length, anchor) = customLength!
            let anchorDay = calendar.startOfDay(for: anchor)
            let offset = calendar.dateComponents([.day], from: anchorDay, to: dayStart).day ?? 0
            let index = Self.floorDiv(offset, length)
            let start = calendar.date(byAdding: .day, value: index * length, to: anchorDay) ?? dayStart
            return Self.days(from: start, count: length, calendar: calendar)
        case .rollingDays:
            let n = rollingLength!
            let start = calendar.date(byAdding: .day, value: -(n - 1), to: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        }
    }

    /// What the ring shows at `now`. Fixed: the whole current period. Rolling: the window up to `now`.
    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let whole = interval(containing: now, calendar: calendar)
        guard isRolling else { return whole }
        return DateInterval(start: whole.start, end: max(whole.start, now))
    }

    /// The period after `interval`. Rolling windows move one day.
    func next(_ interval: DateInterval, calendar: Calendar) -> DateInterval {
        if isRolling { return shiftedWindow(interval, days: 1, calendar: calendar) }
        return self.interval(containing: interval.end, calendar: calendar)
    }

    /// The period before `interval`. Rolling windows move one day (and become whole days).
    func previous(_ interval: DateInterval, calendar: Calendar) -> DateInterval {
        if isRolling { return shiftedWindow(interval, days: -1, calendar: calendar) }
        return self.interval(containing: interval.start.addingTimeInterval(-1), calendar: calendar)
    }

    /// Finished periods before the current one, newest first. For rolling periods: the windows that ended at each of
    /// the previous `count` midnights (yesterday's window first).
    func history(now: Date = .now, count: Int, calendar: Calendar = .current) -> [DateInterval] {
        var result: [DateInterval] = []
        result.reserveCapacity(max(0, count))
        var current = interval(now: now, calendar: calendar)
        for _ in 0..<max(0, count) {
            current = previous(current, calendar: calendar)
            result.append(current)
        }
        return result
    }

    /// Calendar days left in the current fixed period, including today. `nil` for rolling periods.
    func daysLeft(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard !isRolling else { return nil }
        let end = interval(containing: now, calendar: calendar).end
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day
    }

    // MARK: Labels

    /// Short name, e.g. "This week", "Every 2 weeks", "Last 7 days".
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .thisWeek: String(localized: "This week")
        case .thisMonth: String(localized: "This month")
        case .everyDays(let n, _):
            n <= 1 ? String(localized: "Every day") : String(localized: "Every \(n) days")
        case .everyWeeks(let n, _):
            n <= 1 ? String(localized: "Every week") : String(localized: "Every \(n) weeks")
        case .rollingDays(let n): String(localized: "Last \(n) days")
        }
    }

    /// The label shown on a ring, e.g. "This week · 3 days left", "Today" or "Last 7 days".
    func status(now: Date = .now, calendar: Calendar = .current) -> String {
        guard case .today = self else {
            guard let left = daysLeft(now: now, calendar: calendar) else { return title }
            let remaining = left <= 1 ? String(localized: "Last day") : String(localized: "\(left) days left")
            return "\(title) · \(remaining)"
        }
        return title
    }

    // MARK: Helpers

    private func shiftedWindow(_ interval: DateInterval, days: Int, calendar: Calendar) -> DateInterval {
        // The day the window ends with (the end is exclusive, or `now` for the live window).
        let lastDay = interval.end.addingTimeInterval(-1)
        let target = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: lastDay)) ?? lastDay
        return self.interval(containing: target, calendar: calendar)
    }

    private static func days(from start: Date, count: Int, calendar: Calendar) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: count, to: start)
            ?? start.addingTimeInterval(Double(count) * 86_400)
        return DateInterval(start: start, end: end)
    }

    /// Integer division rounding towards minus infinity, so days before the anchor fall in the previous period.
    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }
}
