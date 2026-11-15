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
        case .standHours, .workouts, .sleep, .mindfulMinutes: nil
        }
    }

    /// Everything this metric needs read access to.
    var readTypes: Set<HKObjectType> {
        if let quantityType { return [quantityType] }
        switch self {
        case .standHours: return [HKCategoryType(.appleStandHour)]
        case .sleep: return [HKCategoryType(.sleepAnalysis)]
        case .mindfulMinutes: return [HKCategoryType(.mindfulSession)]
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
         HKQuantityType(.distanceWheelchair), HKQuantityType(.distanceRowing)]
    }

    var hkUnit: HKUnit {
        switch baseUnit {
        case .count: .count()
        case .kilocalories: .kilocalorie()
        case .minutes: .minute()
        case .hours: .hour()
        case .meters: .meter()
        case .liters: .liter()
        }
    }
}

extension WorkoutKind {
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
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// The ring's value over `interval`, in `metric.baseUnit`. Missing data (or no access, which HealthKit doesn't
    /// reveal for reading) counts as zero.
    func value(of metric: HealthMetric, in interval: DateInterval) async throws -> Double {
        guard Self.isAvailable else { return 0 }
        if let type = metric.quantityType {
            return try await sum(type, unit: metric.hkUnit, in: interval)
        }
        switch metric {
        case .standHours:
            let samples = try await categorySamples(.appleStandHour, in: interval, strictStart: true)
            return Double(samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count)
        case .mindfulMinutes:
            let samples = try await categorySamples(.mindfulSession, in: interval)
            return IntervalMath.covered(samples.map(\.interval), within: interval) / 60
        case .sleep:
            // A night belongs to the day you wake up: look back far enough to catch its start, and a bit past the end
            // so a night still in progress at the end of the period isn't cut in two.
            let fetch = DateInterval(start: interval.start.addingTimeInterval(-24 * 3600),
                                     end: interval.end.addingTimeInterval(18 * 3600))
            let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let samples = try await categorySamples(.sleepAnalysis, in: fetch)
                .filter { asleep.contains($0.value) }
            return IntervalMath.asleep(samples.map(\.interval), attributedTo: interval) / 3600
        case .workouts(let measure, let kind):
            let workouts = try await workouts(kind: kind, in: interval)
            switch measure {
            case .count: return Double(workouts.count)
            case .minutes: return workouts.reduce(0) { $0 + $1.duration } / 60
            case .distance:
                return workouts.reduce(0) { total, workout in
                    total + HealthMetric.workoutDistanceTypes.reduce(0) { sum, type in
                        sum + (workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0)
                    }
                }
            }
        default:
            return 0
        }
    }

    /// The metric's value per calendar day from `start` up to `end`, keyed by start of day (days without data are
    /// missing). One query for the whole range: daily statistics for quantities, samples bucketed by day otherwise.
    func dailyValues(of metric: HealthMetric, from start: Date, to end: Date,
                     calendar: Calendar) async throws -> [Date: Double] {
        guard Self.isAvailable, start < end else { return [:] }
        let range = DateInterval(start: calendar.startOfDay(for: start), end: end)
        if let type = metric.quantityType {
            let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum,
                anchorDate: range.start, intervalComponents: DateComponents(day: 1))
            var result: [Date: Double] = [:]
            do {
                let collection = try await descriptor.result(for: store)
                collection.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: metric.hkUnit) {
                        result[calendar.startOfDay(for: statistics.startDate), default: 0] += sum
                    }
                }
            } catch let error as HKError where error.code == .errorNoData {
                return [:]
            }
            return result
        }
        switch metric {
        case .standHours:
            let stood = try await categorySamples(.appleStandHour, in: range, strictStart: true)
                .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
            return Dictionary(grouping: stood) { calendar.startOfDay(for: $0.startDate) }.mapValues { Double($0.count) }
        case .mindfulMinutes:
            let samples = try await categorySamples(.mindfulSession, in: range)
            return IntervalMath.coveredByDay(samples.map(\.interval), calendar: calendar)
                .filter { $0.key >= range.start }
                .mapValues { $0 / 60 }
        case .sleep:
            let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let fetch = DateInterval(start: range.start.addingTimeInterval(-24 * 3600),
                                     end: range.end.addingTimeInterval(18 * 3600))
            let samples = try await categorySamples(.sleepAnalysis, in: fetch).filter { asleep.contains($0.value) }
            return IntervalMath.asleepByDay(samples.map(\.interval), calendar: calendar)
                .filter { $0.key >= range.start && $0.key < range.end }
                .mapValues { $0 / 3600 }
        case .workouts(let measure, let kind):
            let workouts = try await workouts(kind: kind, in: range)
            return Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.startDate) }.mapValues { list in
                switch measure {
                case .count: Double(list.count)
                case .minutes: list.reduce(0) { $0 + $1.duration } / 60
                case .distance: list.reduce(0) { $0 + Self.distance(of: $1) }
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

    private func sum(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum)
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        }
    }

    private func categorySamples(_ identifier: HKCategoryTypeIdentifier, in interval: DateInterval,
                                 strictStart: Bool = false) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end,
                                                    options: strictStart ? .strictStartDate : [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    /// Workouts that start inside `interval`, optionally of one kind.
    private func workouts(kind: WorkoutKind?, in interval: DateInterval) async throws -> [HKWorkout] {
        var predicates = [HKQuery.predicateForSamples(withStart: interval.start, end: interval.end,
                                                      options: .strictStartDate)]
        if let kind {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates:
                kind.activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }))
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }
}

private extension HKSample {
    var interval: DateInterval { DateInterval(start: startDate, end: max(startDate, endDate)) }
}
