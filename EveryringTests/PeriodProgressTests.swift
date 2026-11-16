import Foundation
import Testing
@testable import Everyring

struct PeriodProgressTests {
    let cph = makeCalendar()

    func ring(_ period: RingPeriod, goal: Double = 100) -> Ring {
        var ring = Ring.new(metric: .steps)
        ring.period = period
        ring.goal = goal
        return ring
    }

    @Test func todayIsHourlyAndRunsUntilNow() {
        let now = date(2026, 11, 18, 3, 30, in: cph)
        let buckets = [date(2026, 11, 18, 1, in: cph): 10.0, date(2026, 11, 18, 3, in: cph): 5]
        let progress = PeriodProgress.make(for: ring(.today), buckets: buckets, now: now, calendar: cph)
        #expect(progress.bucket == .hour)
        #expect(progress.points.map(\.total) == [0, 0, 10, 10, 15])
        #expect(progress.points.last?.date == now)
        #expect(progress.interval.end == date(2026, 11, 19, in: cph))
        // 3.5 of 24 hours.
        #expect(abs((progress.paceNow ?? 0) - 100 * 3.5 / 24) < 0.0001)
    }

    @Test func weekIsDailyAndSpansTheWholeWeek() {
        let now = date(2026, 11, 18, 12, in: cph)  // Wednesday
        let buckets = [date(2026, 11, 16, in: cph): 20.0, date(2026, 11, 17, in: cph): 30, date(2026, 11, 18, in: cph): 5]
        let progress = PeriodProgress.make(for: ring(.thisWeek), buckets: buckets, now: now, calendar: cph)
        #expect(progress.bucket == .day)
        #expect(progress.points.map(\.total) == [0, 20, 50, 55])
        #expect(progress.interval.start == date(2026, 11, 16, in: cph))
        #expect(progress.interval.end == date(2026, 11, 23, in: cph))
    }

    @Test func rollingWindowHasNoPace() {
        let now = date(2026, 11, 18, 12, in: cph)
        let progress = PeriodProgress.make(for: ring(.rollingDays(3)), buckets: [:], now: now, calendar: cph)
        #expect(progress.paceNow == nil)
        #expect(progress.interval.start == date(2026, 11, 16, in: cph))
        #expect(progress.points.count == 4)
    }

    @Test func demoHoursAddUp() {
        let now = date(2026, 11, 18, 15, in: cph)
        let hourly = DemoHistory.hourly(total: 7_200, from: date(2026, 11, 18, in: cph), to: now, calendar: cph)
        #expect(abs(hourly.values.reduce(0, +) - 7_200) < 0.001)
        #expect(hourly.keys.allSatisfy { (7...14).contains(cph.component(.hour, from: $0)) })
    }

    @Test func pastWeekRunsToItsEnd() {
        let now = date(2026, 11, 18, 12, in: cph)
        let lastWeek = DateInterval(start: date(2026, 11, 9, in: cph), end: date(2026, 11, 16, in: cph))
        let buckets = [date(2026, 11, 9, in: cph): 40.0, date(2026, 11, 15, in: cph): 70]
        let progress = PeriodProgress.make(for: ring(.thisWeek), buckets: buckets, interval: lastWeek, now: now,
                                           calendar: cph)
        #expect(progress.isPast)
        #expect(progress.points.count == 8)
        #expect(progress.points.last?.total == 110)
        #expect(progress.points.last?.date == lastWeek.end)
        #expect(progress.paceNow == 100)
    }

    @Test func currentPeriodIsNotPast() {
        let now = date(2026, 11, 18, 12, in: cph)
        #expect(!PeriodProgress.make(for: ring(.thisWeek), buckets: [:], now: now, calendar: cph).isPast)
    }
}

struct DailyPaceTests {
    let cph = makeCalendar()

    func ring(_ period: RingPeriod, goal: Double = 70, kind: GoalKind = .reach) -> Ring {
        var ring = Ring.new(metric: .walkingRunningDistance)
        ring.period = period
        ring.goal = goal
        ring.goalKind = kind
        return ring
    }

    @Test func weekInProgress() {
        let now = date(2026, 11, 18, 12, in: cph)  // Wednesday: 3 days gone incl. today, 5 left incl. today
        let r = ring(.thisWeek)
        let pace = DailyPace.make(for: r, value: 30, interval: r.period.interval(now: now, calendar: cph), now: now,
                                  calendar: cph)
        #expect(pace?.days == 3)
        #expect(pace?.average == 10)
        #expect(pace?.daysLeft == 5)
        #expect(pace?.perDayLeft == 8)
    }

    @Test func finishedWeekAveragesAllDays() {
        let now = date(2026, 11, 18, 12, in: cph)
        let r = ring(.thisWeek)
        let lastWeek = DateInterval(start: date(2026, 11, 9, in: cph), end: date(2026, 11, 16, in: cph))
        let pace = DailyPace.make(for: r, value: 84, interval: lastWeek, now: now, calendar: cph)
        #expect(pace?.days == 7)
        #expect(pace?.average == 12)
        #expect(pace?.perDayLeft == nil)
    }

    @Test func rollingAveragesTheWindowAndOneDayHasNone() {
        let now = date(2026, 11, 18, 12, in: cph)
        let rolling = ring(.rollingDays(7))
        let pace = DailyPace.make(for: rolling, value: 70, interval: rolling.period.interval(now: now, calendar: cph),
                                  now: now, calendar: cph)
        #expect(pace?.days == 7)
        #expect(pace?.perDayLeft == nil)
        let today = ring(.today)
        #expect(DailyPace.make(for: today, value: 5, interval: today.period.interval(now: now, calendar: cph), now: now,
                               calendar: cph) == nil)
    }

    @Test func limitShowsWhatIsLeft() {
        let now = date(2026, 11, 18, 12, in: cph)
        let r = ring(.thisWeek, goal: 100, kind: .limit)
        let pace = DailyPace.make(for: r, value: 50, interval: r.period.interval(now: now, calendar: cph), now: now,
                                  calendar: cph)
        #expect(pace?.perDayLeft == 10)
        let over = DailyPace.make(for: r, value: 120, interval: r.period.interval(now: now, calendar: cph), now: now,
                                  calendar: cph)
        #expect(over?.perDayLeft == nil)
    }
}
