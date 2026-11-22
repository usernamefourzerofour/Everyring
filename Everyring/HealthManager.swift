import Foundation
import HealthKit

extension HealthMetric {
    /// Cumulative quantity type, for metrics that are a plain sum.
    var quantityType: HKQuantityType? {
        switch self {
        case .steps: HKQuantityType(.stepCount)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .exerciseMinutes: HKQuantityType(.appleExerciseTime)
        case .flightsClimbed: HKQuantityType(.flightsClimbed)
        case .walkingRunningDistance: HKQuantityType(.distanceWalkingRunning)
        case .cyclingDistance: HKQuantityType(.distanceCycling)
        case .swimmingDistance: HKQuantityType(.distanceSwimming)
        case .wheelchairDistance: HKQuantityType(.distanceWheelchair)
        case .timeInDaylight: HKQuantityType(.timeInDaylight)
        case .water: HKQuantityType(.dietaryWater)
        case .quantity(let kind): HKQuantityType(kind.identifier)
        case .nutrient(let kind): HKQuantityType(kind.identifier)
        case .sensitive(let kind): kind.quantityIdentifier.map { HKQuantityType($0) }
        case .standHours, .heartMinutes, .workouts, .sleep, .sleepStage, .mindfulMinutes, .events: nil
        }
    }

    /// The type of sample the metric reads, for listing its sources.
    var sampleType: HKSampleType? {
        if let quantityType { return quantityType }
        switch self {
        case .standHours: return HKCategoryType(.appleStandHour)
        case .heartMinutes: return HKQuantityType(.heartRate)
        case .sleep, .sleepStage: return HKCategoryType(.sleepAnalysis)
        case .mindfulMinutes: return HKCategoryType(.mindfulSession)
        case .events(let kind): return HKCategoryType(kind.identifier)
        case .sensitive(let kind): return kind.categoryIdentifier.map { HKCategoryType($0) }
        case .workouts: return HKObjectType.workoutType()
        default: return nil
        }
    }

    /// Everything this metric needs read access to.
    var readTypes: Set<HKObjectType> {
        // Heart Minutes: heart rate, plus workouts and Exercise minutes to mark measurements, and age for max heart rate.
        if case .heartMinutes = self {
            return [HKQuantityType(.heartRate), HKQuantityType(.appleExerciseTime), HKObjectType.workoutType(),
                    HKCharacteristicType(.dateOfBirth)]
        }
        // Activity measured all day: workouts too, to leave some out and to list them on the ring's detail screen.
        if supportsWorkoutLeaveOut, let quantityType { return [quantityType, HKObjectType.workoutType()] }
        if let quantityType { return [quantityType] }
        switch self {
        case .standHours: return [HKCategoryType(.appleStandHour)]
        case .sleep, .sleepStage: return [HKCategoryType(.sleepAnalysis)]
        case .mindfulMinutes: return [HKCategoryType(.mindfulSession)]
        case .events(let kind): return [HKCategoryType(kind.identifier)]
        case .sensitive(let kind): return kind.categoryIdentifier.map { [HKCategoryType($0)] } ?? []
        case .workouts(let measure, _):
            var types: Set<HKObjectType> = [HKObjectType.workoutType()]
            if measure == .distance { types.formUnion(Self.workoutDistanceTypes) }
            return types
        default: return []
        }
    }

    /// Distance types a workout can carry statistics for.
    static var workoutDistanceTypes: Set<HKQuantityType> {
        [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
         HKQuantityType(.distanceWheelchair), HKQuantityType(.distanceRowing), HKQuantityType(.distancePaddleSports),
         HKQuantityType(.distanceSkatingSports), HKQuantityType(.distanceCrossCountrySkiing),
         HKQuantityType(.distanceDownhillSnowSports)]
    }

    var hkUnit: HKUnit {
        switch baseUnit {
        case .count: .count()
        case .kilocalories: .kilocalorie()
        case .minutes: .minute()
        case .hours: .hour()
        case .meters: .meter()
        case .liters: .liter()
        case .grams: .gram()
        case .milligrams: .gramUnit(with: .milli)
        case .micrograms: .gramUnit(with: .micro)
        case .internationalUnits: .internationalUnit()
        }
    }
}

extension QuantityKind {
    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .restingEnergy: .basalEnergyBurned
        case .moveTime: .appleMoveTime
        case .standTime: .appleStandTime
        case .wheelchairPushes: .pushCount
        case .rowingDistance: .distanceRowing
        case .paddleDistance: .distancePaddleSports
        case .skatingDistance: .distanceSkatingSports
        case .crossCountrySkiingDistance: .distanceCrossCountrySkiing
        case .downhillSnowDistance: .distanceDownhillSnowSports
        case .swimmingStrokes: .swimmingStrokeCount
        case .dietaryEnergy: .dietaryEnergyConsumed
        case .protein: .dietaryProtein
        case .carbohydrates: .dietaryCarbohydrates
        case .fat: .dietaryFatTotal
        case .fiber: .dietaryFiber
        case .sugar: .dietarySugar
        case .caffeine: .dietaryCaffeine
        }
    }
}

extension NutrientKind {
    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .alcoholicBeverages: .numberOfAlcoholicBeverages
        case .saturatedFat: .dietaryFatSaturated
        case .monounsaturatedFat: .dietaryFatMonounsaturated
        case .polyunsaturatedFat: .dietaryFatPolyunsaturated
        case .cholesterol: .dietaryCholesterol
        case .sodium: .dietarySodium
        case .potassium: .dietaryPotassium
        case .calcium: .dietaryCalcium
        case .iron: .dietaryIron
        case .phosphorus: .dietaryPhosphorus
        case .magnesium: .dietaryMagnesium
        case .zinc: .dietaryZinc
        case .copper: .dietaryCopper
        case .manganese: .dietaryManganese
        case .chloride: .dietaryChloride
        case .iodine: .dietaryIodine
        case .selenium: .dietarySelenium
        case .chromium: .dietaryChromium
        case .molybdenum: .dietaryMolybdenum
        case .vitaminA: .dietaryVitaminA
        case .vitaminB6: .dietaryVitaminB6
        case .vitaminB12: .dietaryVitaminB12
        case .vitaminC: .dietaryVitaminC
        case .vitaminD: .dietaryVitaminD
        case .vitaminE: .dietaryVitaminE
        case .vitaminK: .dietaryVitaminK
        case .thiamin: .dietaryThiamin
        case .riboflavin: .dietaryRiboflavin
        case .niacin: .dietaryNiacin
        case .folate: .dietaryFolate
        case .biotin: .dietaryBiotin
        case .pantothenicAcid: .dietaryPantothenicAcid
        }
    }
}

extension SleepStage {
    var categoryValue: HKCategoryValueSleepAnalysis {
        switch self {
        case .core: .asleepCore
        case .deep: .asleepDeep
        case .rem: .asleepREM
        }
    }
}

extension SensitiveKind {
    /// Insulin, inhaler and falls are quantities; everything else is a category whose entries are counted.
    var quantityIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .insulinDelivery: .insulinDelivery
        case .inhalerUsage: .inhalerUsage
        case .timesFallen: .numberOfTimesFallen
        default: nil
        }
    }

    var categoryIdentifier: HKCategoryTypeIdentifier? {
        switch self {
        case .abdominalCramps: .abdominalCramps
        case .acne: .acne
        case .appetiteChanges: .appetiteChanges
        case .bladderIncontinence: .bladderIncontinence
        case .bloating: .bloating
        case .breastPain: .breastPain
        case .chestTightnessOrPain: .chestTightnessOrPain
        case .chills: .chills
        case .constipation: .constipation
        case .coughing: .coughing
        case .diarrhea: .diarrhea
        case .dizziness: .dizziness
        case .drySkin: .drySkin
        case .fainting: .fainting
        case .fatigue: .fatigue
        case .fever: .fever
        case .generalizedBodyAche: .generalizedBodyAche
        case .hairLoss: .hairLoss
        case .headache: .headache
        case .heartburn: .heartburn
        case .hotFlashes: .hotFlashes
        case .lossOfSmell: .lossOfSmell
        case .lossOfTaste: .lossOfTaste
        case .lowerBackPain: .lowerBackPain
        case .memoryLapse: .memoryLapse
        case .moodChanges: .moodChanges
        case .nausea: .nausea
        case .nightSweats: .nightSweats
        case .pelvicPain: .pelvicPain
        case .rapidPoundingOrFlutteringHeartbeat: .rapidPoundingOrFlutteringHeartbeat
        case .runnyNose: .runnyNose
        case .shortnessOfBreath: .shortnessOfBreath
        case .sinusCongestion: .sinusCongestion
        case .skippedHeartbeat: .skippedHeartbeat
        case .sleepChanges: .sleepChanges
        case .soreThroat: .soreThroat
        case .vaginalDryness: .vaginalDryness
        case .vomiting: .vomiting
        case .wheezing: .wheezing
        case .sexualActivity: .sexualActivity
        case .menstrualFlow: .menstrualFlow
        case .intermenstrualBleeding: .intermenstrualBleeding
        case .contraceptive: .contraceptive
        case .lactation: .lactation
        case .ovulationTest: .ovulationTestResult
        case .pregnancyTest: .pregnancyTestResult
        case .highHeartRateEvent: .highHeartRateEvent
        case .lowHeartRateEvent: .lowHeartRateEvent
        case .irregularHeartRhythmEvent: .irregularHeartRhythmEvent
        case .lowCardioFitnessEvent: .lowCardioFitnessEvent
        case .sleepApneaEvent: .sleepApneaEvent
        case .walkingSteadinessEvent: .appleWalkingSteadinessEvent
        case .environmentalAudioExposureEvent: .environmentalAudioExposureEvent
        case .headphoneAudioExposureEvent: .headphoneAudioExposureEvent
        case .insulinDelivery, .inhalerUsage, .timesFallen: nil
        }
    }

    /// Whether an entry with this category value counts: a symptom marked "not present" (or appetite "no change")
    /// doesn't, nor a period day logged as "no flow".
    func counts(_ value: Int) -> Bool {
        if isSymptom {
            // Severity "not present", presence "not present" and appetite "no change" are all 1.
            return value != HKCategoryValueSeverity.notPresent.rawValue
        }
        if self == .menstrualFlow { return value != HKCategoryValueVaginalBleeding.none.rawValue }
        return true
    }
}

extension EventKind {
    var identifier: HKCategoryTypeIdentifier {
        switch self {
        case .toothbrushing: .toothbrushingEvent
        case .handwashing: .handwashingEvent
        }
    }
}

extension WorkoutKind {
    init?(activityType: HKWorkoutActivityType) {
        guard let kind = Self.allCases.first(where: { $0.activityTypes.contains(activityType) }) else { return nil }
        self = kind
    }

    var activityTypes: [HKWorkoutActivityType] {
        switch self {
        case .running: [.running]
        case .walking: [.walking]
        case .hiking: [.hiking]
        case .cycling: [.cycling]
        case .swimming: [.swimming]
        case .rowing: [.rowing]
        case .elliptical: [.elliptical]
        case .strength: [.traditionalStrengthTraining, .functionalStrengthTraining]
        case .hiit: [.highIntensityIntervalTraining]
        case .yoga: [.yoga]
        case .pilates: [.pilates]
        case .dance: [.socialDance, .cardioDance]
        case .crossTraining: [.crossTraining]
        case .coreTraining: [.coreTraining]
        case .flexibility: [.flexibility]
        case .mixedCardio: [.mixedCardio]
        case .stairs: [.stairClimbing, .stairs, .stepTraining]
        case .tennis: [.tennis]
        case .badminton: [.badminton]
        case .tableTennis: [.tableTennis]
        case .pickleball: [.pickleball]
        case .soccer: [.soccer]
        case .basketball: [.basketball]
        case .golf: [.golf]
        case .climbing: [.climbing]
        case .martialArts: [.martialArts]
        case .boxing: [.boxing, .kickboxing]
        case .downhillSkiing: [.downhillSkiing]
        case .snowboarding: [.snowboarding]
        case .crossCountrySkiing: [.crossCountrySkiing]
        case .paddling: [.paddleSports]
        case .skating: [.skatingSports]
        }
    }
}

/// Reads ring values from Apple Health. Read-only: Everyring never writes to Health.
@MainActor
final class HealthManager {
    static let shared = HealthManager()

    let store = HKHealthStore()

    /// How Heart Minutes are calculated (the library's settings; set before reading).
    var heartMinuteSettings = RingStore.load()?.heartMinutes ?? HeartMinuteSettings()

    /// Age from the date of birth in Health, for max heart rate; `nil` if not set or not allowed.
    func ageFromHealth(now: Date = .now) -> Int? {
        guard Self.isAvailable, let components = try? store.dateOfBirthComponents(),
              let birth = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birth, to: now).year
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for read access to the types `metrics` need. HealthKit only shows the sheet for types not asked for before,
    /// so this is cheap to call whenever a ring is added.
    func requestAuthorization(for metrics: some Sequence<HealthMetric>) async throws {
        try await requestAuthorization(types: metrics.reduce(into: Set<HKObjectType>()) { $0.formUnion($1.readTypes) })
    }

    /// Asks for read access to `types` (see `requestAuthorization(for:)`).
    func requestAuthorization(types: Set<HKObjectType>) async throws {
        guard Self.isAvailable, !types.isEmpty else { return }
        // iOS shows one access sheet at a time: requests made while one is open wait for it and then run one by one,
        // instead of racing (several screens ask for the same new type at once).
        let previous = authorization
        let task = Task { @MainActor in
            _ = await previous?.result
            try await store.requestAuthorization(toShare: [], read: types)
        }
        authorization = task
        try await task.value
    }

    private var authorization: Task<Void, Error>?

    /// The ring's value over `interval`, in `metric.baseUnit`. Missing data (or no access, which HealthKit doesn't
    /// reveal for reading) counts as zero.
    func value(of metric: HealthMetric, in interval: DateInterval, filter: HealthFilter = .none) async throws -> Double {
        guard Self.isAvailable, interval.duration > 0 else { return 0 }
        let values = try await reading(metric) {
            try await self.read(metric, filter: filter, in: interval, by: .whole, calendar: .current)
        }
        return values.values.reduce(0, +)
    }

    /// The metric's value per calendar day from `start` up to `end`, keyed by start of day (days without data are
    /// missing). One query for the whole range: daily statistics for quantities, samples bucketed by day otherwise.
    func dailyValues(of metric: HealthMetric, from start: Date, to end: Date, calendar: Calendar,
                     filter: HealthFilter = .none) async throws -> [Date: Double] {
        guard Self.isAvailable, start < end else { return [:] }
        let range = DateInterval(start: calendar.startOfDay(for: start), end: end)
        return try await reading(metric) {
            try await self.read(metric, filter: filter, in: range, by: .day, calendar: calendar)
        }
    }

    /// The metric's value per hour inside `interval`, keyed by the start of each hour. Sleep and mindful minutes have
    /// no meaningful hourly build-up and return nothing.
    func hourlyValues(of metric: HealthMetric, in interval: DateInterval, calendar: Calendar,
                      filter: HealthFilter = .none) async throws -> [Date: Double] {
        guard Self.isAvailable, interval.duration > 0 else { return [:] }
        return try await reading(metric) {
            try await self.read(metric, filter: filter, in: interval, by: .hour, calendar: calendar)
        }
    }

    /// The apps and devices that wrote the metric's data, for picking a ring's sources.
    func sources(for metric: HealthMetric) async -> [HealthSource] {
        guard Self.isAvailable, let type = metric.sampleType else { return [] }
        let found = (try? await reading(metric) { try await self.sources(of: type) }) ?? []
        return found.map { HealthSource(id: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The workouts that started inside `interval`, newest first, each with what `metric` logged during it.
    func workoutLog(of metric: HealthMetric, in interval: DateInterval, filter: HealthFilter = .none) async throws -> [LoggedWorkout] {
        if case .heartMinutes = metric, Self.isAvailable {
            return try await reading(metric) {
                let scope = try await self.scope(for: metric, filter: HealthFilter(sources: filter.sources))
                let workouts = try await self.workouts(kinds: nil, in: interval)
                let spans = workouts.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
                let credits = try await self.heartMinutes(in: spans, around: interval, scope: scope, markAll: true)
                return zip(workouts, credits).map { workout, value in
                    LoggedWorkout(id: workout.uuid, kind: WorkoutKind(activityType: workout.workoutActivityType),
                                  start: workout.startDate, end: workout.endDate, value: value)
                }.reversed()
            }
        }
        guard Self.isAvailable, let type = metric.quantityType else { return [] }
        return try await reading(metric) {
            let scope = try await self.scope(for: metric, filter: filter)
            let workouts = try await self.workouts(kinds: nil, in: interval)
            var log: [LoggedWorkout] = []
            for workout in workouts.reversed() {
                let span = DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))
                let value = try await self.sum(type, unit: metric.hkUnit, in: span, scope: scope)
                log.append(LoggedWorkout(id: workout.uuid, kind: WorkoutKind(activityType: workout.workoutActivityType),
                                         start: workout.startDate, end: workout.endDate, value: value))
            }
            return log
        }
    }

    /// How much of `metric` in `interval` was logged during workouts and how much in everyday life.
    func activitySplit(of metric: HealthMetric, in interval: DateInterval, filter: HealthFilter = .none) async throws -> ActivitySplit {
        if case .heartMinutes = metric, Self.isAvailable, interval.duration > 0 {
            return try await reading(metric) {
                let scope = try await self.scope(for: metric, filter: HealthFilter(sources: filter.sources))
                let fetch = DateInterval(start: interval.start.addingTimeInterval(-12 * 3600), end: interval.end)
                let spans = IntervalMath.merged(try await self.workouts(kinds: nil, in: fetch)
                    .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) })
                    .compactMap { $0.intersection(with: interval) }
                    .filter { $0.duration > 0 }
                let credits = try await self.heartMinutes(in: [interval] + spans, around: interval, scope: scope, markAll: true)
                return ActivitySplit(total: credits.first ?? 0, duringWorkouts: credits.dropFirst().reduce(0, +))
            }
        }
        guard Self.isAvailable, let type = metric.quantityType, interval.duration > 0 else { return ActivitySplit() }
        return try await reading(metric) {
            let scope = try await self.scope(for: metric, filter: HealthFilter(sources: filter.sources))
            var split = ActivitySplit(total: try await self.sum(type, unit: metric.hkUnit, in: interval, scope: scope))
            // A workout that started the evening before can run into the period.
            let fetch = DateInterval(start: interval.start.addingTimeInterval(-12 * 3600), end: interval.end)
            let spans = IntervalMath.merged(try await self.workouts(kinds: nil, in: fetch)
                .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) })
                .compactMap { $0.intersection(with: interval) }
                .filter { $0.duration > 0 }
            for span in spans {
                split.duringWorkouts += try await self.sum(type, unit: metric.hkUnit, in: span, scope: scope)
            }
            return split
        }
    }

    /// The nights that end inside `interval` (counted on the day you wake up), newest first.
    func nights(in interval: DateInterval, calendar: Calendar, filter: HealthFilter = .none) async throws -> [LoggedNight] {
        guard Self.isAvailable else { return [] }
        return try await reading(.sleep) {
            let scope = try await self.scope(for: .sleep, filter: filter)
            let fetch = DateInterval(start: interval.start.addingTimeInterval(-24 * 3600),
                                     end: interval.end.addingTimeInterval(18 * 3600))
            let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let samples = try await self.categorySamples(.sleepAnalysis, in: fetch, scope: scope)
                .filter { asleepValues.contains($0.value) }
                .map { sample in
                    (interval: sample.interval, stage: SleepStage.allCases.first { $0.categoryValue.rawValue == sample.value })
                }
            let first = calendar.startOfDay(for: interval.start)
            return LoggedNight.make(samples)
                .filter { $0.day(calendar: calendar) >= first && $0.day(calendar: calendar) < interval.end }
                .reversed()
        }
    }

    /// Heart rate and `metric` minute by minute through a workout. Asks for heart rate access the first time.
    func workoutTimeline(of metric: HealthMetric, in interval: DateInterval,
                         filter: HealthFilter = .none) async throws -> WorkoutTimeline {
        guard Self.isAvailable, interval.duration > 0 else { return WorkoutTimeline() }
        let heartRateType = HKQuantityType(.heartRate)
        try? await requestAuthorization(types: [heartRateType])
        var timeline = WorkoutTimeline()
        let scope = try await self.scope(for: metric, filter: HealthFilter(sources: filter.sources))
        if let type = metric.quantityType {
            timeline.perMinute = try await series(type, unit: metric.hkUnit, options: .cumulativeSum, in: interval,
                                                  step: DateComponents(minute: 1), scope: scope, fillsGaps: true)
        } else if case .heartMinutes = metric {
            // Heart Minutes earned minute by minute through the workout.
            var minutes: [DateInterval] = []
            var t = interval.start
            while t < interval.end {
                minutes.append(DateInterval(start: t, end: min(interval.end, t.addingTimeInterval(60))))
                t = t.addingTimeInterval(60)
            }
            let credits = try await heartMinutes(in: minutes, around: interval, scope: scope, markAll: true)
            timeline.perMinute = zip(minutes, credits).map { .init(date: $0.start, value: $1) }
        }
        // Heart rate every 30 seconds for an hour and a half, every minute for longer workouts.
        let step = interval.duration <= 90 * 60 ? DateComponents(second: 30) : DateComponents(minute: 1)
        timeline.heartRate = (try? await series(heartRateType, unit: .count().unitDivided(by: .minute()),
                                                options: .discreteAverage, in: interval, step: step, scope: Scope(),
                                                fillsGaps: false)) ?? []
        return timeline
    }

    /// Average heart rate through `interval` (a night: every 2 minutes). Asks for heart rate access the first time.
    func heartRate(in interval: DateInterval) async throws -> [WorkoutTimeline.Point] {
        guard Self.isAvailable, interval.duration > 0 else { return [] }
        let type = HKQuantityType(.heartRate)
        try? await requestAuthorization(types: [type])
        let step = interval.duration <= 90 * 60 ? DateComponents(second: 30)
            : interval.duration <= 4 * 3600 ? DateComponents(minute: 1) : DateComponents(minute: 2)
        return (try? await series(type, unit: .count().unitDivided(by: .minute()), options: .discreteAverage,
                                  in: interval, step: step, scope: Scope(), fillsGaps: false)) ?? []
    }

    /// A quantity per step through `interval`: sums, or averages for discrete types.
    private func series(_ type: HKQuantityType, unit: HKUnit, options: HKStatisticsOptions, in interval: DateInterval,
                        step: DateComponents, scope: Scope, fillsGaps: Bool) async throws -> [WorkoutTimeline.Point] {
        let predicate = scope.apply(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: options,
            anchorDate: interval.start, intervalComponents: step)
        var points: [WorkoutTimeline.Point] = []
        do {
            let collection = try await descriptor.result(for: store)
            collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                let quantity = options.contains(.discreteAverage) ? statistics.averageQuantity() : statistics.sumQuantity()
                if let value = quantity?.doubleValue(for: unit) {
                    points.append(.init(date: statistics.startDate, value: value))
                } else if fillsGaps {
                    points.append(.init(date: statistics.startDate, value: 0))
                }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
        return points
    }

    // MARK: Reading

    /// Runs a read, treating "no data" as nothing, and asking for access once if it was never asked for (e.g. the
    /// request failed while a sheet was closing).
    private func reading<T>(_ metric: HealthMetric, _ read: () async throws -> T) async throws -> T where T: EmptyableResult {
        do {
            return try await read()
        } catch let error as HKError where error.code == .errorNoData {
            return T.empty
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            try await requestAuthorization(for: [metric])
            do { return try await read() } catch let error as HKError where error.code == .errorNoData { return T.empty }
        }
    }

    private enum Bucket { case whole, day, hour }

    /// What a read is limited to.
    private struct Scope {
        /// `nil`: every source.
        var sources: Set<HKSource>?
        var minimumWorkoutDuration: TimeInterval = 0
        /// 0: no limit.
        var maximumWorkoutDuration: TimeInterval = 0
        var leftOutWorkouts: [WorkoutKind] = []
        var activity: ActivityScope = .all

        func apply(_ predicate: NSPredicate) -> NSPredicate {
            guard let sources else { return predicate }
            return NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, HKQuery.predicateForObjects(from: sources)])
        }
    }

    private func scope(for metric: HealthMetric, filter: HealthFilter) async throws -> Scope {
        var scope = Scope(minimumWorkoutDuration: Double(filter.minimumWorkoutMinutes) * 60,
                          maximumWorkoutDuration: Double(filter.maximumWorkoutMinutes) * 60,
                          leftOutWorkouts: filter.leftOutWorkouts,
                          activity: filter.activity)
        if !filter.sources.isEmpty, let type = metric.sampleType {
            let wanted = Set(filter.sources)
            scope.sources = try await sources(of: type).filter { wanted.contains($0.bundleIdentifier) }
        }
        return scope
    }

    private func sources(of type: HKSampleType) async throws -> Set<HKSource> {
        Set(try await HKSourceQueryDescriptor(predicate: .sample(type: type)).result(for: store))
    }

    /// The metric's values in `range`, summed per bucket (keyed by the bucket's start; `.whole`: by `range.start`).
    private func read(_ metric: HealthMetric, filter: HealthFilter, in range: DateInterval, by bucket: Bucket,
                      calendar: Calendar) async throws -> [Date: Double] {
        let scope = try await self.scope(for: metric, filter: filter)
        func key(_ date: Date) -> Date {
            switch bucket {
            case .whole: range.start
            case .day: calendar.startOfDay(for: date)
            case .hour: calendar.dateInterval(of: .hour, for: date)?.start ?? date
            }
        }
        func counted<S: HKSample>(_ samples: [S], value: (S) -> Double = { _ in 1 }) -> [Date: Double] {
            samples.reduce(into: [:]) { result, sample in result[key(sample.startDate), default: 0] += value(sample) }
        }

        if case .heartMinutes = metric {
            // Buckets: the whole range, each day or each hour.
            var buckets: [DateInterval] = []
            if bucket == .whole {
                buckets = [range]
            } else {
                var t = range.start
                while t < range.end {
                    let next = calendar.date(byAdding: bucket == .day ? .day : .hour, value: 1, to: t) ?? range.end
                    buckets.append(DateInterval(start: t, end: min(next, range.end)))
                    t = next
                }
            }
            let credits = try await heartMinutes(in: buckets, around: range, scope: scope, markAll: false)
            return Dictionary(zip(buckets.map { key($0.start) }, credits), uniquingKeysWith: +)
        }
        if let type = metric.quantityType {
            // Health doesn't tie samples to workouts: what was logged while a workout ran belongs to it.
            func workoutSpans(_ filter: WorkoutFilter?, lengths: Bool) async throws -> [DateInterval] {
                let fetch = DateInterval(start: range.start.addingTimeInterval(-12 * 3600), end: range.end)
                // Workouts from any source (the ring's sources are for its samples), within the ring's lengths.
                var limits = Scope()
                if lengths {
                    limits.minimumWorkoutDuration = scope.minimumWorkoutDuration
                    limits.maximumWorkoutDuration = scope.maximumWorkoutDuration
                }
                return IntervalMath.merged(try await workouts(filter: filter, in: fetch, scope: limits)
                    .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) })
                    .compactMap { $0.intersection(with: range) }
                    .filter { $0.duration > 0 }
            }
            switch scope.activity {
            case .duringWorkouts:
                // Only what was logged while workouts ran (except the left-out kinds).
                var result: [Date: Double] = [:]
                for span in try await workoutSpans(WorkoutFilter.make(scope.leftOutWorkouts, excludes: true), lengths: true) {
                    result[key(span.start), default: 0] += try await sum(type, unit: metric.hkUnit, in: span, scope: scope)
                }
                return result
            case .outsideWorkouts, .all:
                var result = try await quantities(type, unit: metric.hkUnit, in: range, by: bucket, scope: scope, key: key)
                // Everyday activity: leave out every workout; otherwise only the left-out kinds.
                let spans: [DateInterval]
                if scope.activity == .outsideWorkouts {
                    spans = try await workoutSpans(nil, lengths: true)
                } else if !scope.leftOutWorkouts.isEmpty {
                    spans = try await workoutSpans(WorkoutFilter.make(scope.leftOutWorkouts), lengths: false)
                } else {
                    spans = []
                }
                for span in spans {
                    let during = try await sum(type, unit: metric.hkUnit, in: span, scope: scope)
                    result[key(span.start)] = max(0, (result[key(span.start)] ?? 0) - during)
                }
                return result
            }
        }

        switch metric {
        case .events(let kind):
            return counted(try await categorySamples(kind.identifier, in: range, scope: scope, strictStart: true))
        case .sensitive(let kind):
            guard let identifier = kind.categoryIdentifier else { return [:] }
            let entries = try await categorySamples(identifier, in: range, scope: scope, strictStart: true)
                .filter { kind.counts($0.value) }
            return counted(entries)
        case .standHours:
            let stood = try await categorySamples(.appleStandHour, in: range, scope: scope, strictStart: true)
                .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
            return counted(stood)
        case .mindfulMinutes:
            let sessions = try await categorySamples(.mindfulSession, in: range, scope: scope).map(\.interval)
            switch bucket {
            case .whole: return [range.start: IntervalMath.covered(sessions, within: range) / 60]
            case .day:
                return IntervalMath.coveredByDay(sessions, calendar: calendar)
                    .filter { range.contains($0.key) }.mapValues { $0 / 60 }
            case .hour: return [:]
            }
        case .sleep, .sleepStage:
            guard bucket != .hour else { return [:] }
            // A night belongs to the day you wake up: look back far enough to catch its start, and a bit past the end
            // so a night still in progress at the end of the period isn't cut in two.
            let fetch = DateInterval(start: range.start.addingTimeInterval(-24 * 3600), end: range.end.addingTimeInterval(18 * 3600))
            let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let samples = try await categorySamples(.sleepAnalysis, in: fetch, scope: scope)
            let asleep = samples.filter { asleepValues.contains($0.value) }.map(\.interval)
            var seconds: [Date: TimeInterval]
            if case .sleepStage(let stage) = metric {
                let stageIntervals = samples.filter { $0.value == stage.categoryValue.rawValue }.map(\.interval)
                seconds = bucket == .whole
                    ? [range.start: IntervalMath.stage(stageIntervals, asleep: asleep, attributedTo: range)]
                    : IntervalMath.stageByDay(stageIntervals, asleep: asleep, calendar: calendar)
            } else {
                seconds = bucket == .whole
                    ? [range.start: IntervalMath.asleep(asleep, attributedTo: range)]
                    : IntervalMath.asleepByDay(asleep, calendar: calendar)
            }
            if bucket == .day { seconds = seconds.filter { range.contains($0.key) } }
            return seconds.mapValues { $0 / 3600 }
        case .workouts(let measure, let filter):
            let workouts = try await workouts(filter: filter, in: range, scope: scope)
            return counted(workouts) { workout in
                switch measure {
                case .count: 1
                case .minutes: workout.duration / 60
                case .distance: Self.distance(of: workout)
                }
            }
        default:
            return [:]
        }
    }

    private static func distance(of workout: HKWorkout) -> Double {
        HealthMetric.workoutDistanceTypes.reduce(0) { sum, type in
            sum + (workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0)
        }
    }

    // MARK: Heart Minutes

    /// Heart Minutes in each of `buckets` (all inside `range`), calculated like the Heart Minutes app: heart rate
    /// measurements with workouts and Exercise-ring minutes marked.
    /// - Parameter markAll: every workout counts as a workout and every measurement counts (for the workout list and
    ///   the split); otherwise the scope's activity, left-out kinds and workout lengths decide.
    private func heartMinutes(in buckets: [DateInterval], around range: DateInterval, scope: Scope,
                              markAll: Bool) async throws -> [Double] {
        guard !buckets.isEmpty else { return [] }
        // A little margin: the calculation looks at the measurements around each edge.
        let margin: TimeInterval = 15 * 60
        let samples = try await heartRates(in: DateInterval(start: range.start.addingTimeInterval(-margin),
                                                            end: range.end.addingTimeInterval(margin)), scope: scope)
        guard !samples.isEmpty else { return buckets.map { _ in 0 } }
        let all = try await workouts(filter: nil, in: DateInterval(start: range.start.addingTimeInterval(-12 * 3600),
                                                                   end: range.end.addingTimeInterval(margin)))
        func span(_ w: HKWorkout) -> DateInterval { DateInterval(start: w.startDate, end: max(w.startDate, w.endDate)) }
        func withinLengths(_ w: HKWorkout) -> Bool {
            w.duration >= scope.minimumWorkoutDuration
                && (scope.maximumWorkoutDuration <= 0 || w.duration <= scope.maximumWorkoutDuration)
        }
        let leftOut = Set(scope.leftOutWorkouts)
        func isLeftOut(_ w: HKWorkout) -> Bool { WorkoutKind(activityType: w.workoutActivityType).map { leftOut.contains($0) } ?? false }
        let exercise = try await exerciseSamples(in: DateInterval(start: range.start.addingTimeInterval(-margin),
                                                                  end: range.end.addingTimeInterval(margin))).map(\.interval)
        let marked: [DateInterval]
        let keep: (HRSample) -> Bool
        if markAll {
            marked = all.map(span)
            keep = { _ in true }
        } else {
            switch scope.activity {
            case .all:
                marked = all.map(span)
                // Measurements during the left-out kinds don't count.
                let out = all.filter(isLeftOut).map(span)
                keep = { sample in !out.contains { $0.contains(sample.date) } }
            case .duringWorkouts:
                marked = all.filter { withinLengths($0) && !isLeftOut($0) }.map(span)
                keep = { $0.inWorkout }
            case .outsideWorkouts:
                marked = all.filter(withinLengths).map(span)
                keep = { !$0.inWorkout }
            }
        }
        return HeartMinuteSettings.credits(samples: samples, workouts: marked, exercise: exercise, buckets: buckets,
                                           settings: heartMinuteSettings, keep: keep)
    }

    /// Exercise-ring minutes (usually one sample per minute).
    private func exerciseSamples(in interval: DateInterval) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.appleExerciseTime), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    /// Heart rate measurements, sorted, with Apple's active/resting marking. Series (one entry with many values, as
    /// Apple Watch stores workout heart rate) are unpacked, so no values are lost.
    private func heartRates(in interval: DateInterval, scope: Scope) async throws -> [HRSample] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = scope.apply(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        var result: [HRSample] = []
        for sample in try await descriptor.result(for: store) {
            let motion = MotionContext(sample.metadata)
            let source = sample.sourceRevision.source.name
            if let discrete = sample as? HKDiscreteQuantitySample, discrete.count > 1 {
                result += try await seriesValues(of: sample).map {
                    HRSample(date: $0.date, bpm: $0.bpm, motion: motion, source: source)
                }
            } else {
                result.append(HRSample(date: sample.startDate, bpm: sample.quantity.doubleValue(for: unit),
                                       motion: motion, source: source))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// The individual heart rate values in a series entry.
    private func seriesValues(of sample: HKQuantitySample) async throws -> [(date: Date, bpm: Double)] {
        try await withCheckedThrowingContinuation { continuation in
            let box = SeriesBox()
            let query = HKQuantitySeriesSampleQuery(sample: sample) { _, quantity, date, done, error in
                if let error {
                    box.finish { continuation.resume(throwing: error) }
                    return
                }
                if let quantity, let date {
                    box.append(date: date, bpm: quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                }
                if done { box.finish { continuation.resume(returning: box.values) } }
            }
            store.execute(query)
        }
    }

    // MARK: Queries

    /// Sums of a quantity per bucket (Health's statistics, which don't double count overlapping sources).
    private func quantities(_ type: HKQuantityType, unit: HKUnit, in range: DateInterval, by bucket: Bucket,
                            scope: Scope, key: @escaping (Date) -> Date) async throws -> [Date: Double] {
        let step: DateComponents
        switch bucket {
        case .whole: return [range.start: try await sum(type, unit: unit, in: range, scope: scope)]
        case .day: step = DateComponents(day: 1)
        case .hour: step = DateComponents(hour: 1)
        }
        let predicate = scope.apply(HKQuery.predicateForSamples(withStart: range.start, end: range.end))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum,
            anchorDate: range.start, intervalComponents: step)
        var result: [Date: Double] = [:]
        do {
            let collection = try await descriptor.result(for: store)
            collection.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                if let sum = statistics.sumQuantity()?.doubleValue(for: unit) {
                    result[key(statistics.startDate), default: 0] += sum
                }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return [:]
        }
        return result
    }

    private func sum(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval, scope: Scope) async throws -> Double {
        let predicate = scope.apply(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum)
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        }
    }

    private func categorySamples(_ identifier: HKCategoryTypeIdentifier, in interval: DateInterval, scope: Scope,
                                 strictStart: Bool = false) async throws -> [HKCategorySample] {
        let predicate = scope.apply(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end,
                                                                options: strictStart ? .strictStartDate : []))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    /// Workouts that start inside `interval`: all, only some kinds, or all but some, at least as long as the scope's
    /// minimum.
    private func workouts(filter: WorkoutFilter?, in interval: DateInterval, scope: Scope = Scope()) async throws -> [HKWorkout] {
        var predicates = [HKQuery.predicateForSamples(withStart: interval.start, end: interval.end,
                                                      options: .strictStartDate)]
        if let filter {
            let kinds = NSCompoundPredicate(orPredicateWithSubpredicates:
                filter.kinds.flatMap(\.activityTypes).map { HKQuery.predicateForWorkouts(with: $0) })
            predicates.append(filter.excludes ? NSCompoundPredicate(notPredicateWithSubpredicate: kinds) : kinds)
        }
        let predicate = scope.apply(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = try await descriptor.result(for: store)
        return workouts.filter { workout in
            workout.duration >= scope.minimumWorkoutDuration
                && (scope.maximumWorkoutDuration <= 0 || workout.duration <= scope.maximumWorkoutDuration)
        }
    }

    /// Workouts of `kinds` (all workouts for `nil`) that start inside `interval`, from any source.
    private func workouts(kinds: [WorkoutKind]?, in interval: DateInterval) async throws -> [HKWorkout] {
        try await workouts(filter: kinds.flatMap { WorkoutFilter.make($0) }, in: interval)
    }
}

/// What a read returns when Health has no data.
protocol EmptyableResult {
    static var empty: Self { get }
}

extension Dictionary: EmptyableResult { static var empty: Self { [:] } }
extension Array: EmptyableResult { static var empty: Self { [] } }
extension Set: EmptyableResult { static var empty: Self { [] } }
extension ActivitySplit: EmptyableResult { static var empty: Self { ActivitySplit() } }

private extension HKSample {
    var interval: DateInterval { DateInterval(start: startDate, end: max(startDate, endDate)) }
}

extension MotionContext {
    /// From HKMetadataKeyHeartRateMotionContext on Apple Watch measurements.
    init(_ metadata: [String: Any]?) {
        guard let raw = (metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue,
              let context = HKHeartRateMotionContext(rawValue: raw) else { self = .unknown; return }
        switch context {
        case .sedentary: self = .sedentary
        case .active: self = .active
        default: self = .unknown
        }
    }
}

/// Collects values from a series query (HealthKit calls back from a background thread).
private final class SeriesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private(set) var values: [(date: Date, bpm: Double)] = []

    func append(date: Date, bpm: Double) {
        lock.lock(); values.append((date, bpm)); lock.unlock()
    }

    /// Only runs the first time (so the continuation is never resumed twice).
    func finish(_ body: () -> Void) {
        lock.lock(); let first = !finished; finished = true; lock.unlock()
        if first { body() }
    }
}
