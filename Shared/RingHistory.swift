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
    /// Whether Health had any data for the metric in the whole range read. With none, the app says so instead of
    /// showing zeros (HealthKit never tells an app it may not read a type: it just returns nothing).
    var hasData = true

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

    /// How many days inside `interval` have a value above zero.
    static func daysWithData(_ daily: [Date: Double], in interval: DateInterval, calendar: Calendar) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            if (daily[day] ?? 0) > 0 { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    static func make(for ring: Ring, daily: [Date: Double], now: Date = .now, calendar: Calendar) -> RingHistory {
        let period = ring.period
        let closed = ring.isMet
        let current = period.interval(now: now, calendar: calendar)
        let currentValue = ring.measure(daily: daily, in: current, now: now, calendar: calendar)

        let lookback = period.history(now: now, count: max(period.streakLookback, shownCount(for: period)),
                                      calendar: calendar)
        let values = lookback.map { ring.measure(daily: daily, in: $0, now: now, calendar: calendar) }
        let streakCount = min(period.streakLookback, lookback.count)
        let streak = Streak(ring: ring, finished: Array(values.prefix(streakCount)), inProgress: currentValue)

        var history = RingHistory(streak: streak, hasData: daily.values.contains { $0 > 0 })
        let shown = shownCount(for: period)
        if period.isRolling {
            // Oldest first, ending with today's live window.
            let past = zip(lookback, values).prefix(shown - 1).reversed().map { interval, value in
                DayValue(day: calendar.startOfDay(for: interval.end.addingTimeInterval(-1)), value: value)
            }
            history.days = past + [DayValue(day: calendar.startOfDay(for: now), value: currentValue)]
        } else {
            history.periods = [PeriodRecord(interval: current, value: currentValue,
                                            closed: ring.isMetInProgress(currentValue), isCurrent: true)]
                + zip(lookback, values).prefix(shown - 1).map { interval, value in
                    PeriodRecord(interval: interval, value: value, closed: closed(value), isCurrent: false)
                }
        }
        return history
    }
}

/// One page of a ring's history: a calendar month, or a year for monthly rings.
struct HistoryPage: Hashable, Sendable {
    var range: DateInterval
    /// Fixed rings: the periods that overlap the page (and have started), newest first.
    var periods: [PeriodRecord] = []
    /// Rolling rings: the window value per day of the page up to today, oldest first.
    var days: [DayValue] = []

    /// Pages are months, except for rings that reset every month: those page by year.
    static func unit(for period: RingPeriod) -> Calendar.Component {
        if case .thisMonth = period { .year } else { .month }
    }

    /// The page `offset` pages from the current one (0 = this month or year, -1 = the one before, …).
    static func range(for period: RingPeriod, offset: Int, now: Date, calendar: Calendar) -> DateInterval {
        let unit = unit(for: period)
        let date = calendar.date(byAdding: unit, value: offset, to: now) ?? now
        return calendar.dateInterval(of: unit, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    /// The earliest day whose value the page needs.
    static func requiredStart(for ring: Ring, range: DateInterval, now: Date, calendar: Calendar) -> Date {
        let lastDay = min(range.end.addingTimeInterval(-1), now)
        if case .rollingDays(let n) = ring.period {
            return calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: range.start)) ?? range.start
        }
        return min(ring.period.interval(containing: range.start, calendar: calendar).start, calendar.startOfDay(for: lastDay))
    }

    static func make(for ring: Ring, daily: [Date: Double], range: DateInterval, now: Date,
                     calendar: Calendar) -> HistoryPage {
        var page = HistoryPage(range: range)
        let current = ring.period.interval(now: now, calendar: calendar)
        if ring.period.isRolling {
            var day = calendar.startOfDay(for: range.start)
            let today = calendar.startOfDay(for: now)
            while day < range.end && day <= today {
                let window = day == today ? current : ring.period.interval(containing: day, calendar: calendar)
                page.days.append(DayValue(day: day, value: ring.measure(daily: daily, in: window, now: now, calendar: calendar)))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        } else {
            var interval = ring.period.interval(containing: min(range.end.addingTimeInterval(-1), now), calendar: calendar)
            while interval.end > range.start {
                if interval.start <= now {
                    let isCurrent = interval.start == current.start
                    let span = isCurrent ? current : interval
                    let value = ring.measure(daily: daily, in: span, now: now, calendar: calendar)
                    let closed = isCurrent ? ring.isMetInProgress(value) : ring.isMet(value)
                    page.periods.append(PeriodRecord(interval: interval, value: value, closed: closed,
                                                     isCurrent: isCurrent))
                }
                interval = ring.period.previous(interval, calendar: calendar)
            }
        }
        return page
    }

    /// "November 2026" ("Nov 2026" when `short`), or "2026" for a year page.
    func title(calendar: Calendar, short: Bool = false) -> String {
        var style = calendar.dateInterval(of: .year, for: range.start) == range
            ? Date.FormatStyle.dateTime.year()
            : Date.FormatStyle.dateTime.month(short ? .abbreviated : .wide).year()
        style.timeZone = calendar.timeZone
        return range.start.formatted(style)
    }
}

extension RingPeriod {
    /// A finished or current period's name in a history list: "Mon 16 Nov", "16 Nov – 22 Nov", "November 2026".
    /// The week's number in the calendar's own numbering (ISO weeks with a Monday start in e.g. Denmark).
    static func weekNumber(of interval: DateInterval, calendar: Calendar) -> Int {
        calendar.component(.weekOfYear, from: interval.start)
    }

    /// The name of the period in progress in lists: "This week · Week 47", otherwise the title.
    func currentLabel(for interval: DateInterval, calendar: Calendar) -> String {
        guard case .thisWeek = self else { return title }
        return String(localized: "\(title) · Week \(Self.weekNumber(of: interval, calendar: calendar))")
    }

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
        case .thisWeek:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let week = Self.weekNumber(of: interval, calendar: calendar)
            return String(localized: "Week \(week) · \(interval.start.formatted(day)) – \(last.formatted(day))")
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
        let perDay = ring.isAverage ? ring.goal
            : ring.isDaysReaching ? ring.dailyTarget
            : ring.goal / Double(ring.period.nominalDays)
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
