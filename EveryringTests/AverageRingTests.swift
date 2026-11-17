import Foundation
import Testing
@testable import Everyring

struct AverageRingTests {
    let cph = makeCalendar()

    func sleep(_ period: RingPeriod) -> Ring {
        Ring(name: "Sleep", color: .indigo, symbol: "bed.double.fill", metric: .sleep, goal: 8, period: period,
             aggregation: .dailyAverage)
    }

    @Test func oneDayPeriodIsNotAnAverage() {
        #expect(!sleep(.today).isAverage)
        #expect(sleep(.rollingDays(30)).isAverage)
    }

    @Test func rollingAverageDividesByTheWholeWindow() {
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = sleep(.rollingDays(30))
        let window = ring.period.interval(now: now, calendar: cph)
        #expect(ring.measure(30 * 7.5, in: window, now: now, calendar: cph) == 7.5)
    }

    @Test func fixedAverageInProgressDividesByDaysSoFar() {
        // Wednesday 18 November with a Monday week start: three days so far.
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = sleep(.thisWeek)
        let week = ring.period.interval(now: now, calendar: cph)
        #expect(ring.measure(24, in: week, now: now, calendar: cph) == 8)
        #expect(ring.isMet(8))
        // A finished week divides by all seven days.
        let last = ring.period.previous(week, calendar: cph)
        #expect(ring.measure(49, in: last, now: now, calendar: cph) == 7)
    }

    @Test func historyShowsAverages() {
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = sleep(.thisWeek)
        var values: [Date: Double] = [:]
        for day in 9...18 { values[date(2026, 11, day, in: cph)] = 8 }
        let history = RingHistory.make(for: ring, daily: values, now: now, calendar: cph)
        #expect(history.periods[0].value == 8)
        #expect(history.periods[1].value == 8)
        #expect(history.periods[1].closed)
    }

    @Test func chartShowsRunningAverage() {
        let now = date(2026, 11, 18, 15, in: cph)
        let ring = sleep(.thisWeek)
        let buckets = [date(2026, 11, 16, in: cph): 6.0, date(2026, 11, 17, in: cph): 8, date(2026, 11, 18, in: cph): 7]
        let progress = PeriodProgress.make(for: ring, buckets: buckets, now: now, calendar: cph)
        #expect(progress.points.map(\.total) == [6, 7, 7])
        #expect(progress.paceNow == nil)
    }

    @Test func averageMayDropInTheCache() {
        let start = date(2026, 11, 16, in: cph)
        let old = RingSnapshot(value: 8, intervalStart: start, intervalEnd: start.addingTimeInterval(7 * 86_400), updated: start)
        var new = old
        new.value = 6
        let ring = sleep(.thisWeek)
        var cache = ProgressCache(rings: [ring.id: old])
        cache.merge([ring.id: new], library: RingLibrary(sets: [RingSet(name: "S", rings: [ring])]), allowDecrease: false)
        #expect(cache.rings[ring.id]?.value == 6)
    }

    @Test func oldRingsDecodeAsTotals() throws {
        let ring = Ring(name: "Steps", color: .fern, symbol: "figure.walk", metric: .steps, goal: 70_000, period: .thisWeek)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ring)) as! [String: Any]
        json.removeValue(forKey: "aggregation")
        let decoded = try JSONDecoder().decode(Ring.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.aggregation == .total)
        #expect(sleep(.rollingDays(30)).progressText(7.5).hasSuffix("a day"))
    }

    @Test func skippingEmptyDaysDividesByDaysWithData() {
        let now = date(2026, 11, 18, 15, in: cph)
        var ring = sleep(.rollingDays(7))
        // Seven nights in the window, one without the watch.
        var values: [Date: Double] = [:]
        for day in 12...18 where day != 15 { values[date(2026, 11, day, in: cph)] = 7 }
        let window = ring.period.interval(now: now, calendar: cph)
        #expect(ring.measure(daily: values, in: window, now: now, calendar: cph) == 6)
        ring.averageSkipsEmptyDays = true
        #expect(ring.measure(daily: values, in: window, now: now, calendar: cph) == 7)
        #expect(ring.measure(daily: [:], in: window, now: now, calendar: cph) == 0)
    }

    @Test func chartSkipsEmptyDaysWhenAsked() {
        let now = date(2026, 11, 18, 15, in: cph)
        var ring = sleep(.thisWeek)
        ring.averageSkipsEmptyDays = true
        let buckets = [date(2026, 11, 16, in: cph): 6.0, date(2026, 11, 18, in: cph): 8]
        let progress = PeriodProgress.make(for: ring, buckets: buckets, now: now, calendar: cph)
        #expect(progress.points.map(\.total) == [6, 6, 7])
    }
}
