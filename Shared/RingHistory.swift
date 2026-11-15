import Foundation

/// One finished or current period of a fixed ring.
struct PeriodRecord: Identifiable, Hashable, Sendable {
    var interval: DateInterval
    var value: Double
    var closed: Bool
    var isCurrent: Bool
    var id: Date { interval.start }
}

/// The value of a rolling ring's window as it stood at the end of a day (today: up to now).
struct DayValue: Identifiable, Hashable, Sendable {
    var day: Date
    var value: Double
    var id: Date { day }
}

/// History and streaks for a ring, computed from one value per calendar day.
///
/// Every period is made of whole calendar days (fixed periods, and rolling windows of N days), so a period's value is
/// the sum of its days. That means one Health query per metric (daily buckets) instead of one per period.
struct RingHistory: Hashable, Sendable {
    var streak: Streak
    /// Fixed rings: the current period first, then finished periods, newest first.
    var periods: [PeriodRecord] = []
    /// Rolling rings: the window value per day, oldest first, ending today.
    var days: [DayValue] = []

    /// How many periods (or days, for rolling rings) the history shows.
    static func shownCount(for period: RingPeriod) -> Int {
        switch period {
        case .today: 35
        case .rollingDays: 60
        default: 12
        }
    }

    /// The earliest day whose value is needed for the history and the streak.
    static func requiredStart(for ring: Ring, now: Date, calendar: Calendar) -> Date {
        let count = max(shownCount(for: ring.period), ring.period.streakLookback)
        let oldest = ring.period.history(now: now, count: count, calendar: calendar).last
            ?? ring.period.interval(now: now, calendar: calendar)
        return calendar.startOfDay(for: oldest.start)
    }

    /// Sum of the daily values (keyed by start of day) inside `interval`.
    static func sum(_ daily: [Date: Double], in interval: DateInterval, calendar: Calendar) -> Double {
        var total = 0.0
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            total += daily[day] ?? 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    static func make(for ring: Ring, daily: [Date: Double], now: Date = .now, calendar: Calendar) -> RingHistory {
        let period = ring.period
        let closed = { (value: Double) in Streak.isClosed(value: value, goal: ring.goal) }
        let current = period.interval(now: now, calendar: calendar)
        let currentValue = sum(daily, in: current, calendar: calendar)

        let lookback = period.history(now: now, count: max(period.streakLookback, shownCount(for: period)),
                                      calendar: calendar)
        let values = lookback.map { sum(daily, in: $0, calendar: calendar) }
        let streakCount = min(period.streakLookback, lookback.count)
        let streak = Streak(finished: values.prefix(streakCount).map(closed), inProgress: closed(currentValue))

        var history = RingHistory(streak: streak)
        let shown = shownCount(for: period)
        if period.isRolling {
            // Oldest first, ending with today's live window.
            let past = zip(lookback, values).prefix(shown - 1).reversed().map { interval, value in
                DayValue(day: calendar.startOfDay(for: interval.end.addingTimeInterval(-1)), value: value)
            }
            history.days = past + [DayValue(day: calendar.startOfDay(for: now), value: currentValue)]
        } else {
            history.periods = [PeriodRecord(interval: current, value: currentValue, closed: closed(currentValue),
                                            isCurrent: true)]
                + zip(lookback, values).prefix(shown - 1).map { interval, value in
                    PeriodRecord(interval: interval, value: value, closed: closed(value), isCurrent: false)
                }
        }
        return history
    }
}

extension RingPeriod {
    /// A finished or current period's name in a history list: "Mon 16 Nov", "16 Nov – 22 Nov", "November 2026".
    func label(for interval: DateInterval, calendar: Calendar) -> String {
        var day = Date.FormatStyle.dateTime.day().month(.abbreviated)
        day.timeZone = calendar.timeZone
        switch self {
        case .today:
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            style.timeZone = calendar.timeZone
            return interval.start.formatted(style)
        case .thisMonth:
            var style = Date.FormatStyle.dateTime.month(.wide).year()
            style.timeZone = calendar.timeZone
            return interval.start.formatted(style)
        default:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(day)) – \(last.formatted(day))"
        }
    }
}

/// Made-up daily values for demo mode and previews: around the goal's daily share, varying by day.
enum DemoHistory {
    static func daily(for ring: Ring, from start: Date, to now: Date, calendar: Calendar) -> [Date: Double] {
        var result: [Date: Double] = [:]
        let perDay = ring.goal / Double(ring.period.nominalDays)
        var day = calendar.startOfDay(for: start)
        while day <= now {
            let ordinal = Int(day.timeIntervalSinceReferenceDate / 86_400)
            // A deterministic wobble between 0.45 and 1.55 of the daily share.
            let wobble = 0.45 + Double((ordinal &* 7_919 &+ Int(ring.id.uuid.0)) % 111) / 100
            result[day] = perDay * wobble
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
