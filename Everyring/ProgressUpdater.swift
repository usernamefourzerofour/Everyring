import Foundation
import HealthKit
import WidgetKit

/// Computes every ring's value from Health and writes it to the App Group cache for the widgets.
@MainActor
enum ProgressUpdater {
    /// The result of reading every ring: the rings that could be read, and the ones that couldn't (with why).
    struct Result {
        var snapshots: [Ring.ID: RingSnapshot] = [:]
        var failures: [(ring: Ring, error: Error)] = []
    }

    /// Reads each ring on its own, so one ring that can't be read (a Health error for one type) never stops the others.
    static func snapshots(for library: RingLibrary, now: Date = .now, health: HealthManager? = nil) async -> Result {
        let health = health ?? .shared
        health.heartMinuteSettings = library.heartMinutes
        let calendar = library.calendar()
        var result = Result()
        for ring in library.sets.flatMap(\.rings) {
            let interval = ring.period.interval(now: now, calendar: calendar)
            let chart = PeriodProgress.chartInterval(for: ring, now: now, calendar: calendar)
            let end = max(interval.start, min(interval.end, now))
            func chartPoints(_ buckets: [Date: Double], bucketSize: Calendar.Component? = nil) -> [ChartPoint] {
                ChartPoint.reduced(PeriodProgress.make(for: ring, buckets: buckets, interval: chart, now: now, calendar: calendar,
                                                       bucketSize: bucketSize)
                    .points.map { ChartPoint(t: $0.date, v: $0.total) })
            }
            do {
                let value: Double
                var points: [ChartPoint]?
                if PeriodProgress.bucket(for: ring.period) == .day {
                    // Periods of several days: one value per day gives both the value and the chart (and counts days one
                    // by one where the ring needs it: left-out days, days reaching a target, days with data).
                    let daily = try await health.dailyValues(of: ring.metric, from: interval.start, to: end,
                                                             calendar: calendar, filter: ring.healthFilter)
                    value = ring.measure(daily: daily, in: interval, now: now, calendar: calendar)
                    // The chart hour by hour, like Heart Minutes' widget, for totals (an average or a count of days is a
                    // daily figure, so it stays day by day).
                    if !ring.isAverage, !ring.isDaysReaching, ring.metric.hasHourlyBuildUp,
                       let hourly = try? await health.hourlyValues(of: ring.metric, in: DateInterval(start: interval.start, end: end),
                                                                   calendar: calendar, filter: ring.healthFilter) {
                        points = chartPoints(hourly, bucketSize: .hour)
                    } else {
                        points = chartPoints(daily)
                    }
                } else {
                    let total = try await health.value(of: ring.metric, in: interval, filter: ring.healthFilter)
                    value = ring.measure(total, in: interval, now: now, calendar: calendar)
                    // One day: the chart builds up hour by hour (not for sleep and mindful minutes).
                    if ring.metric.hasHourlyBuildUp,
                       let hourly = try? await health.hourlyValues(of: ring.metric, in: DateInterval(start: interval.start, end: end),
                                                                   calendar: calendar, filter: ring.healthFilter) {
                        points = chartPoints(hourly)
                    }
                }
                result.snapshots[ring.id] = RingSnapshot(value: value, intervalStart: interval.start,
                                                         intervalEnd: interval.end, updated: now, points: points)
            } catch {
                result.failures.append((ring, error))
            }
        }
        return result
    }

    /// Merges into the cache and reloads widgets when anything changed.
    static func store(_ snapshots: [Ring.ID: RingSnapshot], library: RingLibrary, allowDecrease: Bool) {
        let old = ProgressCache.load()
        var cache = old
        cache.merge(snapshots, library: library, allowDecrease: allowDecrease)
        try? cache.save()
        // Only what widgets draw: the values and the charts (not when they were computed).
        func drawn(_ cache: ProgressCache) -> [Ring.ID: [Double]] {
            cache.rings.mapValues { [$0.value] + ($0.points?.map(\.v) ?? []) }
        }
        if drawn(cache) != drawn(old) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// Keeps the widget cache fresh while the app isn't running: an observer query per Health type in use, with
/// background delivery, recomputes the rings when new samples arrive.
@MainActor
final class BackgroundUpdater {
    static let shared = BackgroundUpdater()

    private var queries: [HKObserverQuery] = []
    private var observedTypes: Set<HKSampleType> = []
    private var lastUpdate = Date.distantPast
    private var store: HKHealthStore { HealthManager.shared.store }

    /// Starts (or restarts, when the rings use other types) the observers. Call at launch and after editing rings.
    func start(library: RingLibrary? = RingStore.load()) {
        guard HealthManager.isAvailable, let library else { return }
        let types = Set(library.sets.flatMap(\.rings).flatMap { $0.metric.readTypes.compactMap { $0 as? HKSampleType } })
        guard types != observedTypes else { return }

        queries.forEach { store.stop($0) }
        queries = []
        for type in observedTypes.subtracting(types) {
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await BackgroundUpdater.shared.update()
                    completion()
                }
            }
            store.execute(query)
            queries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
        observedTypes = types
    }

    /// Recomputes all rings, at most once a minute unless `force` (several types often change together).
    func update(now: Date = .now, force: Bool = false) async {
        guard force || now.timeIntervalSince(lastUpdate) > 60, let library = RingStore.load() else { return }
        lastUpdate = now
        // Health can't be read while the device is locked; then those rings keep their cached values.
        let snapshots = await ProgressUpdater.snapshots(for: library, now: now).snapshots
        guard !snapshots.isEmpty else { return }
        ProgressUpdater.store(snapshots, library: library, allowDecrease: false)
        if force { WidgetCenter.shared.reloadAllTimelines() }
    }
}
