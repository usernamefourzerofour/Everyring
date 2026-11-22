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
    /// The night minute by minute: each stretch with its stage, and the awake gaps (oldest first).
    var segments: [Segment] = []

    /// What a stretch of the night was.
    enum Phase: Int, CaseIterable, Hashable, Sendable {
        // Raw values are the rows of the sleep chart, deep at the bottom.
        case deep, core, asleep, rem, awake

        init(_ stage: SleepStage?) {
            switch stage {
            case .deep: self = .deep
            case .core: self = .core
            case .rem: self = .rem
            case nil: self = .asleep
            }
        }
    }

    struct Segment: Hashable, Sendable {
        var interval: DateInterval
        var phase: Phase
    }

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
            // The stretches inside the night: staged ones when the night has stages (a plain "asleep" sample from
            // another source would cover them), otherwise the plain ones; and the awake gaps between them.
            let inside = samples.filter { $0.interval.start < end && $0.interval.end > start }
            let staged = inside.filter { $0.stage != nil }
            var segments = (staged.isEmpty ? inside : staged)
                .compactMap { sample in sample.interval.intersection(with: span).map { Segment(interval: $0, phase: Phase(sample.stage)) } }
            for (earlier, later) in zip(night, night.dropFirst()) where later.start > earlier.end {
                segments.append(Segment(interval: DateInterval(start: earlier.end, end: later.start), phase: .awake))
            }
            segments.sort { $0.interval.start < $1.interval.start }
            return LoggedNight(interval: span, asleep: night.reduce(0) { $0 + $1.duration }, stages: stages,
                               segments: segments)
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
                // Cycles of about 90 minutes: core, deep (more early in the night), core, REM (more late), a short wake.
                var samples: [(interval: DateInterval, stage: SleepStage?)] = []
                var t = bedtime
                var cycle = 0
                while t < wake {
                    let share = Double(cycle) / 5
                    for (stage, minutes) in [(SleepStage.core, 25.0), (.deep, 30 - 20 * share), (.core, 20.0), (.rem, 10 + 20 * share)] {
                        let end = min(wake, t.addingTimeInterval(minutes * 60))
                        if end > t { samples.append((DateInterval(start: t, end: end), stage)) }
                        t = end
                    }
                    t = min(wake, t.addingTimeInterval(Double(3 + (ordinal + cycle) % 6) * 60))
                    cycle += 1
                }
                if let night = LoggedNight.make(samples, maxGap: 2 * 3600).first {
                    result.append(night)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.reversed()
    }
}
