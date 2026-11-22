import Foundation
import Testing
@testable import Everyring

struct HeartMinuteSettingsTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func defaultsMatchHeartMinutes() {
        let settings = HeartMinuteSettings()
        #expect(settings.zoneModel == .two)
        #expect(settings.activityMode == .withPauses)
        #expect(settings.maxHR == 180)   // age 40 until read from Health
        let config = settings.config
        #expect(config.requireActive && config.activitySource == .either && config.activeBridge == 300)
        #expect(config.maxGap == 300 && config.fillWorkoutGaps)
    }

    @Test func activityModesMapLikeHeartMinutes() {
        var settings = HeartMinuteSettings()
        settings.activityMode = .always
        #expect(!settings.config.requireActive)
        settings.activityMode = .watch
        #expect(settings.config.requireActive && settings.config.activitySource == .watchMotion
                && settings.config.activeBridge == 0)
    }

    @Test func zonesFollowAgeAndOverrides() {
        var settings = HeartMinuteSettings()
        settings.age = 50
        #expect(settings.zones.moderate == 85)   // 50 % of 170
        settings.zoneWeights[.two] = [0, 1, 3]
        #expect(settings.zones.weights == [0, 1, 3])
        settings.zoneModel = .five
        #expect(settings.zones.weights == ZoneModel.five.defaultWeights)
    }

    @Test func creditsPerBucket() {
        // 20 minutes at 110 bpm (moderate for max 180), everything counts.
        var settings = HeartMinuteSettings()
        settings.activityMode = .always
        let samples = (0...20).map { HRSample(date: t0.addingTimeInterval(Double($0) * 60), bpm: 110) }
        let buckets = [DateInterval(start: t0, duration: 600), DateInterval(start: t0.addingTimeInterval(600), duration: 600)]
        let credits = HeartMinuteSettings.credits(samples: samples, workouts: [], exercise: [], buckets: buckets,
                                                  settings: settings)
        #expect(credits.map { ($0 * 1000).rounded() / 1000 } == [10, 10])
        // Only measurements in workouts: none here.
        let none = HeartMinuteSettings.credits(samples: samples, workouts: [], exercise: [], buckets: buckets,
                                               settings: settings, keep: { $0.inWorkout })
        #expect(none == [0, 0])
    }

    @Test func savedWithTheLibrary() throws {
        var library = RingLibrary(sets: [])
        library.heartMinutes.age = 36
        library.heartMinutes.activityMode = .watch
        let decoded = try JSONDecoder().decode(RingLibrary.self, from: JSONEncoder().encode(library))
        #expect(decoded.heartMinutes == library.heartMinutes)
        let old = try JSONDecoder().decode(RingLibrary.self, from: Data(#"{"sets":[]}"#.utf8))
        #expect(old.heartMinutes == HeartMinuteSettings())
    }

    @Test func heartMinutesMetric() {
        #expect(HealthMetric.heartMinutes.title == "Heart Minutes")
        #expect(HealthMetric.heartMinutes.suggestedGoal(for: .rollingDays(7), locale: Locale(identifier: "da_DK")) == 150)
        #expect(HealthMetric.heartMinutes.supportsWorkoutLeaveOut)
    }
}
