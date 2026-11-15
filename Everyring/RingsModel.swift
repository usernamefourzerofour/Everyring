import Foundation
import Observation
import WidgetKit

/// The app's state: the ring library and the latest value per ring.
@MainActor
@Observable
final class RingsModel {
    var library: RingLibrary {
        didSet {
            guard library != oldValue else { return }
            try? RingStore.save(library)
            WidgetCenter.shared.reloadAllTimelines()
            BackgroundUpdater.shared.start(library: library)
            #if os(iOS)
            PhoneSync.shared.send(library)
            #endif
            Task { await refresh() }
        }
    }
    /// Latest value per ring, in the metric's base unit.
    private(set) var values: [Ring.ID: Double] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?

    private let health: HealthManager
    private var needsRefresh = false

    /// Launch with `-demo YES` to show made-up values (simulator, screenshots).
    static var isDemo: Bool { UserDefaults.standard.bool(forKey: "demo") }

    init(library: RingLibrary? = nil, health: HealthManager? = nil) {
        let stored = RingStore.load()
        self.health = health ?? .shared
        #if os(watchOS)
        // The watch shows the iPhone's rings; until they arrive it has none.
        self.library = library ?? stored ?? (Self.isDemo ? .starter : RingLibrary(sets: []))
        #else
        self.library = library ?? stored ?? .starter
        // Save the starter set on first launch so the widgets (and the watch) can read it.
        if library == nil, stored == nil { try? RingStore.save(self.library) }
        PhoneSync.shared.activate()
        #endif
        BackgroundUpdater.shared.start(library: self.library)
    }

    var calendar: Calendar { library.calendar() }

    func value(for ring: Ring) -> Double { values[ring.id] ?? 0 }

    func displays(for set: RingSet) -> [RingDisplay] {
        set.rings.map { RingDisplay(id: $0.id, color: $0.color, fraction: $0.fraction(value(for: $0))) }
    }

    // MARK: Lookup and editing

    func ring(id: Ring.ID) -> Ring? {
        library.sets.lazy.flatMap(\.rings).first { $0.id == id }
    }

    /// Adds the set, or replaces the set with the same id.
    func save(_ set: RingSet) {
        if let index = library.sets.firstIndex(where: { $0.id == set.id }) {
            library.sets[index] = set
        } else {
            library.sets.append(set)
        }
    }

    func deleteSet(id: RingSet.ID) {
        library.sets.removeAll { $0.id == id }
    }

    func update(_ ring: Ring) {
        for s in library.sets.indices {
            if let r = library.sets[s].rings.firstIndex(where: { $0.id == ring.id }) {
                library.sets[s].rings[r] = ring
            }
        }
    }

    func deleteRing(id: Ring.ID) {
        for s in library.sets.indices {
            library.sets[s].rings.removeAll { $0.id == id }
        }
    }

    // MARK: Health

    /// Asks for Health access for all metrics in use and reloads every ring.
    func refresh(now: Date = .now) async {
        guard !isLoading else {
            needsRefresh = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            if needsRefresh {
                needsRefresh = false
                Task { await refresh() }
            }
        }
        let library = library
        do {
            let snapshots: [Ring.ID: RingSnapshot]
            if Self.isDemo {
                snapshots = demoSnapshots(now: now)
            } else {
                try await health.requestAuthorization(for: library.sets.flatMap(\.rings).map(\.metric))
                snapshots = try await ProgressUpdater.snapshots(for: library, now: now, health: health)
            }
            values = snapshots.mapValues(\.value)
            lastUpdated = now
            error = nil
            // With the app open the value may go down (e.g. deleted samples).
            ProgressUpdater.store(snapshots, library: library, allowDecrease: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static let demoFractions = [0.72, 1.24, 0.46, 1.0, 0.31]

    private func demoSnapshots(now: Date) -> [Ring.ID: RingSnapshot] {
        var result: [Ring.ID: RingSnapshot] = [:]
        for set in library.sets {
            for (index, ring) in set.rings.enumerated() {
                let interval = ring.period.interval(now: now, calendar: calendar)
                result[ring.id] = RingSnapshot(value: ring.goal * Self.demoFractions[index % 5],
                                               intervalStart: interval.start, intervalEnd: interval.end, updated: now)
            }
        }
        return result
    }

    /// Current and best streak, from Health data for the last `period.streakLookback` periods. `nil` on failure.
    func streak(for ring: Ring, now: Date = .now) async -> Streak? {
        if Self.isDemo { return Streak(current: 4, best: 9) }
        let calendar = calendar
        do {
            let current = try await health.value(of: ring.metric, in: ring.period.interval(now: now, calendar: calendar))
            var finished: [Bool] = []
            for interval in ring.period.history(now: now, count: ring.period.streakLookback, calendar: calendar) {
                let value = try await health.value(of: ring.metric, in: interval)
                finished.append(Streak.isClosed(value: value, goal: ring.goal))
            }
            return Streak(finished: finished, inProgress: Streak.isClosed(value: current, goal: ring.goal))
        } catch {
            return nil
        }
    }
}
