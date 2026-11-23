import Foundation

/// How a ring's value built up through its current period: a running total per hour (one-day periods) or per day.
struct PeriodProgress: Hashable, Sendable {
    struct Point: Identifiable, Hashable, Sendable {
        var date: Date
        /// Running total in the metric's base unit (for an average ring: the running average per day).
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
    /// The even pace from nothing to the goal over the period, flat over days that don't count.
    var pacePoints: [Point] = []
    /// Days the ring leaves out (weekends for a weekdays ring), shaded in the chart.
    var leftOutDays: [DateInterval] = []

    /// Whether the chart counts hours (one-day periods) or days.
    static func bucket(for period: RingPeriod) -> Calendar.Component {
        switch period {
        case .today, .everyDays(1, _): .hour
        default: .day
        }
    }

    /// The whole period the chart spans.
    static func chartInterval(for ring: Ring, now: Date, calendar: Calendar) -> DateInterval {
        let period = ring.period.interval(containing: now, calendar: calendar)
        // Screen Time is only counted from the day the ring was added: the chart starts there too.
        if ring.metric == .screenTime, let first = ScreenTimeLog.load().firstDay(ring: ring.id, calendar: calendar),
           first > period.start, first < period.end {
            return DateInterval(start: first, end: period.end)
        }
        return period
    }

    /// - Parameters:
    ///   - buckets: values keyed by the start of each hour or day.
    ///   - interval: a past period to show instead of the current one (whole days; for a rolling ring, the window
    ///     ending on a past day).
    /// - Parameter bucketSize: hours instead of the period's usual buckets (a finer chart of a total over several
    ///   days, e.g. for the chart widget).
    static func make(for ring: Ring, buckets: [Date: Double], interval chosen: DateInterval? = nil, now: Date,
                     calendar: Calendar, bucketSize: Calendar.Component? = nil) -> PeriodProgress {
        let interval = chosen ?? chartInterval(for: ring, now: now, calendar: calendar)
        let isPast = interval.end <= now
        let now = min(now, interval.end)
        let bucket = bucketSize ?? bucket(for: ring.period)
        // The period's own unit (days for a week), also when the chart is computed hour by hour.
        let periodBucket = Self.bucket(for: ring.period)
        let average = ring.isAverage && periodBucket == .day
        let daysReaching = ring.isDaysReaching && bucket == .day
        let today = calendar.startOfDay(for: now)
        // An average ring charts its running average per day, which has no meaningful zero at the start.
        var points = average ? [] : [Point(date: interval.start, total: 0)]
        var total = 0.0
        var days = 0
        var begun: Set<Date> = []
        var dayTotals: [Date: Double] = [:]
        var start = interval.start
        while start < min(interval.end, now) {
            guard let next = calendar.date(byAdding: bucket, value: 1, to: start) else { break }
            // Days the ring leaves out (e.g. weekends for a weekdays ring) add nothing.
            let counted = ring.counts(start, calendar: calendar)
            let value = counted ? buckets[start] ?? 0 : 0
            if daysReaching {
                if counted && ring.dayMeetsTarget(value) && (ring.goalKind != .limit || start < today) { total += 1 }
                points.append(Point(date: min(next, now), total: total))
            } else if average {
                // The running average: everything so far over the days begun so far (hour by hour, a day counts
                // from its first hour, as the ring does).
                total += value
                let day = calendar.startOfDay(for: start)
                dayTotals[day, default: 0] += value
                if counted && !begun.contains(day) && !ring.averageSkipsEmptyDays { begun.insert(day) }
                if counted && ring.averageSkipsEmptyDays && (dayTotals[day] ?? 0) > 0 { begun.insert(day) }
                days = begun.count
                points.append(Point(date: min(next, now), total: days > 0 ? total / Double(days) : 0))
            } else {
                total += value
                points.append(Point(date: min(next, now), total: total))
            }
            start = next
        }
        // The days the ring leaves out, to shade in the chart.
        var leftOut: [DateInterval] = []
        if periodBucket == .day && ring.effectiveDays != .everyDay {
            var day = calendar.startOfDay(for: interval.start)
            while day < interval.end {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                if !ring.counts(day, calendar: calendar) { leftOut.append(DateInterval(start: day, end: min(next, interval.end))) }
                day = next
            }
        }
        // An even pace to the goal; days that don't count add nothing, so the line stays flat over them.
        var pace: Double?
        var pacePoints: [Point] = []
        if !ring.period.isRolling, !average, interval.duration > 0 {
            if periodBucket == .day {
                var days: [(start: Date, end: Date, counted: Bool)] = []
                var day = calendar.startOfDay(for: interval.start)
                while day < interval.end {
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    days.append((day, min(next, interval.end), ring.counts(day, calendar: calendar)))
                    day = next
                }
                let countedTotal = Double(max(1, days.filter { $0.counted }.count))
                var sum = 0.0
                pacePoints = [Point(date: interval.start, total: 0)]
                var soFar = 0.0
                for day in days {
                    // The share of this day that has passed (today: partly).
                    let passed = min(1, max(0, now.timeIntervalSince(day.start) / day.end.timeIntervalSince(day.start)))
                    if day.counted {
                        sum += 1
                        soFar += passed
                    }
                    pacePoints.append(Point(date: day.end, total: ring.goal * sum / countedTotal))
                }
                pace = ring.goal * soFar / countedTotal
            } else {
                pacePoints = [Point(date: interval.start, total: 0), Point(date: interval.end, total: ring.goal)]
                pace = ring.goal * min(1, max(0, now.timeIntervalSince(interval.start) / interval.duration))
            }
        }
        return PeriodProgress(interval: interval, points: points, bucket: periodBucket, paceNow: pace, isPast: isPast,
                              pacePoints: pacePoints, leftOutDays: leftOut)
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
    /// What is still needed to reach the goal (or left of a limit) in the rest of the period; `nil` like `perDayLeft`.
    var remaining: Double?

    /// `nil` for one-day periods, where the average is the value itself.
    static func make(for ring: Ring, value: Double, interval: DateInterval, now: Date,
                     calendar: Calendar) -> DailyPace? {
        // An average ring already shows its value per day; a days-reaching ring counts days.
        guard !ring.isAverage, !ring.isDaysReaching else { return nil }
        guard RingPeriod.wholeDays(of: interval, calendar: calendar) > 1 else { return nil }
        let days = max(1, ring.countedDays(in: interval, now: now, calendar: calendar).count)
        var daysLeft = 0
        if interval.end > now && !ring.period.isRolling {
            // The counted days from today to the end of the period.
            let today = calendar.startOfDay(for: now)
            daysLeft = ring.countedDays(in: interval, now: interval.end, calendar: calendar).filter { $0 >= today }.count
        }
        var pace = DailyPace(average: value / Double(days), days: days, daysLeft: daysLeft)
        let remaining = ring.goal - value
        if daysLeft > 0, remaining > 0 {
            pace.perDayLeft = remaining / Double(daysLeft)
            pace.remaining = remaining
        }
        return pace
    }
}

extension RingPeriod {
    /// The calendar days `interval` touches.
    static func wholeDays(of interval: DateInterval, calendar: Calendar) -> Int {
        let first = calendar.startOfDay(for: interval.start)
        let last = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        return max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
    }

    /// The days a daily average over `interval` divides by: all its days for a finished period or a rolling window
    /// (today counts as one of them), and the days so far, today included, for a fixed period in progress.
    func averageDays(in interval: DateInterval, now: Date, calendar: Calendar) -> Int {
        let whole = Self.wholeDays(of: interval, calendar: calendar)
        guard interval.end > now, !isRolling else { return whole }
        let elapsed = (calendar.dateComponents([.day], from: calendar.startOfDay(for: interval.start),
                                               to: calendar.startOfDay(for: now)).day ?? 0) + 1
        return max(1, min(whole, elapsed))
    }
}

extension Ring {
    /// Whether the value needs values per day rather than one total: days that are left out or counted one by one,
    /// or an average over the days with data.
    var needsDailyValues: Bool {
        (isAverage && averageSkipsEmptyDays) || isDaysReaching || effectiveDays != .everyDay
    }

    /// The days of `interval` that count (keyed by start of day): for a fixed period in progress only those up to
    /// today; a finished period or a rolling window, all of them. Days the day filter leaves out are skipped.
    func countedDays(in interval: DateInterval, now: Date, calendar: Calendar) -> [Date] {
        let inProgress = interval.end > now && !period.isRolling
        let last = calendar.startOfDay(for: inProgress ? now : interval.end.addingTimeInterval(-1))
        var result: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day <= last {
            if counts(day, calendar: calendar) { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// The value the ring shows for a period's total, for rings that don't need values per day: the total itself, or
    /// for an average ring the average per day.
    func measure(_ total: Double, in interval: DateInterval, now: Date, calendar: Calendar) -> Double {
        guard isAverage else { return total }
        return total / Double(period.averageDays(in: interval, now: now, calendar: calendar))
    }

    /// For a Screen Time ring: how many of the period's days it has data for, when that's fewer than the period (the
    /// days before the ring was made don't count). Nil otherwise.
    func screenTimeDaysTracked(in interval: DateInterval, now: Date, calendar: Calendar) -> Int? {
        guard metric == .screenTime, let first = ScreenTimeLog.load().firstDay(ring: id, calendar: calendar) else { return nil }
        let all = countedDays(in: interval, now: now, calendar: calendar)
        let tracked = all.filter { $0 >= first }.count
        return tracked < all.count ? tracked : nil
    }

    /// The value the ring shows for `interval`, from values per day (keyed by start of day).
    func measure(daily: [Date: Double], in interval: DateInterval, now: Date, calendar: Calendar) -> Double {
        var days = countedDays(in: interval, now: now, calendar: calendar)
        // Screen Time is only recorded from when the ring was made: the days before have no data, so they don't
        // count (as 0) in an average or a count of days.
        if metric == .screenTime, let first = ScreenTimeLog.load().firstDay(ring: id, calendar: calendar) {
            days = days.filter { $0 >= first }
        }
        let values = days.map { daily[$0] ?? 0 }
        if isDaysReaching {
            let today = calendar.startOfDay(for: now)
            // A day under a limit only counts once it's over: it could still go over.
            return Double(zip(days, values).filter { day, value in
                dayMeetsTarget(value) && (goalKind != .limit || day < today)
            }.count)
        }
        let total = values.reduce(0, +)
        guard isAverage else { return total }
        let divisor = averageSkipsEmptyDays ? values.filter { $0 > 0 }.count : values.count
        return divisor > 0 ? total / Double(divisor) : 0
    }
}
