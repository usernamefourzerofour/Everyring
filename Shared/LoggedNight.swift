import Foundation

/// One night of sleep from Health, for the detail screen of a sleep ring: when it was, how long you slept, and how
/// long in each stage (when the watch or a sleep app recorded stages).
struct LoggedNight: Identifiable, Hashable, Sendable {
    /// From falling asleep to waking up.
    var interval: DateInterval
    /// Time asleep (awake gaps not counted).
    var asleep: TimeInterval
    /// Time in each recorded stage.
    var stages: [SleepStage: TimeInterval] = [:]

    var id: Date { interval.start }
    /// Awake inside the night: the gaps between asleep times.
    var awake: TimeInterval { max(0, interval.duration - asleep) }
    /// Asleep without a recorded stage (older watches, sleep apps that only record "asleep").
    var unspecified: TimeInterval { max(0, asleep - stages.values.reduce(0, +)) }

    /// The day the night counts on: the day you woke up.
    func day(calendar: Calendar) -> Date { calendar.startOfDay(for: interval.end.addingTimeInterval(-1)) }

    /// What a ring of `metric` counts for this night, in hours.
    func hours(for metric: HealthMetric) -> Double {
        if case .sleepStage(let stage) = metric { return (stages[stage] ?? 0) / 3600 }
        return asleep / 3600
    }

    /// Nights from asleep intervals (each with its stage, if recorded): asleep times with gaps of at most `maxGap`
    /// belong to the same night, as for the ring's value. Oldest first.
    static func make(_ samples: [(interval: DateInterval, stage: SleepStage?)],
                     maxGap: TimeInterval = 2 * 3600) -> [LoggedNight] {
        IntervalMath.sessions(samples.map(\.interval), maxGap: maxGap).compactMap { night in
            guard let start = night.first?.start, let end = night.last?.end else { return nil }
            let span = DateInterval(start: start, end: end)
            var stages: [SleepStage: TimeInterval] = [:]
            for stage in SleepStage.allCases {
                let time = IntervalMath.covered(samples.filter { $0.stage == stage }.map(\.interval), within: span)
                if time > 0 { stages[stage] = time }
            }
            return LoggedNight(interval: span, asleep: night.reduce(0) { $0 + $1.duration }, stages: stages)
        }
    }
}

extension Ring {
    /// What one day should reach (or stay under), for marking days and nights: the goal of a one-day ring, the daily
    /// goal of an average ring, or a days-reaching ring's target. `nil` for totals over several days.
    var dailyGoal: Double? {
        if isDaysReaching { return dailyTarget }
        if isAverage || period.nominalDays == 1 { return goal }
        return nil
    }

    /// Whether one day's value meets `dailyGoal`.
    func dayIsMet(_ value: Double) -> Bool? {
        guard let target = dailyGoal, target > 0 else { return nil }
        return goalKind == .limit ? value <= target : value >= target
    }
}

extension DemoHistory {
    /// Made-up nights for demo mode: around 7 to 8 hours, with stages.
    static func nights(in interval: DateInterval, now: Date, calendar: Calendar) -> [LoggedNight] {
        var result: [LoggedNight] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < min(interval.end, now) {
            let ordinal = Int(day.timeIntervalSinceReferenceDate / 86_400)
            let bedtime = day.addingTimeInterval(Double(-60 - (ordinal * 37) % 90) * 60)
            let length = Double(6 * 60 + (ordinal * 53) % 150) * 60
            let wake = bedtime.addingTimeInterval(length)
            if wake <= now {
                let awake = Double(10 + ordinal % 25) * 60
                let asleep = length - awake
                result.append(LoggedNight(interval: DateInterval(start: bedtime, end: wake), asleep: asleep,
                                          stages: [.deep: asleep * 0.16, .rem: asleep * 0.22, .core: asleep * 0.62]))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.reversed()
    }
}
