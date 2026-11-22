import Foundation
import Testing
@testable import Everyring

struct ProgressCacheTests {
    let cph = makeCalendar()

    func snapshot(_ value: Double, day: Int, rolling: Bool = false) -> RingSnapshot {
        RingSnapshot(value: value, intervalStart: date(2026, 11, day, in: cph),
                     intervalEnd: date(2026, 11, day + 1, in: cph), updated: date(2026, 11, day, 12, in: cph))
    }

    @Test func backgroundCannotLowerFixedRingInSamePeriod() {
        #expect(!ProgressCache.shouldReplace(snapshot(5_000, day: 18), with: snapshot(4_000, day: 18),
                                             rolling: false, allowDecrease: false))
        #expect(ProgressCache.shouldReplace(snapshot(5_000, day: 18), with: snapshot(6_000, day: 18),
                                            rolling: false, allowDecrease: false))
    }

    @Test func newPeriodRollingOrAppOpenMayLower() {
        #expect(ProgressCache.shouldReplace(snapshot(5_000, day: 18), with: snapshot(100, day: 19),
                                            rolling: false, allowDecrease: false))
        #expect(ProgressCache.shouldReplace(snapshot(5_000, day: 18), with: snapshot(4_000, day: 18),
                                            rolling: true, allowDecrease: false))
        #expect(ProgressCache.shouldReplace(snapshot(5_000, day: 18), with: snapshot(4_000, day: 18),
                                            rolling: false, allowDecrease: true))
        #expect(ProgressCache.shouldReplace(nil, with: snapshot(1, day: 18), rolling: false, allowDecrease: false))
    }

    @Test func mergeKeepsHigherAndDropsDeletedRings() {
        let steps = Ring.new(metric: .steps)
        let gone = Ring.new(metric: .water)
        var cache = ProgressCache(rings: [steps.id: snapshot(5_000, day: 18), gone.id: snapshot(1, day: 18)])
        let library = RingLibrary(sets: [RingSet(name: "A", rings: [steps])])
        cache.merge([steps.id: snapshot(4_000, day: 18)], library: library, allowDecrease: false)
        #expect(cache.rings[steps.id]?.value == 5_000)
        #expect(cache.rings[gone.id] == nil)
    }

    @Test func fixedRingShowsZeroAfterItsPeriodEnds() {
        var steps = Ring.new(metric: .steps)
        steps.period = .today
        let cache = ProgressCache(rings: [steps.id: snapshot(5_000, day: 18)])
        #expect(cache.value(for: steps, at: date(2026, 11, 18, 23, in: cph), calendar: cph) == 5_000)
        #expect(cache.value(for: steps, at: date(2026, 11, 19, 0, 1, in: cph), calendar: cph) == 0)
    }

    @Test func rollingRingKeepsLastValue() {
        var exercise = Ring.new(metric: .exerciseMinutes())
        exercise.period = .rollingDays(7)
        let cache = ProgressCache(rings: [exercise.id: snapshot(120, day: 18)])
        #expect(cache.value(for: exercise, at: date(2026, 11, 19, 8, in: cph), calendar: cph) == 120)
    }

    @Test func boundariesAreNextPeriodStarts() {
        var day = Ring.new(metric: .steps)
        day.period = .today
        var week = Ring.new(metric: .workouts(.count, kind: nil))
        week.period = .thisWeek
        var rolling = Ring.new(metric: .exerciseMinutes())
        rolling.period = .rollingDays(7)
        // Sunday 22 Nov 15:00, Monday week start: midnight is both a new day and a new week.
        let now = date(2026, 11, 22, 15, in: cph)
        #expect(ProgressCache.boundaries(for: [day, week, rolling], after: now, calendar: cph)
            == [date(2026, 11, 23, in: cph)])
        // Wednesday: only the day ends within 24 hours.
        let wednesday = date(2026, 11, 18, 15, in: cph)
        #expect(ProgressCache.boundaries(for: [day, week], after: wednesday, calendar: cph)
            == [date(2026, 11, 19, in: cph)])
    }

    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ProgressCache(rings: [UUID(): snapshot(42, day: 18)])
        try cache.save(to: url)
        #expect(ProgressCache.load(from: url) == cache)
    }
}
