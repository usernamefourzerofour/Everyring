import Foundation
import Testing
@testable import Everyring

struct WorkoutFilterTests {
    @Test func emptyFilterMeansAllWorkouts() {
        #expect(WorkoutFilter.make([]) == nil)
        #expect(WorkoutFilter.make([], excludes: true) == nil)
    }

    @Test func titles() {
        #expect(HealthMetric.workouts(.count, kind: nil).title == "Workouts")
        #expect(HealthMetric.workouts(.count, kind: .only(.strength)).title == "Strength workouts")
        #expect(HealthMetric.workouts(.minutes, kind: .make([.yoga, .strength])).title == "Strength and Yoga minutes")
        #expect(HealthMetric.workouts(.count, kind: .make([.walking], excludes: true)).title == "Workouts except Walking")
        #expect(WorkoutFilter.summary(.make([.running, .cycling, .swimming])) == "3 types")
    }

    @Test func includesAndExcludes() throws {
        let only = try #require(WorkoutFilter.make([.running, .cycling]))
        #expect(only.includes(.running) && !only.includes(.yoga))
        let except = try #require(WorkoutFilter.make([.walking], excludes: true))
        #expect(!except.includes(.walking) && except.includes(.running))
    }

    @Test func distanceDropsKindsWithoutDistance() {
        let filter = WorkoutFilter.make([.running, .yoga])
        #expect(WorkoutFilter.adapted(filter, to: .distance) == .only(.running))
        #expect(WorkoutFilter.adapted(.only(.yoga), to: .distance) == nil)
        #expect(WorkoutFilter.adapted(filter, to: .minutes) == filter)
    }

    @Test func singleKindDrivesIconAndColour() {
        #expect(HealthMetric.workouts(.count, kind: .only(.yoga)).defaultSymbol == WorkoutKind.yoga.symbol)
        #expect(HealthMetric.workouts(.count, kind: .make([.yoga, .dance])).defaultSymbol == "dumbbell")
    }

    @Test func oldSingleKindRingsStillDecode() throws {
        let old = #"{"workouts":{"_0":"count","kind":"strength"}}"#
        let metric = try JSONDecoder().decode(HealthMetric.self, from: Data(old.utf8))
        #expect(metric == .workouts(.count, kind: .only(.strength)))
        let filtered = HealthMetric.workouts(.minutes, kind: .make([.walking, .hiking], excludes: true))
        let roundTrip = try JSONDecoder().decode(HealthMetric.self, from: JSONEncoder().encode(filtered))
        #expect(roundTrip == filtered)
        let all = HealthMetric.workouts(.count, kind: nil)
        #expect(try JSONDecoder().decode(HealthMetric.self, from: JSONEncoder().encode(all)) == all)
    }

    @Test func activityRingsLeaveOutWorkouts() {
        var ring = Ring(name: "Exercise", color: .magenta, symbol: "bolt.heart", metric: .exerciseMinutes, goal: 150,
                        period: .rollingDays(7), leftOutWorkouts: [.walking])
        #expect(ring.healthFilter.leftOutWorkouts == [.walking])
        let walk = LoggedWorkout(id: UUID(), kind: .walking, start: .now, end: .now, value: 5)
        var run = walk
        run.kind = .running
        #expect(walk.isLeftOut(by: ring))
        #expect(!run.isLeftOut(by: ring))
        // Metrics without workouts to leave out ignore the setting.
        ring.metric = .sleep
        #expect(ring.healthFilter.leftOutWorkouts.isEmpty)
        #expect(!walk.isLeftOut(by: ring))
    }

    @Test func minimumLengthOnlyForWorkoutRings() {
        var ring = Ring(name: "W", color: .indigo, symbol: "dumbbell", metric: .workouts(.count, kind: nil), goal: 3,
                        period: .thisWeek, minimumWorkoutMinutes: 20)
        #expect(ring.healthFilter.minimumWorkoutMinutes == 20)
        ring.metric = .steps
        #expect(ring.healthFilter.minimumWorkoutMinutes == 0)
    }
}
