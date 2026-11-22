import Foundation

/// A workout from Health with the exercise minutes logged during it, for the detail screen of an exercise-minute ring.
struct LoggedWorkout: Identifiable, Hashable, Sendable {
    var id: UUID
    /// `nil` for workout types Everyring has no kind for.
    var kind: WorkoutKind?
    var start: Date
    var end: Date
    /// Exercise minutes whose middle falls inside the workout (Health doesn't tie them to workouts).
    var exerciseMinutes: Double

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var title: String { kind?.title ?? String(localized: "Other workout") }
    var symbol: String { kind?.symbol ?? "dumbbell" }

    /// Whether the ring leaves this workout's minutes out.
    func isLeftOut(by ring: Ring) -> Bool {
        guard case .exerciseMinutes(let excluded?) = ring.metric, let kind else { return false }
        return excluded.kinds.contains(kind)
    }

    /// The minutes of `samples` that fall in each of `spans` (by each sample's middle; a sample counts once, in the
    /// first span that holds it).
    static func minutes(of samples: [(interval: DateInterval, minutes: Double)], in spans: [DateInterval]) -> [Double] {
        var result = Array(repeating: 0.0, count: spans.count)
        for sample in samples {
            let middle = sample.interval.start.addingTimeInterval(sample.interval.duration / 2)
            if let index = spans.firstIndex(where: { $0.contains(middle) }) {
                result[index] += sample.minutes
            }
        }
        return result
    }
}

extension DemoHistory {
    /// Made-up workouts for demo mode: one most days, at varying times and kinds.
    static func workouts(in interval: DateInterval, now: Date, calendar: Calendar) -> [LoggedWorkout] {
        let kinds: [WorkoutKind] = [.running, .strength, .walking, .yoga, .cycling]
        var result: [LoggedWorkout] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < min(interval.end, now) {
            let ordinal = Int(day.timeIntervalSinceReferenceDate / 86_400)
            if ordinal % 3 != 1, let start = calendar.date(byAdding: .minute, value: 7 * 60 + (ordinal * 97) % (11 * 60), to: day) {
                let length = Double(25 + (ordinal * 13) % 40)
                let end = start.addingTimeInterval(length * 60)
                if end <= now {
                    let kind = kinds[abs(ordinal) % kinds.count]
                    let share = kind == .walking || kind == .yoga ? 0.35 : 0.85
                    result.append(LoggedWorkout(id: UUID(), kind: kind, start: start, end: end,
                                                exerciseMinutes: (length * share).rounded()))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.reversed()
    }
}
