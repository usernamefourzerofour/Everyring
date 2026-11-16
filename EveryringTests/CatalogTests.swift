import Foundation
import Testing
@testable import Everyring

struct DisplayUnitTests {
    let us = Locale(identifier: "en_US")
    let dk = Locale(identifier: "da_DK")
    let gb = Locale(identifier: "en_GB")
    let au = Locale(identifier: "en_AU")

    @Test func progressUsesGoalUnit() {
        #expect(HealthMetric.walkingRunningDistance.formatProgress(0, goal: 100_000, locale: us) == "0 of 62.1 mi")
        #expect(HealthMetric.steps.formatProgress(6_512, goal: 10_000, locale: us) == "6,512 of 10,000 steps")
        #expect(HealthMetric.exerciseMinutes.formatProgress(45, goal: 150, locale: us) == "45 of 150 min")
    }

    @Test func standHoursAreACount() {
        #expect(HealthMetric.standHours.formatProgress(0, goal: 10, locale: us) == "0 of 10 hr")
        #expect(HealthMetric.standHours.format(7, locale: us) == "7 hr")
        let sleep = HealthMetric.sleep.formatProgress(6.5, goal: 8, locale: us)
        #expect(sleep.contains("6 hr") && sleep.contains("30 min") && sleep.hasSuffix("of 8 hr"))
    }

    @Test func progressNeverRoundsUpToGoal() {
        #expect(HealthMetric.walkingRunningDistance.formatProgress(19_990, goal: 20_000, locale: dk)
            .hasPrefix("19,9 of"))
    }

    @Test func distanceUnits() {
        #expect(HealthMetric.cyclingDistance.displayUnit(locale: dk) == UnitLength.kilometers)
        #expect(HealthMetric.cyclingDistance.displayUnit(locale: us) == UnitLength.miles)
        #expect(HealthMetric.cyclingDistance.displayUnit(locale: gb) == UnitLength.miles)
        #expect(HealthMetric.swimmingDistance.displayUnit(locale: dk) == UnitLength.meters)
        #expect(HealthMetric.workouts(.distance, kind: .swimming).displayUnit(locale: us) == UnitLength.yards)
        #expect(HealthMetric.steps.displayUnit(locale: dk) == nil)
    }

    @Test func energyAndWater() {
        #expect(HealthMetric.activeEnergy.displayUnit(locale: dk) == UnitEnergy.kilocalories)
        #expect(HealthMetric.activeEnergy.displayUnit(locale: au) == UnitEnergy.kilojoules)
        #expect(HealthMetric.water.displayUnit(locale: us) == UnitVolume.fluidOunces)
        #expect(HealthMetric.water.displayUnit(locale: dk) == UnitVolume.liters)
    }

    @Test(arguments: [HealthMetric.walkingRunningDistance, .activeEnergy, .water, .steps, .sleep])
    func displayRoundTrip(metric: HealthMetric) {
        for locale in [us, dk, au] {
            let base = 1234.5
            #expect(abs(metric.fromDisplay(metric.toDisplay(base, locale: locale), locale: locale) - base) < 0.001)
        }
    }
}

struct CatalogTests {
    let dk = Locale(identifier: "da_DK")
    let us = Locale(identifier: "en_US")

    @Test func everyMetricIsInOneCategory() {
        let all = HealthMetric.Category.allCases.flatMap(\.metrics)
        #expect(Set(all).count == all.count)
        for metric in all { #expect(metric.category.metrics.contains(metric)) }
    }

    @Test(arguments: [(3.0, 3.0), (21.7, 20), (56, 55), (213, 200), (10_400, 10_000), (0.43, 0.43), (150, 150)])
    func roundNicely(value: Double, expected: Double) {
        #expect(abs(HealthMetric.roundNicely(value) - expected) < 0.0001)
    }

    @Test func suggestedGoals() {
        #expect(HealthMetric.steps.suggestedGoal(for: .today, locale: dk) == 8_000)
        #expect(HealthMetric.exerciseMinutes.suggestedGoal(for: .rollingDays(7), locale: dk) == 200)
        #expect(HealthMetric.workouts(.count, kind: nil).suggestedGoal(for: .thisWeek, locale: dk) == 3)
        #expect(HealthMetric.workouts(.count, kind: nil).suggestedGoal(for: .today, locale: dk) == 1)
        #expect(HealthMetric.walkingRunningDistance.suggestedGoal(for: .thisWeek, locale: dk) == 35_000)
        // 35 km ≈ 21.7 mi → 20 mi.
        let miles = HealthMetric.walkingRunningDistance.toDisplay(
            HealthMetric.walkingRunningDistance.suggestedGoal(for: .thisWeek, locale: us), locale: us)
        #expect(abs(miles - 20) < 0.0001)
    }

    @Test func newRingPicksUnusedColor() {
        let ring = Ring.new(metric: .sleep, usedColors: [.sunrise, .tangerine])
        #expect(ring.color == .magenta)
        #expect(ring.name == "Sleep")
        #expect(ring.period == .rollingDays(7))
        #expect(ring.symbol == "bed.double")
    }

    @Test func streakUnits() {
        #expect(RingPeriod.thisWeek.streakUnits(1) == "1 week")
        #expect(RingPeriod.thisWeek.streakUnits(3) == "3 weeks")
        #expect(RingPeriod.rollingDays(7).streakUnits(12) == "12 days")
        #expect(RingPeriod.everyDays(3, from: .now).streakUnits(2) == "2 periods")
    }
}
