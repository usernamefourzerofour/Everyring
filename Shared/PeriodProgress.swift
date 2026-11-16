import Foundation

/// How a ring's value built up through its current period: a running total per hour (one-day periods) or per day.
struct PeriodProgress: Hashable, Sendable {
    struct Point: Identifiable, Hashable, Sendable {
        var date: Date
        /// Running total in the metric's base unit.
        var total: Double
        var id: Date { date }
    }

    /// The whole period (for a rolling ring: the window's whole days, ending tonight).
    var interval: DateInterval
    /// Starts with zero at the period start and ends at now.
    var points: [Point]
    /// Hourly buckets for one-day periods, otherwise daily.
    var bucket: Calendar.Component
    /// Where you would be now going at an even pace to the goal; `nil` for rolling rings, which have no "now" in a
    /// period that started on a fixed day.
    var paceNow: Double?
    /// A finished period picked in the history (not the one in progress).
    var isPast = false

    /// Whether the chart counts hours (one-day periods) or days.
    static func bucket(for period: RingPeriod) -> Calendar.Component {
        switch period {
        case .today, .everyDays(1, _): .hour
        default: .day
        }
    }

    /// The whole period the chart spans.
    static func chartInterval(for ring: Ring, now: Date, calendar: Calendar) -> DateInterval {
        ring.period.interval(containing: now, calendar: calendar)
    }

    /// - Parameters:
    ///   - buckets: values keyed by the start of each hour or day.
    ///   - interval: a past period to show instead of the current one (whole days; for a rolling ring, the window
    ///     ending on a past day).
    static func make(for ring: Ring, buckets: [Date: Double], interval chosen: DateInterval? = nil, now: Date,
                     calendar: Calendar) -> PeriodProgress {
        let interval = chosen ?? chartInterval(for: ring, now: now, calendar: calendar)
        let isPast = interval.end <= now
        let now = min(now, interval.end)
        let bucket = bucket(for: ring.period)
        var points = [Point(date: interval.start, total: 0)]
        var total = 0.0
        var start = interval.start
        while start < min(interval.end, now) {
            guard let next = calendar.date(byAdding: bucket, value: 1, to: start) else { break }
            total += buckets[start] ?? 0
            points.append(Point(date: min(next, now), total: total))
            start = next
        }
        var pace: Double?
        if !ring.period.isRolling, interval.duration > 0 {
            pace = ring.goal * min(1, max(0, now.timeIntervalSince(interval.start) / interval.duration))
        }
        return PeriodProgress(interval: interval, points: points, bucket: bucket, paceNow: pace, isPast: isPast)
    }
}

extension DemoHistory {
    /// Made-up hourly values for demo mode: the ring's current value spread over the waking hours so far.
    static func hourly(total: Double, from start: Date, to now: Date, calendar: Calendar) -> [Date: Double] {
        var hours: [Date] = []
        var hour = start
        while hour < now {
            let h = calendar.component(.hour, from: hour)
            if (7...22).contains(h) { hours.append(hour) }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
            hour = next
        }
        guard !hours.isEmpty else { return [:] }
        let weights = hours.map { 0.5 + Double(calendar.component(.hour, from: $0) * 37 % 11) / 10 }
        let sum = weights.reduce(0, +)
        return Dictionary(uniqueKeysWithValues: zip(hours, weights.map { total * $0 / sum }))
    }
}

/// Per-day figures for periods of several days, shown under the ring.
struct DailyPace: Hashable, Sendable {
    /// The value per day so far (a finished period: over all its days).
    var average: Double
    /// Days counted in the average.
    var days: Int
    /// Days left in a fixed period in progress, today included; 0 otherwise.
    var daysLeft: Int
    /// Per remaining day: what is still needed to reach the goal, or (for a limit) what is left of it. `nil` when
    /// the goal is already reached or the limit already exceeded, or with no days left.
    var perDayLeft: Double?

    /// `nil` for one-day periods, where the average is the value itself.
    static func make(for ring: Ring, value: Double, interval: DateInterval, now: Date,
                     calendar: Calendar) -> DailyPace? {
        let wholeDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: interval.start),
                                                to: calendar.startOfDay(for: interval.end.addingTimeInterval(-1))).day.map { $0 + 1 } ?? 1
        guard wholeDays > 1 else { return nil }
        let inProgress = interval.end > now
        var days = wholeDays
        var daysLeft = 0
        if inProgress && !ring.period.isRolling {
            let elapsed = (calendar.dateComponents([.day], from: calendar.startOfDay(for: interval.start),
                                                   to: calendar.startOfDay(for: now)).day ?? 0) + 1
            days = max(1, min(wholeDays, elapsed))
            daysLeft = max(0, wholeDays - elapsed + 1)
        }
        var pace = DailyPace(average: value / Double(days), days: days, daysLeft: daysLeft)
        let remaining = ring.goal - value
        if daysLeft > 0, remaining > 0 {
            pace.perDayLeft = remaining / Double(daysLeft)
        }
        return pace
    }
}
