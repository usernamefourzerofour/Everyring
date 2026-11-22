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

    @Test func exerciseMinutesLeaveOutWorkouts() throws {
        #expect(HealthMetric.exerciseMinutes().title == "Exercise minutes")
        let walking = HealthMetric.exerciseMinutes(excluding: .make([.walking], excludes: true))
        #expect(walking.title == "Exercise minutes except Walking")
        #expect(walking.pickerTitle == "Exercise minutes")
        #expect(walking.isSameKind(as: .exerciseMinutes()))
        // Rings saved before the filter existed.
        let old = try JSONDecoder().decode(HealthMetric.self, from: Data(#"{"exerciseMinutes":{}}"#.utf8))
        #expect(old == .exerciseMinutes())
        #expect(try JSONDecoder().decode(HealthMetric.self, from: JSONEncoder().encode(walking)) == walking)
    }

    @Test func exerciseMinutesAreAssignedToTheWorkoutHoldingThem() {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func span(_ a: Double, _ b: Double) -> DateInterval { DateInterval(start: t0 + a * 60, end: t0 + b * 60) }
        let workouts = [span(0, 30), span(60, 90)]
        // Minutes inside the first workout, one between workouts, one straddling the second workout's start.
        let samples = [(span(5, 6), 1.0), (span(10, 11), 1.0), (span(40, 41), 1.0), (span(59.8, 60.8), 1.0)]
            .map { (interval: $0.0, minutes: $0.1) }
        #expect(LoggedWorkout.minutes(of: samples, in: workouts) == [2, 1])
    }

    @Test func leftOutFollowsTheRing() {
        let ring = Ring(name: "Exercise", color: .magenta, symbol: "bolt.heart",
                        metric: .exerciseMinutes(excluding: .make([.walking], excludes: true)), goal: 150, period: .rollingDays(7))
        let walk = LoggedWorkout(id: UUID(), kind: .walking, start: .now, end: .now, exerciseMinutes: 5)
        var run = walk
        run.kind = .running
        #expect(walk.isLeftOut(by: ring))
        #expect(!run.isLeftOut(by: ring))
    }
}
