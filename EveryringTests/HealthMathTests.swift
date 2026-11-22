import Foundation
import Testing
@testable import Everyring

struct IntervalMathTests {
    let cph = makeCalendar()

    func span(_ d1: Int, _ h1: Int, _ m1: Int, _ d2: Int, _ h2: Int, _ m2: Int) -> DateInterval {
        DateInterval(start: date(2026, 11, d1, h1, m1, in: cph), end: date(2026, 11, d2, h2, m2, in: cph))
    }

    @Test func mergesOverlapsFromSeveralSources() {
        // Watch and iPhone record the same meditation.
        let a = span(18, 8, 0, 18, 8, 20)
        let b = span(18, 8, 10, 18, 8, 30)
        let c = span(18, 9, 0, 18, 9, 10)
        #expect(IntervalMath.merged([c, b, a]) == [span(18, 8, 0, 18, 8, 30), c])
        #expect(IntervalMath.covered([a, b, c], within: span(18, 0, 0, 19, 0, 0)) == 40 * 60)
    }

    @Test func coveredClipsToWindow() {
        let late = span(18, 23, 50, 19, 0, 10)
        #expect(IntervalMath.covered([late], within: span(18, 0, 0, 19, 0, 0)) == 10 * 60)
    }

    @Test func nightCountsOnWakeUpDay() {
        // Stage samples 23:00–02:00 and 02:30–07:00 (30 min awake in between), plus a nap 14:00–14:30.
        let night = [span(17, 23, 0, 18, 2, 0), span(18, 2, 30, 18, 7, 0)]
        let nap = [span(18, 14, 0, 18, 14, 30)]
        let wednesday = span(18, 0, 0, 19, 0, 0)
        let tuesday = span(17, 0, 0, 18, 0, 0)
        #expect(IntervalMath.asleep(night + nap, attributedTo: wednesday) == 8 * 3600)
        #expect(IntervalMath.asleep(night, attributedTo: tuesday) == 0)
    }

    @Test func duplicateSleepIsNotDoubleCounted() {
        let watch = span(17, 23, 0, 18, 7, 0)
        let phone = span(17, 23, 30, 18, 6, 30)
        #expect(IntervalMath.asleep([watch, phone], attributedTo: span(18, 0, 0, 19, 0, 0)) == 8 * 3600)
    }

    @Test func longGapStartsNewSession() {
        let sessions = IntervalMath.sessions([span(18, 1, 0, 18, 2, 0), span(18, 5, 0, 18, 6, 0)], maxGap: 2 * 3600)
        #expect(sessions.count == 2)
    }
}

struct MetricFormatTests {
    let us = Locale(identifier: "en_US")
    let dk = Locale(identifier: "da_DK")

    @Test func counts() {
        #expect(HealthMetric.steps.format(6_512.7, locale: us) == "6,512 steps")
        #expect(HealthMetric.workouts(.count, kind: nil).format(3, locale: us) == "3 workouts")
    }

    @Test func distanceFollowsLocale() {
        #expect(HealthMetric.walkingRunningDistance.format(14_200, locale: us).contains("mi"))
        let metric = HealthMetric.walkingRunningDistance.format(14_200, locale: dk)
        #expect(metric.contains("km"))
        #expect(metric.contains("14,2"))
    }

    @Test func durations() {
        #expect(HealthMetric.exerciseMinutes().format(45, locale: us) == "45 min")
        #expect(HealthMetric.exerciseMinutes().format(0, locale: us) == "0 min")
        let sleep = HealthMetric.sleep.format(7.5, locale: us)
        #expect(sleep.contains("7 hr"))
        #expect(sleep.contains("30 min"))
    }

    @Test func fractionMayExceedOne() {
        let ring = Ring(name: "Steps", color: .sunrise, symbol: "figure.walk", metric: .steps, goal: 10_000,
                        period: .today)
        #expect(ring.fraction(12_500) == 1.25)
        #expect(ring.fraction(-5) == 0)
        #expect(Ring(name: "", color: .fern, symbol: "", metric: .steps, goal: 0, period: .today).fraction(100) == 0)
    }

    @Test func accessibilityText() {
        let calendar = makeCalendar()
        let ring = Ring(name: "Exercise", color: .violet, symbol: "flame", metric: .exerciseMinutes(), goal: 150,
                        period: .rollingDays(7))
        let text = ring.accessibilityText(75, now: date(2026, 11, 18, 12, in: calendar), calendar: calendar)
        #expect(text.hasPrefix("Exercise, "))
        #expect(text.hasSuffix("Last 7 days, 50 percent"))
    }
}

struct RingStoreTests {
    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var library = RingLibrary.starter
        library.weekStart = .sunday
        try RingStore.save(library, to: url)
        #expect(RingStore.load(from: url) == library)
    }

    @Test func missingFileLoadsNil() {
        #expect(RingStore.load(from: URL(filePath: "/nonexistent/rings.json")) == nil)
    }

    @Test func starterSetIsValid() {
        let set = RingSet.starter
        #expect((1...RingSet.maxRings).contains(set.rings.count))
        #expect(Set(set.rings.map(\.color)).count == set.rings.count)
    }
}

struct RingLayoutTests {
    @Test func fiveRingsFitAndStayReadable() {
        // A small widget's ring is roughly 120 pt.
        let lw = RingStackView.lineWidth(diameter: 120, count: 5)
        #expect(lw >= 8)
        let innermostRadius = 60 - lw / 2 - 4 * lw * (1 + RingStackView.gapUnits)
        #expect(innermostRadius > lw / 2)
    }

    @Test func fewerRingsAreThicker() {
        #expect(RingStackView.lineWidth(diameter: 120, count: 2) > RingStackView.lineWidth(diameter: 120, count: 5))
    }
}
