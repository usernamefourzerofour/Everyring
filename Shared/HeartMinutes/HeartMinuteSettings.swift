import Foundation

/// How Heart Minutes are calculated: the same settings and defaults as the Heart Minutes app. Part of the ring library,
/// so the watch calculates the same way.
struct HeartMinuteSettings: Codable, Hashable, Sendable {
    var zoneModel: ZoneModel = .two
    /// Lower limit of each zone as a fraction of max heart rate, per zone model (`nil`: the model's defaults).
    var zonePercents: [ZoneModel: [Double]] = [:]
    /// How much a minute in each zone counts, per zone model (`nil`: the model's defaults).
    var zoneWeights: [ZoneModel: [Double]] = [:]
    var maxHRSource: MaxHRSource = .age
    /// For max heart rate from age (220 − age). `nil` until read from Health or entered.
    var age: Int?
    var manualMaxHR = 180
    /// When background heart rate counts (Heart Minutes' default: active, Exercise ring and short pauses).
    var activityMode: ActiveMinutes.ActivityMode = .withPauses
    /// Longest pause between active measurements that is filled (seconds).
    var pauseSeconds = 300
    /// Longest gap between two measurements outside workouts that counts (seconds, 1–600).
    var maxGapSeconds = 300
    var workoutGaps: ActiveMinutes.WorkoutGaps = .betweenMeasurements
    var interpolation: ActiveMinutes.Interpolation = .linear

    static let defaultAge = 40

    var effectiveAge: Int { age ?? Self.defaultAge }

    var maxHR: Double { maxHRSource == .age ? HeartZones.maxHR(age: effectiveAge) : Double(manualMaxHR) }

    var zones: HeartZones {
        HeartZones(maxHR: maxHR, model: zoneModel, percents: zonePercents[zoneModel], weights: zoneWeights[zoneModel])
    }

    /// The calculation's settings, as Heart Minutes builds them from its activity mode.
    var config: ActiveMinutes.Config {
        let pause = TimeInterval(min(max(pauseSeconds, 1), 600))
        let (requireActive, source, bridge): (Bool, ActiveMinutes.ActivitySource, TimeInterval) = switch activityMode {
        case .always: (false, .either, 0)
        case .watch: (true, .watchMotion, 0)
        case .watchWithPauses: (true, .watchMotion, pause)
        case .watchOrRing: (true, .either, 0)
        case .withPauses: (true, .either, pause)
        }
        return ActiveMinutes.Config(zones: zones, requireActive: requireActive, fillWorkoutGaps: workoutGaps != .sameLimit,
                                    maxGap: TimeInterval(min(max(maxGapSeconds, 1), 600)), interpolation: interpolation,
                                    activitySource: source, activeBridge: bridge)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case zoneModel, zonePercents, zoneWeights, maxHRSource, age, manualMaxHR, activityMode, pauseSeconds
        case maxGapSeconds, workoutGaps, interpolation
    }

    /// Every field may be missing (older libraries, or settings added later).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HeartMinuteSettings()
        zoneModel = try c.decodeIfPresent(ZoneModel.self, forKey: .zoneModel) ?? d.zoneModel
        zonePercents = try c.decodeIfPresent([ZoneModel: [Double]].self, forKey: .zonePercents) ?? [:]
        zoneWeights = try c.decodeIfPresent([ZoneModel: [Double]].self, forKey: .zoneWeights) ?? [:]
        maxHRSource = try c.decodeIfPresent(MaxHRSource.self, forKey: .maxHRSource) ?? d.maxHRSource
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        manualMaxHR = try c.decodeIfPresent(Int.self, forKey: .manualMaxHR) ?? d.manualMaxHR
        activityMode = try c.decodeIfPresent(ActiveMinutes.ActivityMode.self, forKey: .activityMode) ?? d.activityMode
        pauseSeconds = try c.decodeIfPresent(Int.self, forKey: .pauseSeconds) ?? d.pauseSeconds
        maxGapSeconds = try c.decodeIfPresent(Int.self, forKey: .maxGapSeconds) ?? d.maxGapSeconds
        workoutGaps = try c.decodeIfPresent(ActiveMinutes.WorkoutGaps.self, forKey: .workoutGaps) ?? d.workoutGaps
        interpolation = try c.decodeIfPresent(ActiveMinutes.Interpolation.self, forKey: .interpolation) ?? d.interpolation
    }
}

extension HeartMinuteSettings {
    /// Heart Minutes for each bucket of `range` from heart rate measurements, with workouts and Exercise-ring minutes
    /// marked as Heart Minutes does. Measurements must cover a little more than the range (gaps look at neighbours).
    /// - Parameters:
    ///   - workouts: the workouts that count as workouts (gaps inside them count, and with `.wholeWorkout` the
    ///     workout is filled from start to end).
    ///   - keep: which measurements count (e.g. only those in workouts), after marking.
    static func credits(samples: [HRSample], workouts: [DateInterval], exercise: [DateInterval],
                        buckets: [DateInterval], settings: HeartMinuteSettings,
                        keep: (HRSample) -> Bool = { _ in true }) -> [Double] {
        var marked = HRSample.markingExercise(HRSample.markingWorkouts(samples, workouts), exercise)
        if settings.workoutGaps == .wholeWorkout { marked = ActiveMinutes.extendingWorkouts(marked, workouts) }
        marked = marked.filter(keep)
        let config = settings.config
        return buckets.map { ActiveMinutes.credit(in: marked, from: $0.start, to: $0.end, config: config) }
    }
}
