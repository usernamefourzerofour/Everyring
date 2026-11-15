import Foundation
import Testing
@testable import Everyring

/// Gregorian calendar in a fixed time zone with a fixed week start, so the tests don't depend on the simulator.
func makeCalendar(_ zone: String = "Europe/Copenhagen", firstWeekday: Int = 2) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = firstWeekday
    return calendar
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct WeekStartTests {
    // Wednesday 18 November 2026, 15:00.
    let cph = makeCalendar()

    @Test(arguments: [
        (WeekStart.monday, 16, 23),
        (WeekStart.sunday, 15, 22),
        (WeekStart.saturday, 14, 21),
    ])
    func weekBoundaries(start: WeekStart, firstDay: Int, nextFirstDay: Int) {
        let calendar = start.calendar(cph)
        let week = RingPeriod.thisWeek.interval(containing: date(2026, 11, 18, 15, in: cph), calendar: calendar)
        #expect(week.start == date(2026, 11, firstDay, in: cph))
        #expect(week.end == date(2026, 11, nextFirstDay, in: cph))
    }

    @Test func systemKeepsRegionWeekStart() {
        let us = makeCalendar("America/New_York", firstWeekday: 1)
        #expect(WeekStart.system.calendar(us).firstWeekday == 1)
        #expect(WeekStart.monday.calendar(us).firstWeekday == 2)
        #expect(WeekStart.monday.calendar(us).timeZone == us.timeZone)
    }

    @Test func weekOnSaturdayStartsThatDay() {
        let calendar = WeekStart.saturday.calendar(cph)
        let week = RingPeriod.thisWeek.interval(containing: date(2026, 11, 14, 0, 30, in: cph), calendar: calendar)
        #expect(week.start == date(2026, 11, 14, in: cph))
    }
}

struct FixedPeriodTests {
    let cph = makeCalendar()

    @Test func todayIsWholeDay() {
        let day = RingPeriod.today.interval(now: date(2026, 11, 18, 15, in: cph), calendar: cph)
        #expect(day.start == date(2026, 11, 18, in: cph))
        #expect(day.end == date(2026, 11, 19, in: cph))
    }

    @Test func todayOnDSTDaysIs23Or25Hours() {
        let spring = RingPeriod.today.interval(containing: date(2026, 3, 29, 12, in: cph), calendar: cph)
        #expect(spring.duration == 23 * 3600)
        let autumn = RingPeriod.today.interval(containing: date(2026, 10, 25, 12, in: cph), calendar: cph)
        #expect(autumn.duration == 25 * 3600)
    }

    @Test func weekAcrossDSTEndsAtMidnight() {
        let week = RingPeriod.thisWeek.interval(containing: date(2026, 10, 22, in: cph), calendar: cph)
        #expect(week.start == date(2026, 10, 19, in: cph))
        #expect(week.end == date(2026, 10, 26, in: cph))
        #expect(week.duration == 7 * 86_400 + 3600)
    }

    @Test(arguments: [(2026, 2, 28), (2028, 2, 29), (2026, 4, 30), (2026, 12, 31)])
    func monthLengths(year: Int, month: Int, days: Int) {
        let interval = RingPeriod.thisMonth.interval(containing: date(year, month, 10, in: cph), calendar: cph)
        #expect(interval.start == date(year, month, 1, in: cph))
        #expect(cph.dateComponents([.day], from: interval.start, to: interval.end).day == days)
    }

    @Test func previousAndNextMonth() {
        let march = RingPeriod.thisMonth.interval(containing: date(2026, 3, 15, in: cph), calendar: cph)
        let february = RingPeriod.thisMonth.previous(march, calendar: cph)
        #expect(february.start == date(2026, 2, 1, in: cph))
        #expect(february.end == march.start)

        let december = RingPeriod.thisMonth.interval(containing: date(2026, 12, 31, 23, 59, in: cph), calendar: cph)
        let january = RingPeriod.thisMonth.next(december, calendar: cph)
        #expect(january.start == date(2027, 1, 1, in: cph))
    }

    @Test func previousWeekAcrossDST() {
        let week = RingPeriod.thisWeek.interval(containing: date(2026, 10, 28, in: cph), calendar: cph)
        let previous = RingPeriod.thisWeek.previous(week, calendar: cph)
        #expect(previous.start == date(2026, 10, 19, in: cph))
        #expect(previous.end == week.start)
    }

    @Test func everyThreeDaysFromAnchor() {
        // Anchor time of day doesn't matter: periods start at midnight.
        let period = RingPeriod.everyDays(3, from: date(2026, 1, 5, 10, 30, in: cph))
        let first = period.interval(containing: date(2026, 1, 7, 23, in: cph), calendar: cph)
        #expect(first.start == date(2026, 1, 5, in: cph))
        #expect(first.end == date(2026, 1, 8, in: cph))

        let second = period.interval(containing: date(2026, 1, 8, in: cph), calendar: cph)
        #expect(second.start == date(2026, 1, 8, in: cph))
        #expect(period.next(first, calendar: cph) == second)
        #expect(period.previous(second, calendar: cph) == first)
    }

    @Test func everyDaysBeforeAnchorUsesEarlierPeriod() {
        let period = RingPeriod.everyDays(3, from: date(2026, 1, 5, in: cph))
        let interval = period.interval(containing: date(2026, 1, 4, 12, in: cph), calendar: cph)
        #expect(interval.start == date(2026, 1, 2, in: cph))
        #expect(interval.end == date(2026, 1, 5, in: cph))
    }

    @Test func everyTwoWeeksFromMonday5January() {
        let period = RingPeriod.everyWeeks(2, from: date(2026, 1, 5, in: cph))
        let interval = period.interval(containing: date(2026, 1, 21, in: cph), calendar: cph)
        #expect(interval.start == date(2026, 1, 19, in: cph))
        #expect(interval.end == date(2026, 2, 2, in: cph))
    }

    @Test func everyWeeksIgnoresWeekStartSetting() {
        // A Thursday anchor keeps Thursday boundaries even with a Monday week start.
        let period = RingPeriod.everyWeeks(1, from: date(2026, 11, 12, in: cph))
        let interval = period.interval(containing: date(2026, 11, 18, in: cph), calendar: cph)
        #expect(interval.start == date(2026, 11, 12, in: cph))
        #expect(interval.end == date(2026, 11, 19, in: cph))
    }

    @Test func customPeriodAcrossDSTStaysOnMidnight() {
        let period = RingPeriod.everyDays(2, from: date(2026, 3, 28, in: cph))
        let interval = period.interval(containing: date(2026, 3, 29, 12, in: cph), calendar: cph)
        #expect(interval.start == date(2026, 3, 28, in: cph))
        #expect(interval.end == date(2026, 3, 30, in: cph))
        #expect(interval.duration == 47 * 3600)
        let next = period.next(interval, calendar: cph)
        #expect(next.start == date(2026, 3, 30, in: cph))
        #expect(next.duration == 48 * 3600)
    }

    @Test func invalidCountIsTreatedAsOne() {
        let interval = RingPeriod.everyDays(0, from: date(2026, 1, 1, in: cph))
            .interval(containing: date(2026, 1, 10, 9, in: cph), calendar: cph)
        #expect(interval.start == date(2026, 1, 10, in: cph))
        #expect(interval.end == date(2026, 1, 11, in: cph))
    }

    @Test func todayDependsOnTimeZone() {
        let tokyo = makeCalendar("Asia/Tokyo")
        let newYork = makeCalendar("America/New_York")
        let instant = date(2026, 11, 18, 20, in: newYork) // 19 Nov 10:00 in Tokyo
        #expect(RingPeriod.today.interval(containing: instant, calendar: newYork).start == date(2026, 11, 18, in: newYork))
        #expect(RingPeriod.today.interval(containing: instant, calendar: tokyo).start == date(2026, 11, 19, in: tokyo))
    }

    @Test func historyIsNewestFirst() {
        let now = date(2026, 11, 18, 15, in: cph)
        let weeks = RingPeriod.thisWeek.history(now: now, count: 3, calendar: cph)
        #expect(weeks.map(\.start) == [date(2026, 11, 9, in: cph), date(2026, 11, 2, in: cph), date(2026, 10, 26, in: cph)])
    }
}

struct RollingPeriodTests {
    let cph = makeCalendar()

    @Test func liveWindowEndsNow() {
        let now = date(2026, 11, 18, 15, in: cph)
        let window = RingPeriod.rollingDays(7).interval(now: now, calendar: cph)
        #expect(window.start == date(2026, 11, 12, in: cph))
        #expect(window.end == now)
    }

    @Test func wholeWindowEndsAtMidnight() {
        let window = RingPeriod.rollingDays(7).interval(containing: date(2026, 11, 18, 15, in: cph), calendar: cph)
        #expect(window.start == date(2026, 11, 12, in: cph))
        #expect(window.end == date(2026, 11, 19, in: cph))
    }

    @Test func windowAcrossDSTCountsCalendarDays() {
        let window = RingPeriod.rollingDays(3).interval(containing: date(2026, 3, 30, 12, in: cph), calendar: cph)
        #expect(window.start == date(2026, 3, 28, in: cph))
        #expect(window.end == date(2026, 3, 31, in: cph))
        #expect(window.duration == 3 * 86_400 - 3600)
    }

    @Test func previousOfLiveWindowIsYesterdaysWindow() {
        let now = date(2026, 11, 18, 15, in: cph)
        let period = RingPeriod.rollingDays(7)
        let previous = period.previous(period.interval(now: now, calendar: cph), calendar: cph)
        #expect(previous.start == date(2026, 11, 11, in: cph))
        #expect(previous.end == date(2026, 11, 18, in: cph))
        #expect(period.next(previous, calendar: cph).end == date(2026, 11, 19, in: cph))
    }

    @Test func historyMovesOneDayAtATime() {
        let now = date(2026, 11, 18, 15, in: cph)
        let windows = RingPeriod.rollingDays(3).history(now: now, count: 2, calendar: cph)
        #expect(windows.map(\.end) == [date(2026, 11, 18, in: cph), date(2026, 11, 17, in: cph)])
        #expect(windows.map(\.start) == [date(2026, 11, 15, in: cph), date(2026, 11, 14, in: cph)])
    }
}

struct PeriodLabelTests {
    let cph = makeCalendar()

    @Test func titles() {
        #expect(RingPeriod.thisWeek.title == "This week")
        #expect(RingPeriod.rollingDays(7).title == "Last 7 days")
        #expect(RingPeriod.everyWeeks(2, from: .now).title == "Every 2 weeks")
        #expect(RingPeriod.everyDays(1, from: .now).title == "Every day")
    }

    @Test func statusShowsDaysLeftIncludingToday() {
        // Wednesday: Wed, Thu, Fri, Sat, Sun.
        #expect(RingPeriod.thisWeek.status(now: date(2026, 11, 18, 15, in: cph), calendar: cph) == "This week · 5 days left")
        #expect(RingPeriod.thisWeek.status(now: date(2026, 11, 22, 23, in: cph), calendar: cph) == "This week · Last day")
        #expect(RingPeriod.today.status(now: date(2026, 11, 18, in: cph), calendar: cph) == "Today")
        #expect(RingPeriod.rollingDays(7).status(now: date(2026, 11, 18, in: cph), calendar: cph) == "Last 7 days")
    }

    @Test func rollingHasNoDaysLeft() {
        #expect(RingPeriod.rollingDays(14).daysLeft(calendar: cph) == nil)
        #expect(RingPeriod.rollingDays(14).isRolling)
        #expect(!RingPeriod.thisMonth.isRolling)
    }
}

struct CodableTests {
    @Test func periodsRoundTrip() throws {
        let anchor = Date(timeIntervalSince1970: 1_767_571_200)
        let periods: [RingPeriod] = [.today, .thisWeek, .thisMonth, .everyDays(3, from: anchor),
                                     .everyWeeks(2, from: anchor), .rollingDays(7)]
        let data = try JSONEncoder().encode(periods)
        #expect(try JSONDecoder().decode([RingPeriod].self, from: data) == periods)
    }

    @Test func ringSetRoundTripsAndCapsAtFive() throws {
        let ring = Ring(name: "Running", color: .tangerine, symbol: "figure.run",
                        metric: .workouts(.distance, kind: .running), goal: 20_000, period: .thisWeek)
        var set = RingSet(name: "Weekly", rings: Array(repeating: ring, count: 7))
        #expect(set.rings.count == 5)
        #expect(!set.canAddRing)
        set.rings.append(ring)
        #expect(set.rings.count == 5)

        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(RingSet.self, from: data) == set)
    }
}
