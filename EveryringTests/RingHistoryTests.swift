import Foundation
import Testing
@testable import Everyring

struct RingHistoryTests {
    let cph = makeCalendar()
    // Wednesday 18 November 2026, 15:00.
    var now: Date { date(2026, 11, 18, 15, in: cph) }

    func ring(_ period: RingPeriod, goal: Double) -> Ring {
        var ring = Ring.new(metric: .steps)
        ring.period = period
        ring.goal = goal
        return ring
    }

    /// Daily values keyed by day of November 2026.
    func daily(_ values: [Int: Double]) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: values.map { (date(2026, 11, $0.key, in: cph), $0.value) })
    }

    @Test func sumCountsWholeDaysInInterval() {
        let values = daily([16: 1, 17: 2, 18: 4, 19: 8])
        let interval = DateInterval(start: date(2026, 11, 16, in: cph), end: date(2026, 11, 19, in: cph))
        #expect(RingHistory.sum(values, in: interval, calendar: cph) == 7)
        // A live window ending now still includes today.
        let live = DateInterval(start: date(2026, 11, 17, in: cph), end: now)
        #expect(RingHistory.sum(values, in: live, calendar: cph) == 6)
    }

    @Test func dailyRingHistoryAndStreak() {
        let r = ring(.today, goal: 10)
        let history = RingHistory.make(for: r, daily: daily([18: 4, 17: 12, 16: 10, 15: 3, 14: 11, 13: 11, 12: 11]),
                                       now: now, calendar: cph)
        #expect(history.streak == Streak(current: 2, best: 3))
        #expect(history.periods.count == RingHistory.shownCount(for: .today))
        #expect(history.periods[0].isCurrent)
        #expect(history.periods[0].value == 4)
        #expect(!history.periods[0].closed)
        #expect(history.periods[1].interval.start == date(2026, 11, 17, in: cph))
        #expect(history.periods[1].closed)
        #expect(history.days.isEmpty)
    }

    @Test func weeklyRingSumsDays() {
        let r = ring(.thisWeek, goal: 20)
        // Week of 16 Nov: 5 + 6; week of 9 Nov: 10 + 15.
        let history = RingHistory.make(for: r, daily: daily([16: 5, 18: 6, 9: 10, 13: 15]), now: now, calendar: cph)
        #expect(history.periods[0].value == 11)
        #expect(history.periods[1].value == 25)
        #expect(history.periods[1].closed)
        #expect(history.streak == Streak(current: 1, best: 1))
    }

    @Test func rollingRingDaysEndWithToday() {
        let r = ring(.rollingDays(3), goal: 60)
        let values = daily([10: 30, 11: 30, 14: 60, 17: 30, 18: 30])
        let history = RingHistory.make(for: r, daily: values, now: now, calendar: cph)
        #expect(history.days.count == RingHistory.shownCount(for: .rollingDays(3)))
        #expect(history.days.last?.day == date(2026, 11, 18, in: cph))
        #expect(history.days.last?.value == 60)
        // Window ending the 17th: 15–17 = 30.
        #expect(history.days[history.days.count - 2].value == 30)
        #expect(history.days.map(\.day) == history.days.map(\.day).sorted())
        #expect(history.streak.current == 1)
        #expect(history.periods.isEmpty)
    }

    @Test func requiredStartCoversStreakLookback() {
        let r = ring(.thisWeek, goal: 1)
        let start = RingHistory.requiredStart(for: r, now: now, calendar: cph)
        // 26 finished weeks before the week of 16 Nov.
        #expect(start == cph.date(byAdding: .day, value: -26 * 7, to: date(2026, 11, 16, in: cph)))
    }

    @Test func labels() {
        let day = RingPeriod.today.interval(containing: now, calendar: cph)
        #expect(RingPeriod.today.label(for: day, calendar: cph).contains("18"))
        let month = RingPeriod.thisMonth.interval(containing: now, calendar: cph)
        #expect(RingPeriod.thisMonth.label(for: month, calendar: cph).contains("2026"))
        let week = RingPeriod.thisWeek.interval(containing: now, calendar: cph)
        let label = RingPeriod.thisWeek.label(for: week, calendar: cph)
        #expect(label.contains("16") && label.contains("22"))
    }

    @Test func demoValuesAreStable() {
        let r = ring(.today, goal: 10_000)
        let a = DemoHistory.daily(for: r, from: date(2026, 11, 1, in: cph), to: now, calendar: cph)
        let b = DemoHistory.daily(for: r, from: date(2026, 11, 1, in: cph), to: now, calendar: cph)
        #expect(a == b)
        #expect(a.count == 18)
        #expect(a.values.allSatisfy { $0 >= 4_500 && $0 <= 15_500 })
    }
}

struct PerDayMathTests {
    let cph = makeCalendar()

    @Test func coveredSplitsAtMidnight() {
        let late = DateInterval(start: date(2026, 11, 17, 23, 30, in: cph), end: date(2026, 11, 18, 0, 20, in: cph))
        let byDay = IntervalMath.coveredByDay([late], calendar: cph)
        #expect(byDay[date(2026, 11, 17, in: cph)] == TimeInterval(30 * 60))
        #expect(byDay[date(2026, 11, 18, in: cph)] == TimeInterval(20 * 60))
    }

    @Test func nightsCountOnWakeUpDay() {
        let night = [DateInterval(start: date(2026, 11, 17, 23, in: cph), end: date(2026, 11, 18, 2, in: cph)),
                     DateInterval(start: date(2026, 11, 18, 2, 30, in: cph), end: date(2026, 11, 18, 7, in: cph))]
        let byDay = IntervalMath.asleepByDay(night, calendar: cph)
        #expect(byDay[date(2026, 11, 18, in: cph)] == 7.5 * 3600)
        #expect(byDay[date(2026, 11, 17, in: cph)] == nil)
    }
}
