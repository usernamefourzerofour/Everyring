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
        case .standHours, .workouts, .sleep, .sleepStage, .mindfulMinutes, .events: nil
        }
    }

    /// The type of sample the metric reads, for listing its sources.
    var sampleType: HKSampleType? {
        if let quantityType { return quantityType }
        switch self {
        case .standHours: return HKCategoryType(.appleStandHour)
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

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for read access to the types `metrics` need. HealthKit only shows the sheet for types not asked for before,
    /// so this is cheap to call whenever a ring is added.
    func requestAuthorization(for metrics: some Sequence<HealthMetric>) async throws {
        guard Self.isAvailable else { return }
        let types = metrics.reduce(into: Set<HKObjectType>()) { $0.formUnion($1.readTypes) }
        guard !types.isEmpty else { return }
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
        var leftOutWorkouts: [WorkoutKind] = []

        func apply(_ predicate: NSPredicate) -> NSPredicate {
            guard let sources else { return predicate }
            return NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, HKQuery.predicateForObjects(from: sources)])
        }
    }

    private func scope(for metric: HealthMetric, filter: HealthFilter) async throws -> Scope {
        var scope = Scope(minimumWorkoutDuration: Double(filter.minimumWorkoutMinutes) * 60,
                          leftOutWorkouts: filter.leftOutWorkouts)
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

        if let type = metric.quantityType {
            var result = try await quantities(type, unit: metric.hkUnit, in: range, by: bucket, scope: scope, key: key)
            // Leave out what was logged while workouts of the left-out kinds ran (Health doesn't tie it to them).
            if !scope.leftOutWorkouts.isEmpty {
                let fetch = DateInterval(start: range.start.addingTimeInterval(-12 * 3600), end: range.end)
                let spans = IntervalMath.merged(try await workouts(kinds: scope.leftOutWorkouts, in: fetch)
                    .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) })
                    .compactMap { $0.intersection(with: range) }
                    .filter { $0.duration > 0 }
                for span in spans {
                    let during = try await sum(type, unit: metric.hkUnit, in: span, scope: scope)
                    result[key(span.start)] = max(0, (result[key(span.start)] ?? 0) - during)
                }
            }
            return result
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

    // MARK: Queries

    /// Sums of a quantity per bucket (Health's statistics, which don't double count overlapping sources).
    private func quantities(_ type: HKQuantityType, unit: HKUnit, in range: DateInterval, by bucket: Bucket,
                            scope: Scope, key: (Date) -> Date) async throws -> [Date: Double] {
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
        return scope.minimumWorkoutDuration > 0 ? workouts.filter { $0.duration >= scope.minimumWorkoutDuration } : workouts
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

private extension HKSample {
    var interval: DateInterval { DateInterval(start: startDate, end: max(startDate, endDate)) }
}
