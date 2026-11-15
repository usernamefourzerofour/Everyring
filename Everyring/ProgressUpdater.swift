import Foundation
import HealthKit
import WidgetKit

/// Computes every ring's value from Health and writes it to the App Group cache for the widgets.
@MainActor
enum ProgressUpdater {
    static func snapshots(for library: RingLibrary, now: Date = .now,
                          health: HealthManager = .shared) async throws -> [Ring.ID: RingSnapshot] {
        let calendar = library.calendar()
        var result: [Ring.ID: RingSnapshot] = [:]
        for ring in library.sets.flatMap(\.rings) {
            let interval = ring.period.interval(now: now, calendar: calendar)
            let value = try await health.value(of: ring.metric, in: interval)
            result[ring.id] = RingSnapshot(value: value, intervalStart: interval.start, intervalEnd: interval.end,
                                           updated: now)
        }
        return result
    }

    /// Merges into the cache and reloads widgets when anything changed.
    static func store(_ snapshots: [Ring.ID: RingSnapshot], library: RingLibrary, allowDecrease: Bool) {
        let old = ProgressCache.load()
        var cache = old
        cache.merge(snapshots, library: library, allowDecrease: allowDecrease)
        try? cache.save()
        if cache.rings.mapValues(\.value) != old.rings.mapValues(\.value) {
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

    /// Recomputes all rings, at most once a minute (several types often change together).
    func update(now: Date = .now) async {
        guard now.timeIntervalSince(lastUpdate) > 60, let library = RingStore.load() else { return }
        lastUpdate = now
        // Health can't be read while the device is locked; then the cache keeps its values.
        guard let snapshots = try? await ProgressUpdater.snapshots(for: library, now: now) else { return }
        ProgressUpdater.store(snapshots, library: library, allowDecrease: false)
    }
}
