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
            // Wait for an editor sheet to finish closing: Health can't show its access sheet over a closing one.
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                await refresh()
            }
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
        set.rings.map { $0.display(value(for: $0)) }
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
        let snapshots: [Ring.ID: RingSnapshot]
        if Self.isDemo {
            snapshots = demoSnapshots(now: now)
            error = nil
        } else {
            var problems: [String] = []
            do {
                try await health.requestAuthorization(for: library.sets.flatMap(\.rings).map(\.metric))
            } catch {
                // Rings with access granted earlier can still be read.
                problems.append(String(localized: "Health access: \(error.localizedDescription)"))
            }
            let result = await ProgressUpdater.snapshots(for: library, now: now, health: health)
            snapshots = result.snapshots
            problems += result.failures.map { "\($0.ring.name): \($0.error.localizedDescription)" }
            error = problems.isEmpty ? nil : problems.joined(separator: "\n")
        }
        // Rings that couldn't be read keep their last value.
        values.merge(snapshots.mapValues(\.value)) { $1 }
        values = values.filter { id, _ in library.sets.contains { $0.rings.contains { $0.id == id } } }
        lastUpdated = now
        celebrateClosedRings(snapshots)
        // With the app open the value may go down (e.g. deleted samples).
        ProgressUpdater.store(snapshots, library: library, allowDecrease: true)
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

    // MARK: History

    private struct DailyCache {
        var from: Date
        var fetched: Date
        var values: [Date: Double]
    }

    /// Daily values per metric, so opening a ring's details again doesn't re-read months of Health data.
    private var dailyCache: [HealthMetric: DailyCache] = [:]

    /// The ring's history and streak, from one daily-values query. `nil` if Health couldn't be read.
    func history(for ring: Ring, now: Date = .now) async -> RingHistory? {
        let calendar = calendar
        let start = RingHistory.requiredStart(for: ring, now: now, calendar: calendar)
        var daily: [Date: Double]
        if Self.isDemo {
            daily = DemoHistory.daily(for: ring, from: start, to: now, calendar: calendar)
            // Let the current period add up to the value on the home screen.
            let current = ring.period.interval(now: now, calendar: calendar)
            let days = (0..<ring.period.nominalDays).compactMap { calendar.date(byAdding: .day, value: $0, to: current.start) }
                .filter { $0 <= now }
            for day in days { daily[day] = value(for: ring) / Double(max(1, days.count)) }
        } else {
            do {
                daily = try await dailyValues(of: ring.metric, from: start, now: now, calendar: calendar)
            } catch {
                return nil
            }
        }
        let history = RingHistory.make(for: ring, daily: daily, now: now, calendar: calendar)
        // The current period from the history is as fresh as it gets: use it, so the ring and its history agree.
        if !Self.isDemo, let current = ring.period.isRolling ? history.days.last?.value : history.periods.first?.value {
            values[ring.id] = current
        }
        return history
    }

    /// One page of the ring's history (`offset` 0 = this month, or this year for monthly rings).
    func historyPage(for ring: Ring, offset: Int, now: Date = .now) async -> HistoryPage? {
        let calendar = calendar
        let range = HistoryPage.range(for: ring.period, offset: offset, now: now, calendar: calendar)
        let start = HistoryPage.requiredStart(for: ring, range: range, now: now, calendar: calendar)
        let daily: [Date: Double]
        if Self.isDemo {
            daily = DemoHistory.daily(for: ring, from: start, to: now, calendar: calendar)
        } else {
            do {
                daily = try await dailyValues(of: ring.metric, from: start, now: now, calendar: calendar)
            } catch {
                return nil
            }
        }
        return HistoryPage.make(for: ring, daily: daily, range: range, now: now, calendar: calendar)
    }

    private func dailyValues(of metric: HealthMetric, from start: Date, now: Date,
                             calendar: Calendar) async throws -> [Date: Double] {
        // Past days rarely change: within an hour, only re-read yesterday and today.
        if var cached = dailyCache[metric], cached.from <= start, now.timeIntervalSince(cached.fetched) < 3600,
           let recent = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) {
            let fresh = try await health.dailyValues(of: metric, from: recent, to: now, calendar: calendar)
            cached.values = cached.values.filter { $0.key < recent }.merging(fresh) { $1 }
            dailyCache[metric] = cached
            return cached.values
        }
        let values = try await health.dailyValues(of: metric, from: start, to: now, calendar: calendar)
        dailyCache[metric] = DailyCache(from: start, fetched: now, values: values)
        return values
    }

    // MARK: Closing rings

    /// A ring that just reached its goal: the home screen celebrates it with an animation and a haptic.
    struct Celebration: Equatable {
        let id = UUID()
        let ring: Ring
    }

    private(set) var celebration: Celebration?

    func dismissCelebration() { celebration = nil }

    /// Celebrates each fixed ring once per period when it closes, and a rolling ring when it gets back above its goal.
    private func celebrateClosedRings(_ snapshots: [Ring.ID: RingSnapshot]) {
        let defaults = UserDefaults.standard
        var celebrated = defaults.stringArray(forKey: "celebratedPeriods") ?? []
        var rollingClosed = defaults.dictionary(forKey: "rollingClosed") as? [String: Bool] ?? [:]
        var newlyClosed: [Ring] = []
        for ring in library.sets.flatMap(\.rings) {
            guard let snapshot = snapshots[ring.id] else { continue }
            // Only goals to reach are celebrated; a limit is met by not doing something.
            guard !ring.isLimit else { continue }
            let closed = ring.isMet(snapshot.value)
            if ring.period.isRolling {
                let key = ring.id.uuidString
                if closed, rollingClosed[key] == false { newlyClosed.append(ring) }
                rollingClosed[key] = closed
            } else if closed {
                let key = "\(ring.id.uuidString)|\(Int(snapshot.intervalStart.timeIntervalSince1970))"
                if !celebrated.contains(key) {
                    celebrated.append(key)
                    newlyClosed.append(ring)
                }
            }
        }
        defaults.set(Array(celebrated.suffix(300)), forKey: "celebratedPeriods")
        defaults.set(rollingClosed, forKey: "rollingClosed")
        if let ring = newlyClosed.first { celebration = Celebration(ring: ring) }
    }
}
