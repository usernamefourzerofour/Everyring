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
        #expect(settings.workoutGaps == .betweenMeasurements && settings.interpolation == .linear)
        #expect(settings.maxHRSource == .age && settings.manualMaxHR == 180)
        #expect(settings.zones.percents == [0, 0.5, 0.7] && settings.zones.weights == [0, 1, 2])
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
        // As in the Heart Minutes app: 150 min this week.
        #expect(HealthMetric.heartMinutes.defaultPeriod == .thisWeek)
        #expect(HealthMetric.heartMinutes.suggestedGoal(for: .thisWeek, locale: Locale(identifier: "da_DK")) == 150)
        let ring = Ring.new(metric: .heartMinutes)
        #expect(ring.goal == 150 && ring.period == .thisWeek && ring.activity == .all)
        #expect(HealthMetric.heartMinutes.supportsWorkoutLeaveOut)
    }
}

struct ScreenTimeLogTests {
    let cph = makeCalendar()

    @Test func readingsBecomeDaysAndHours() {
        let ring = UUID()
        var log = ScreenTimeLog()
        log.record(ring: ring, minutes: 5, at: date(2026, 11, 18, 9, 10, in: cph), calendar: cph)
        log.record(ring: ring, minutes: 10, at: date(2026, 11, 18, 9, 40, in: cph), calendar: cph)
        log.record(ring: ring, minutes: 30, at: date(2026, 11, 18, 14, 5, in: cph), calendar: cph)
        // A late, lower threshold never takes the day back.
        log.record(ring: ring, minutes: 15, at: date(2026, 11, 18, 15, 0, in: cph), calendar: cph)
        log.record(ring: ring, minutes: 5, at: date(2026, 11, 19, 8, 0, in: cph), calendar: cph)
        #expect(log.daily(ring: ring, calendar: cph) == [date(2026, 11, 18, in: cph): 30, date(2026, 11, 19, in: cph): 5])
        let day = DateInterval(start: date(2026, 11, 18, in: cph), end: date(2026, 11, 19, in: cph))
        #expect(log.hourly(ring: ring, in: day, calendar: cph)
                == [date(2026, 11, 18, 9, in: cph): 10, date(2026, 11, 18, 14, in: cph): 20])
    }

    @Test func namesRoundTrip() {
        let ring = UUID()
        #expect(ScreenTimeLog.ring(fromActivity: ScreenTimeLog.activityName(ring: ring)) == ring)
        #expect(ScreenTimeLog.minutes(fromEvent: ScreenTimeLog.eventName(minutes: 45)) == 45)
        #expect(ScreenTimeLog.thresholds.first == 5 && ScreenTimeLog.thresholds.last == 960)
    }

    @Test func screenTimeMetric() {
        #expect(HealthMetric.screenTime.defaultGoalKind == .limit)
        #expect(!HealthMetric.screenTime.readsHealth)
        #expect(HealthMetric.screenTime.category == .screenTime)
    }
}
