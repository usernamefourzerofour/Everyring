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
        set.rings.map { $0.display(value(for: $0), fadesWhenClosed: library.fadesClosedRings) }
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
        // With the app open the value may go down (e.g. deleted samples).
        ProgressUpdater.store(snapshots, library: library, allowDecrease: true)
    }

    private static let demoFractions = [0.72, 1.24, 0.46, 1.0, 0.31]

    private func demoSnapshots(now: Date) -> [Ring.ID: RingSnapshot] {
        var result: [Ring.ID: RingSnapshot] = [:]
        for set in library.sets {
            for (index, ring) in set.rings.enumerated() {
                let interval = ring.period.interval(now: now, calendar: calendar)
                let made = ring.goal * Self.demoFractions[index % 5]
                result[ring.id] = RingSnapshot(value: ring.isDaysReaching ? made.rounded(.down) : made,
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
    private var dailyCache: [DailyKey: DailyCache] = [:]

    private struct DailyKey: Hashable {
        var metric: HealthMetric
        var filter: HealthFilter
    }

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
            // (Rings that count days one by one keep the made-up days.)
            if !ring.needsDailyValues {
                for day in days { daily[day] = ring.isAverage ? value(for: ring) : value(for: ring) / Double(max(1, days.count)) }
            }
        } else {
            do {
                daily = try await dailyValues(for: ring, from: start, now: now, calendar: calendar)
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

    /// Asks for access to the ring's Health data if it was never asked for (shows the sheet once).
    func requestAccess(for ring: Ring) async {
        guard !Self.isDemo else { return }
        try? await health.requestAuthorization(for: [ring.metric])
    }

    /// How the ring's value built up through its current period, for the chart on the detail screen. `nil` if Health
    /// couldn't be read, or for sleep and mindful minutes in a one-day period (no meaningful hourly build-up).
    /// - Parameter chosen: a period picked in the history; `nil` for the one in progress.
    func periodProgress(for ring: Ring, interval chosen: DateInterval? = nil, now: Date = .now) async -> PeriodProgress? {
        let calendar = calendar
        let interval = chosen ?? PeriodProgress.chartInterval(for: ring, now: now, calendar: calendar)
        let isPast = interval.end <= now
        let end = min(now, interval.end)
        let buckets: [Date: Double]
        if PeriodProgress.bucket(for: ring.period) == .hour {
            guard ring.metric.hasHourlyBuildUp else { return nil }
            if Self.isDemo {
                let total = isPast
                    ? DemoHistory.daily(for: ring, from: interval.start, to: interval.start, calendar: calendar).values.reduce(0, +)
                    : value(for: ring)
                buckets = DemoHistory.hourly(total: total, from: interval.start, to: end, calendar: calendar)
            } else {
                guard let hourly = try? await health.hourlyValues(
                    of: ring.metric, in: DateInterval(start: interval.start, end: max(interval.start, end)),
                    calendar: calendar, filter: ring.healthFilter) else { return nil }
                buckets = hourly
            }
        } else if Self.isDemo && (isPast || ring.needsDailyValues) {
            buckets = DemoHistory.daily(for: ring, from: interval.start, to: end, calendar: calendar)
        } else if Self.isDemo {
            // Spread the home screen's demo value over the days so far, so the chart ends where the ring is.
            let days = DemoHistory.daily(for: ring, from: interval.start, to: end, calendar: calendar).keys.sorted()
            let share = ring.isAverage ? value(for: ring) : value(for: ring) / Double(max(1, days.count))
            buckets = Dictionary(uniqueKeysWithValues: days.map { ($0, share) })
        } else {
            // Daily values from the cache cover past periods too (it reaches back as far as the history needs).
            guard let daily = try? await dailyValues(for: ring, from: interval.start, now: now, calendar: calendar)
            else { return nil }
            buckets = daily
        }
        return PeriodProgress.make(for: ring, buckets: buckets, interval: interval, now: now, calendar: calendar)
    }

    /// The workouts in `interval` with what the ring's metric logged during each, for activity rings (steps, energy,
    /// exercise minutes, distance); `nil` for other rings or if Health couldn't be read.
    func workoutLog(for ring: Ring, interval: DateInterval, now: Date = .now) async -> [LoggedWorkout]? {
        guard ring.metric.supportsWorkoutLeaveOut else { return nil }
        if Self.isDemo { return DemoHistory.workouts(for: ring, in: interval, now: now, calendar: calendar) }
        return try? await health.workoutLog(of: ring.metric, in: interval, filter: ring.healthFilter)
    }

    /// How much of an activity ring's metric in `interval` came from workouts and how much from everyday life; `nil`
    /// for other rings or if Health couldn't be read.
    func activitySplit(for ring: Ring, interval: DateInterval, now: Date = .now) async -> ActivitySplit? {
        guard ring.metric.supportsWorkoutLeaveOut else { return nil }
        if Self.isDemo {
            let during = DemoHistory.workouts(for: ring, in: interval, now: now, calendar: calendar).reduce(0) { $0 + $1.value }
            return ActivitySplit(total: during * 2.4, duringWorkouts: during)
        }
        return try? await health.activitySplit(of: ring.metric, in: interval, filter: ring.healthFilter)
    }

    /// Heart rate and the ring's metric minute by minute through `workout`; `nil` if Health couldn't be read.
    func workoutTimeline(for ring: Ring, workout: LoggedWorkout) async -> WorkoutTimeline? {
        if Self.isDemo { return DemoHistory.timeline(for: workout) }
        return try? await health.workoutTimeline(of: ring.metric, in: DateInterval(start: workout.start, end: workout.end),
                                                 filter: ring.healthFilter)
    }

    /// The nights in `interval`, for sleep rings; `nil` for other rings or if Health couldn't be read.
    func nightLog(for ring: Ring, interval: DateInterval, now: Date = .now) async -> [LoggedNight]? {
        guard ring.metric.isSleep else { return nil }
        if Self.isDemo { return DemoHistory.nights(in: interval, now: now, calendar: calendar) }
        return try? await health.nights(in: interval, calendar: calendar, filter: ring.healthFilter)
    }

    /// The apps and devices that wrote data for `metric`, for picking a ring's sources.
    func sources(for metric: HealthMetric) async -> [HealthSource] {
        if Self.isDemo {
            return [HealthSource(id: "com.apple.health.demo-watch", name: "Apple Watch"),
                    HealthSource(id: "com.apple.health.demo-phone", name: "iPhone")]
        }
        return await health.sources(for: metric)
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
                daily = try await dailyValues(for: ring, from: start, now: now, calendar: calendar)
            } catch {
                return nil
            }
        }
        return HistoryPage.make(for: ring, daily: daily, range: range, now: now, calendar: calendar)
    }

    private func dailyValues(for ring: Ring, from start: Date, now: Date,
                             calendar: Calendar) async throws -> [Date: Double] {
        let key = DailyKey(metric: ring.metric, filter: ring.healthFilter)
        // Past days rarely change: within an hour, only re-read yesterday and today.
        if var cached = dailyCache[key], cached.from <= start, now.timeIntervalSince(cached.fetched) < 3600,
           let recent = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) {
            let fresh = try await health.dailyValues(of: key.metric, from: recent, to: now, calendar: calendar,
                                                     filter: key.filter)
            cached.values = cached.values.filter { $0.key < recent }.merging(fresh) { $1 }
            dailyCache[key] = cached
            return cached.values
        }
        let values = try await health.dailyValues(of: key.metric, from: start, to: now, calendar: calendar,
                                                  filter: key.filter)
        dailyCache[key] = DailyCache(from: start, fetched: now, values: values)
        return values
    }
}
