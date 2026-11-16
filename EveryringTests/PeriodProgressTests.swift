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
