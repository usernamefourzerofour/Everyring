import Foundation
import Testing
@testable import Everyring

struct HistoryPageTests {
    let cph = makeCalendar()
    var now: Date { date(2026, 11, 18, 15, in: cph) }

    func ring(_ period: RingPeriod, goal: Double = 10) -> Ring {
        var ring = Ring.new(metric: .steps)
        ring.period = period
        ring.goal = goal
        return ring
    }

    @Test func monthPagesAndYearPages() {
        let october = HistoryPage.range(for: .today, offset: -1, now: now, calendar: cph)
        #expect(october.start == date(2026, 10, 1, in: cph))
        #expect(october.end == date(2026, 11, 1, in: cph))
        let lastYear = HistoryPage.range(for: .thisMonth, offset: -1, now: now, calendar: cph)
        #expect(lastYear.start == date(2025, 1, 1, in: cph))
        #expect(HistoryPage.unit(for: .thisMonth) == .year)
        #expect(HistoryPage.unit(for: .rollingDays(7)) == .month)
    }

    @Test func dailyPageStopsAtToday() {
        let r = ring(.today)
        let range = HistoryPage.range(for: .today, offset: 0, now: now, calendar: cph)
        let page = HistoryPage.make(for: r, daily: [date(2026, 11, 18, in: cph): 12], range: range, now: now, calendar: cph)
        #expect(page.periods.count == 18)
        #expect(page.periods.first?.isCurrent == true)
        #expect(page.periods.first?.closed == true)
        #expect(page.periods.last?.interval.start == date(2026, 11, 1, in: cph))
    }

    @Test func pastMonthHasAllDays() {
        let r = ring(.today)
        let range = HistoryPage.range(for: .today, offset: -9, now: now, calendar: cph)  // February 2026
        let page = HistoryPage.make(for: r, daily: [:], range: range, now: now, calendar: cph)
        #expect(page.periods.count == 28)
        #expect(page.periods.allSatisfy { !$0.isCurrent && !$0.closed })
    }

    @Test func weeklyPageIncludesWeeksOverlappingTheMonth() {
        let r = ring(.thisWeek)
        let range = HistoryPage.range(for: .thisWeek, offset: -1, now: now, calendar: cph)  // October 2026
        let page = HistoryPage.make(for: r, daily: [:], range: range, now: now, calendar: cph)
        // Weeks starting 28 Sep, 5, 12, 19 and 26 Oct.
        #expect(page.periods.map(\.interval.start) == [26, 19, 12, 5].map { date(2026, 10, $0, in: cph) }
            + [date(2026, 9, 28, in: cph)])
    }

    @Test func rollingPageUsesWindowsAndNeedsEarlierDays() {
        let r = ring(.rollingDays(3), goal: 60)
        let range = HistoryPage.range(for: r.period, offset: 0, now: now, calendar: cph)
        #expect(HistoryPage.requiredStart(for: r, range: range, now: now, calendar: cph) == date(2026, 10, 30, in: cph))
        let daily = [date(2026, 10, 31, in: cph): 30.0, date(2026, 11, 1, in: cph): 30.0]
        let page = HistoryPage.make(for: r, daily: daily, range: range, now: now, calendar: cph)
        #expect(page.days.count == 18)
        #expect(page.days.first?.value == 60)  // 30 Oct – 1 Nov
        #expect(page.days.last?.day == date(2026, 11, 18, in: cph))
    }

    @Test func titles() {
        let month = HistoryPage(range: HistoryPage.range(for: .today, offset: 0, now: now, calendar: cph))
        #expect(month.title(calendar: cph).contains("2026"))
        #expect(month.title(calendar: cph).count > 4)
        let year = HistoryPage(range: HistoryPage.range(for: .thisMonth, offset: 0, now: now, calendar: cph))
        #expect(year.title(calendar: cph) == "2026")
    }
}

struct MoreMetricsTests {
    let us = Locale(identifier: "en_US")

    @Test func everyNewTypeIsListed() {
        let all = HealthMetric.Category.allCases.flatMap(\.metrics)
        for kind in QuantityKind.allCases { #expect(all.contains(.quantity(kind))) }
        for kind in EventKind.allCases { #expect(all.contains(.events(kind))) }
    }

    @Test func formats() {
        #expect(HealthMetric.quantity(.protein).format(42, locale: us) == "42 g")
        #expect(HealthMetric.quantity(.caffeine).format(95, locale: us) == "95 mg")
        #expect(HealthMetric.quantity(.wheelchairPushes).format(1200, locale: us) == "1,200 pushes")
        #expect(HealthMetric.events(.toothbrushing).formatProgress(1, goal: 2, locale: us) == "1 of 2 times")
    }

    @Test func suggestedGoals() {
        #expect(HealthMetric.quantity(.protein).suggestedGoal(for: .today, locale: us) == 60)
        #expect(HealthMetric.events(.toothbrushing).suggestedGoal(for: .today, locale: us) == 2)
        #expect(HealthMetric.quantity(.restingEnergy).suggestedGoal(for: .today, locale: us) == 1_500)
    }

    @Test func codableRoundTrip() throws {
        let metrics: [HealthMetric] = [.quantity(.fiber), .events(.handwashing), .workouts(.minutes, kind: .tennis)]
        let data = try JSONEncoder().encode(metrics)
        #expect(try JSONDecoder().decode([HealthMetric].self, from: data) == metrics)
    }
}
