import Foundation

/// How a workout went over time, for its expanded row on an activity ring's detail screen: heart rate and the ring's
/// metric minute by minute.
struct WorkoutTimeline: Hashable, Sendable {
    struct Point: Identifiable, Hashable, Sendable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    /// Average heart rate per short interval, in beats per minute (empty without heart rate data or access).
    var heartRate: [Point] = []
    /// The ring's metric per minute, in its base unit.
    var perMinute: [Point] = []

    var isEmpty: Bool { heartRate.isEmpty && !perMinute.contains { $0.value > 0 } }

    var averageHeartRate: Double? {
        heartRate.isEmpty ? nil : heartRate.reduce(0) { $0 + $1.value } / Double(heartRate.count)
    }

    var maxHeartRate: Double? { heartRate.map(\.value).max() }

    /// The metric adding up minute by minute: zero at `start`, then the total at the end of each minute (the last one
    /// at `end`).
    func runningTotal(from start: Date, to end: Date) -> [Point] {
        var total = 0.0
        var result = [Point(date: start, value: 0)]
        for point in perMinute.sorted(by: { $0.date < $1.date }) {
            total += point.value
            result.append(Point(date: min(point.date.addingTimeInterval(60), end), value: total))
        }
        return result
    }
}

extension DemoHistory {
    /// A made-up timeline for demo mode: a warm-up, a steady middle with intervals, and a cool-down.
    static func timeline(for workout: LoggedWorkout) -> WorkoutTimeline {
        let minutes = max(1, Int(workout.duration / 60))
        var timeline = WorkoutTimeline()
        let perMinute = workout.value / Double(minutes)
        for minute in 0..<minutes {
            let progress = Double(minute) / Double(max(1, minutes - 1))
            let warm = min(1, progress * 5) * min(1, (1 - progress) * 6)
            let wave = 0.85 + 0.3 * sin(Double(minute) / 2.5)
            let date = workout.start.addingTimeInterval(Double(minute) * 60)
            timeline.perMinute.append(.init(date: date, value: perMinute * (0.3 + 0.7 * warm) * wave))
            for half in 0..<2 {
                let bpm = 95 + 60 * warm * (0.9 + 0.12 * sin(Double(minute * 2 + half) / 3))
                timeline.heartRate.append(.init(date: date.addingTimeInterval(Double(half) * 30), value: bpm.rounded()))
            }
        }
        return timeline
    }
}

/// How much of an activity metric over a period was logged during workouts and how much in everyday life.
struct ActivitySplit: Hashable, Sendable {
    /// The whole period's value, in the metric's base unit.
    var total: Double = 0
    /// The part logged while workouts ran (overlapping workouts counted once).
    var duringWorkouts: Double = 0

    /// What was logged outside workouts: walking around, taking the stairs, cycling to work.
    var everyday: Double { max(0, total - duringWorkouts) }
    /// The share from workouts, 0–1 (0 when nothing was logged).
    var workoutShare: Double { total > 0 ? min(1, duringWorkouts / total) : 0 }
}
