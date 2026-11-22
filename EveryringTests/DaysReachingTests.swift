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
        for key in ["dailyTarget", "days", "leftOutWorkouts", "sources", "minimumWorkoutMinutes"] { json.removeValue(forKey: key) }
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
