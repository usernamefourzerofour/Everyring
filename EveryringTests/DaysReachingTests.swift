import Foundation
import Testing
@testable import Everyring

struct DaysReachingTests {
    let cph = makeCalendar()

    func steps(_ period: RingPeriod = .thisWeek, days: DayFilter = .everyDay) -> Ring {
        Ring(name: "Steps", color: .fern, symbol: "figure.walk", metric: .steps, goal: 5, period: period,
             aggregation: .daysReaching, dailyTarget: 10_000, days: days)
    }

    func values(_ map: [Int: Double]) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: map.map { (date(2026, 11, $0.key, in: cph), $0.value) })
    }

    @Test func countsDaysThatReachTheTarget() {
        // Wednesday 18 November; the week started Monday the 16th.
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = steps()
        #expect(ring.isDaysReaching && ring.needsDailyValues && !ring.isLimit)
        let week = ring.period.interval(now: now, calendar: cph)
        let daily = values([16: 12_000, 17: 8_000, 18: 10_500])
        #expect(ring.measure(daily: daily, in: week, now: now, calendar: cph) == 2)
        #expect(!ring.isMet(2))
        #expect(ring.isMet(5))
        #expect(ring.progressText(2) == "2 of 5 days")
    }

    @Test func limitDaysOnlyCountOnceOver() {
        let now = date(2026, 11, 18, 15, in: cph)
        var ring = steps()
        ring.goalKind = .limit
        ring.dailyTarget = 2_000
        let week = ring.period.interval(now: now, calendar: cph)
        // Monday under, Tuesday over, today under so far (could still go over).
        let daily = values([16: 1_800, 17: 2_400, 18: 900])
        #expect(ring.measure(daily: daily, in: week, now: now, calendar: cph) == 1)
        // The ring counts days up to its goal, so it never turns red.
        #expect(!ring.isOverLimit(9))
    }

    @Test func oneDayPeriodCannotCountDays() {
        #expect(!steps(.today).isDaysReaching)
        #expect(steps(.today).effectiveDays == .everyDay)
    }

    @Test func weekdaysLeaveOutTheWeekend() {
        // Sunday 22 November: a whole Monday–Sunday week.
        let now = date(2026, 11, 22, 20, in: cph)
        var ring = steps(days: .weekdays)
        ring.aggregation = .total
        let week = ring.period.interval(now: now, calendar: cph)
        let daily = values([16: 1, 17: 1, 18: 1, 19: 1, 20: 1, 21: 100, 22: 100])
        #expect(ring.needsDailyValues)
        #expect(ring.measure(daily: daily, in: week, now: now, calendar: cph) == 5)
        ring.days = .weekends
        #expect(ring.measure(daily: daily, in: week, now: now, calendar: cph) == 200)
        // An average over weekdays divides by the weekdays.
        ring.days = .weekdays
        ring.aggregation = .dailyAverage
        #expect(ring.measure(daily: daily, in: week, now: now, calendar: cph) == 1)
    }

    @Test func chartCountsReachedDays() {
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = steps()
        let buckets = values([16: 12_000, 17: 8_000, 18: 10_500])
        let progress = PeriodProgress.make(for: ring, buckets: buckets, now: now, calendar: cph)
        #expect(progress.points.map(\.total) == [0, 1, 1, 2])
    }

    @Test func historyAndStreakUseDays() {
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = steps()
        var map: [Int: Double] = [:]
        for day in 9...18 { map[day] = 11_000 }
        let history = RingHistory.make(for: ring, daily: values(map), now: now, calendar: cph)
        #expect(history.periods[0].value == 3)
        #expect(history.periods[1].value == 7)
        #expect(history.periods[1].closed)
    }

    @Test func newSettingsDecodeWithDefaults() throws {
        let ring = Ring(name: "Steps", color: .fern, symbol: "figure.walk", metric: .steps, goal: 10_000, period: .today)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ring)) as! [String: Any]
        for key in ["dailyTarget", "days", "leftOutWorkouts", "sources", "minimumWorkoutMinutes", "maximumWorkoutMinutes"] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(Ring.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == ring)
        var full = steps(days: .weekdays)
        full.sources = ["com.example.app"]
        full.leftOutWorkouts = [.walking]
        #expect(try JSONDecoder().decode(Ring.self, from: JSONEncoder().encode(full)) == full)
    }
}

struct SleepStageTests {
    let cph = makeCalendar()

    @Test func stagesCountOnTheNightTheyBelongTo() {
        func t(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { date(2026, 11, d, h, m, in: cph) }
        // One night 23:00–07:00 with deep sleep before and after midnight, and a 1.5-hour awake gap.
        let asleep = [DateInterval(start: t(17, 23), end: t(18, 2)), DateInterval(start: t(18, 3, 30), end: t(18, 7))]
        let deep = [DateInterval(start: t(17, 23, 30), end: t(18, 0, 30)), DateInterval(start: t(18, 4), end: t(18, 4, 30))]
        let byDay = IntervalMath.stageByDay(deep, asleep: asleep, calendar: cph)
        #expect(byDay == [date(2026, 11, 18, in: cph): 90 * 60])
        let day = DateInterval(start: date(2026, 11, 18, in: cph), end: date(2026, 11, 19, in: cph))
        #expect(IntervalMath.stage(deep, asleep: asleep, attributedTo: day) == 90 * 60)
    }

    @Test func stageMetrics() {
        #expect(HealthMetric.sleepStage(.deep).title == "Deep sleep")
        #expect(HealthMetric.sleepStage(.rem).baseUnit == .hours)
        #expect(HealthMetric.sleepStage(.core).category == .recovery)
        #expect(!HealthMetric.sleepStage(.deep).hasHourlyBuildUp)
    }
}

struct SensitiveMetricTests {
    @Test func sensitiveTypesAreListedButFlagged() {
        let all = HealthMetric.Category.allCases.flatMap(\.metrics)
        for kind in SensitiveKind.allCases { #expect(all.contains(.sensitive(kind))) }
        #expect(HealthMetric.Category.medical.isSensitive)
        #expect(!HealthMetric.Category.activity.isSensitive)
    }

    @Test func formats() {
        let us = Locale(identifier: "en_US")
        #expect(HealthMetric.sensitive(.insulinDelivery).format(12.5, locale: us) == "12.5 IU")
        #expect(HealthMetric.sensitive(.headache).format(2, locale: us) == "2 times")
        #expect(HealthMetric.sensitive(.headache).defaultGoalKind == .limit)
        #expect(HealthMetric.sensitive(.menstrualFlow).format(4, locale: us) == "4 days")
    }
}

struct LoggedNightTests {
    let cph = makeCalendar()

    @Test func nightsWithStages() {
        func t(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { date(2026, 11, d, h, m, in: cph) }
        let samples: [(interval: DateInterval, stage: SleepStage?)] = [
            (DateInterval(start: t(17, 23), end: t(18, 1)), .core),
            (DateInterval(start: t(18, 1), end: t(18, 2)), .deep),
            // 30 minutes awake
            (DateInterval(start: t(18, 2, 30), end: t(18, 6)), .rem),
            // The next night
            (DateInterval(start: t(18, 22), end: t(19, 6)), nil),
        ]
        let nights = LoggedNight.make(samples)
        #expect(nights.count == 2)
        let first = nights[0]
        #expect(first.day(calendar: cph) == date(2026, 11, 18, in: cph))
        #expect(first.asleep == 6.5 * 3600)
        #expect(first.awake == 30 * 60)
        #expect(first.stages[.deep] == 3600)
        #expect(first.hours(for: .sleepStage(.rem)) == 3.5)
        #expect(nights[1].unspecified == 8 * 3600)
    }

    @Test func dailyGoalMarksNights() {
        var ring = Ring(name: "Sleep", color: .indigo, symbol: "bed.double", metric: .sleep, goal: 56, period: .thisWeek)
        #expect(ring.dailyGoal == nil)
        ring.aggregation = .dailyAverage
        ring.goal = 8
        #expect(ring.dayIsMet(7.5) == false)
        #expect(ring.dayIsMet(8.2) == true)
    }
}

struct WorkoutTimelineTests {
    @Test func heartRateSummary() {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var timeline = WorkoutTimeline()
        #expect(timeline.isEmpty && timeline.averageHeartRate == nil)
        timeline.heartRate = [.init(date: t0, value: 100), .init(date: t0 + 30, value: 140), .init(date: t0 + 60, value: 150)]
        #expect(timeline.averageHeartRate == 130)
        #expect(timeline.maxHeartRate == 150)
        #expect(!timeline.isEmpty)
    }

    @Test func demoTimelineFollowsTheWorkout() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let workout = LoggedWorkout(id: UUID(), kind: .running, start: start, end: start + 30 * 60, value: 300)
        let timeline = DemoHistory.timeline(for: workout)
        #expect(timeline.perMinute.count == 30)
        #expect(timeline.heartRate.count == 60)
        #expect(timeline.perMinute.allSatisfy { $0.date >= workout.start && $0.date < workout.end })
    }
}

struct ActivitySplitTests {
    @Test func everydayIsTheRest() {
        let split = ActivitySplit(total: 200, duringWorkouts: 80)
        #expect(split.everyday == 120)
        #expect(split.workoutShare == 0.4)
        #expect(ActivitySplit().workoutShare == 0)
        // Statistics can round so workouts exceed the total by a hair: never below zero or above 100 %.
        #expect(ActivitySplit(total: 10, duringWorkouts: 10.2).everyday == 0)
        #expect(ActivitySplit(total: 10, duringWorkouts: 10.2).workoutShare == 1)
    }
}

struct PaceTextTests {
    let us = Locale(identifier: "en_US")

    @Test func oneIsSingular() {
        #expect(HealthMetric.workouts(.count, kind: nil).format(1, locale: us) == "1 workout")
        #expect(HealthMetric.workouts(.count, kind: nil).format(2, locale: us) == "2 workouts")
        #expect(HealthMetric.steps.format(1, locale: us) == "1 step")
        #expect(HealthMetric.workouts(.count, kind: nil).formatProgress(0, goal: 1, locale: us) == "0 of 1 workout")
        // Rates keep a decimal for small counts.
        #expect(HealthMetric.workouts(.count, kind: nil).formatPerDay(2.0 / 7, locale: us) == "0.3 workouts")
        #expect(HealthMetric.workouts(.count, kind: nil).formatPerDay(1, locale: us) == "1 workout")
        #expect(HealthMetric.steps.formatPerDay(8_412, locale: us) == "8,412 steps")
    }

    @Test func lastDayNeedsWhatIsLeft() {
        let cph = makeCalendar()
        // Sunday afternoon: the last day of a Monday–Sunday week.
        let now = date(2026, 11, 22, 9, 43, in: cph)
        let ring = Ring(name: "Workouts", color: .indigo, symbol: "dumbbell", metric: .workouts(.count, kind: nil),
                        goal: 3, period: .thisWeek)
        let week = ring.period.interval(now: now, calendar: cph)
        let pace = DailyPace.make(for: ring, value: 2, interval: week, now: now, calendar: cph)
        #expect(pace?.daysLeft == 1)
        #expect(pace?.remaining == 1)
    }
}

struct FadedRingTests {
    @Test func closedRingsFadeOnlyWhenAsked() {
        let steps = Ring(name: "Steps", color: .fern, symbol: "figure.walk", metric: .steps, goal: 10_000, period: .today)
        #expect(!steps.display(12_000).faded)
        #expect(steps.display(12_000, fadesWhenClosed: true).faded)
        #expect(!steps.display(8_000, fadesWhenClosed: true).faded)
        var limit = steps
        limit.goalKind = .limit
        #expect(!limit.display(500, fadesWhenClosed: true).faded)
    }

    @Test func oldLibrariesDecodeWithoutTheSetting() throws {
        let json = #"{"sets":[],"weekStart":"system"}"#
        let library = try JSONDecoder().decode(RingLibrary.self, from: Data(json.utf8))
        #expect(!library.fadesClosedRings)
        let faded = RingLibrary(sets: [], fadesClosedRings: true)
        #expect(try JSONDecoder().decode(RingLibrary.self, from: JSONEncoder().encode(faded)).fadesClosedRings)
    }
}
