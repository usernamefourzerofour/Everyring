import Foundation
import Testing
@testable import Everyring

struct LimitRingTests {
    let cph = makeCalendar()

    var calories: Ring {
        Ring(name: "Calories eaten", color: .tangerine, symbol: "fork.knife", metric: .quantity(.dietaryEnergy),
             goal: 2_000, period: .today, goalKind: .limit)
    }

    @Test func limitIsMetWhenLoggedAndUnder() {
        #expect(calories.isMet(1_800))
        #expect(calories.isMet(2_000))
        #expect(!calories.isMet(2_100))
        #expect(!calories.isMet(0))  // nothing logged
        #expect(!calories.isMetInProgress(1_000))  // only once the day is over
    }

    @Test func overLimitTurnsWarning() {
        #expect(!calories.display(1_900).warning)
        #expect(calories.display(2_300).warning)
        var steps = calories
        steps.goalKind = .reach
        #expect(!steps.display(12_000).warning)
    }

    @Test func limitStreakCountsDaysUnder() {
        let now = date(2026, 11, 18, 15, in: cph)
        // Today 2,500 (over, but in progress); 17th 1,900; 16th 2,200 (over); 15th 1,500; 14th 1,700; 13th nothing.
        let daily = [18: 2_500.0, 17: 1_900, 16: 2_200, 15: 1_500, 14: 1_700]
        let values = Dictionary(uniqueKeysWithValues: daily.map { (date(2026, 11, $0.key, in: cph), $0.value) })
        let history = RingHistory.make(for: calories, daily: values, now: now, calendar: cph)
        #expect(history.streak == Streak(current: 1, best: 2))
        #expect(history.periods[0].isCurrent && !history.periods[0].closed)
    }

    @Test func oldRingsDecodeAsReach() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Steps","color":"sunrise","symbol":"figure.walk",
         "metric":{"steps":{}},"goal":10000,"period":{"today":{}}}
        """
        let ring = try JSONDecoder().decode(Ring.self, from: Data(json.utf8))
        #expect(ring.goalKind == .reach)
        let limit = calories
        let again = try JSONDecoder().decode(Ring.self, from: JSONEncoder().encode(limit))
        #expect(again == limit)
    }

    @Test func nutritionLimitsByDefault() {
        #expect(HealthMetric.quantity(.dietaryEnergy).defaultGoalKind == .limit)
        #expect(HealthMetric.quantity(.protein).defaultGoalKind == .reach)
        #expect(Ring.new(metric: .quantity(.sugar)).isLimit)
    }
}
