import Foundation
import Testing
@testable import Everyring

struct StreakTests {
    @Test func empty() {
        #expect(Streak(finished: [], inProgress: false) == .zero)
        #expect(Streak(finished: [], inProgress: true) == Streak(current: 1, best: 1))
    }

    @Test func periodInProgressDoesNotBreakStreak() {
        #expect(Streak(finished: [true, true], inProgress: false) == Streak(current: 2, best: 2))
    }

    @Test func periodInProgressAddsWhenClosed() {
        #expect(Streak(finished: [true, true], inProgress: true) == Streak(current: 3, best: 3))
    }

    @Test func missedPeriodBreaksStreak() {
        // Newest first: last period missed.
        #expect(Streak(finished: [false, true, true, true], inProgress: false) == Streak(current: 0, best: 3))
        #expect(Streak(finished: [true, false, true, true, true], inProgress: true) == Streak(current: 2, best: 3))
    }

    @Test func bestCanBeCurrent() {
        #expect(Streak(finished: [true, true, true, false, true], inProgress: true) == Streak(current: 4, best: 4))
    }

    @Test func closedMeansReachingGoal() {
        #expect(Streak.isClosed(value: 10_000, goal: 10_000))
        #expect(!Streak.isClosed(value: 9_999, goal: 10_000))
        #expect(!Streak.isClosed(value: 5, goal: 0))
    }

    @Test func dailyStreakFromValues() {
        let calendar = makeCalendar()
        let now = date(2026, 11, 18, 15, in: calendar)
        // Steps per day; key = day of month in November.
        let steps: [Int: Double] = [18: 4_000, 17: 12_000, 16: 10_000, 15: 3_000, 14: 11_000, 13: 11_000, 12: 11_000]
        let streak = Streak.compute(period: .today, goal: 10_000, now: now, calendar: calendar, lookback: 10) { interval in
            steps[calendar.component(.day, from: interval.start)] ?? 0
        }
        #expect(streak == Streak(current: 2, best: 3))
    }

    @Test func rollingStreakChecksEachDaysWindow() {
        let calendar = makeCalendar()
        let now = date(2026, 11, 18, 15, in: calendar)
        // Minutes per day in November. Goal: 60 in the last 3 days.
        let minutes: [Int: Double] = [10: 30, 11: 30, 12: 0, 13: 0, 14: 60, 15: 0, 16: 0, 17: 30, 18: 30]
        func sum(_ interval: DateInterval) -> Double {
            var total = 0.0
            var day = interval.start
            while day < interval.end {
                total += minutes[calendar.component(.day, from: day)] ?? 0
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            return total
        }
        // Windows ending: 17th = 15–17 → 30 ✗; 16th = 14–16 → 60 ✓; 15th → 60 ✓; 14th → 60 ✓; 13th = 11–13 → 30 ✗;
        // 12th = 10–12 → 60 ✓; 11th = 9–11 → 60 ✓. Live window 16–18 → 60 ✓.
        let streak = Streak.compute(period: .rollingDays(3), goal: 60, now: now, calendar: calendar, lookback: 6, value: sum)
        #expect(streak == Streak(current: 1, best: 3))
    }

    @Test func weeklyStreak() {
        let calendar = makeCalendar()
        let now = date(2026, 11, 18, 15, in: calendar)
        // Closed in the three weeks before this one; this week not yet.
        let closedWeekStarts: Set<Date> = [date(2026, 11, 9, in: calendar), date(2026, 11, 2, in: calendar),
                                           date(2026, 10, 26, in: calendar)]
        let streak = Streak.compute(period: .thisWeek, goal: 1, now: now, calendar: calendar, lookback: 8) {
            closedWeekStarts.contains($0.start) ? 1 : 0
        }
        #expect(streak == Streak(current: 3, best: 3))
    }
}
