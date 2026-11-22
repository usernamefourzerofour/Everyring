import Foundation

/// A workout from Health with what the ring's metric logged during it (exercise minutes, steps, …), for the detail
/// screen of an activity ring.
struct LoggedWorkout: Identifiable, Hashable, Sendable {
    var id: UUID
    /// `nil` for workout types Everyring has no kind for.
    var kind: WorkoutKind?
    var start: Date
    var end: Date
    /// The ring's metric logged during the workout, in its base unit (Health doesn't tie it to workouts: it is what
    /// was logged while the workout ran).
    var value: Double

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var title: String { kind?.title ?? String(localized: "Other workout") }
    var symbol: String { kind?.symbol ?? "dumbbell" }

    /// Whether the ring leaves out what was logged during this workout.
    func isLeftOut(by ring: Ring) -> Bool {
        guard ring.metric.supportsWorkoutLeaveOut, let kind else { return false }
        return ring.leftOutWorkouts.contains(kind)
    }
}

extension DemoHistory {
    /// Made-up workouts for demo mode: one most days, at varying times and kinds.
    static func workouts(for ring: Ring, in interval: DateInterval, now: Date, calendar: Calendar) -> [LoggedWorkout] {
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
                    let intensity = kind == .walking || kind == .yoga ? 0.35 : 0.85
                    let value: Double = switch ring.metric {
                    case .steps: (length * (kind == .running ? 160 : kind == .walking ? 110 : 30)).rounded()
                    case .activeEnergy: (length * 9 * intensity).rounded()
                    case .walkingRunningDistance: kind == .running ? length * 170 : kind == .walking ? length * 85 : 0
                    default: (length * intensity).rounded()
                    }
                    result.append(LoggedWorkout(id: UUID(), kind: kind, start: start, end: end, value: value))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.reversed()
    }
}

/// An app or device that writes to Health, for picking a ring's sources.
struct HealthSource: Identifiable, Hashable, Sendable {
    /// The bundle identifier.
    var id: String
    var name: String
}

/// What a ring reads beyond its metric: sources, workouts to leave out, a minimum workout length.
struct HealthFilter: Hashable, Sendable {
    var sources: [String] = []
    var leftOutWorkouts: [WorkoutKind] = []
    var minimumWorkoutMinutes = 0

    static let none = HealthFilter()
}

extension Ring {
    /// The ring's filter, with only the parts its metric supports.
    var healthFilter: HealthFilter {
        HealthFilter(sources: sources,
                     leftOutWorkouts: metric.supportsWorkoutLeaveOut ? leftOutWorkouts : [],
                     minimumWorkoutMinutes: metric.isWorkouts ? minimumWorkoutMinutes : 0)
    }
}
