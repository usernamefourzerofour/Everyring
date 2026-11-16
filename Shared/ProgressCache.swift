import Foundation

/// A ring's last computed value and the period it was computed for.
struct RingSnapshot: Codable, Hashable, Sendable {
    var value: Double
    var intervalStart: Date
    var intervalEnd: Date
    var updated: Date
}

/// The latest value per ring, cached in the App Group by the app (and its background updates) so widgets and
/// complications can draw without reading HealthKit, which they often can't (e.g. while the device is locked).
struct ProgressCache: Codable, Hashable, Sendable {
    var rings: [Ring.ID: RingSnapshot] = [:]

    static var url: URL { AppGroup.containerURL.appending(path: "progress.json") }

    static func load(from url: URL = url) -> ProgressCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ProgressCache.self, from: data) else { return ProgressCache() }
        return cache
    }

    func save(to url: URL = Self.url) throws {
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Within the same fixed period the value can only go up, so a lower value read in the background is an
    /// incomplete read of Health and must not replace the cached one. With the app open (`allowDecrease`) it may drop,
    /// e.g. after deleted samples. Rolling periods drop naturally as old days leave the window.
    static func shouldReplace(_ old: RingSnapshot?, with new: RingSnapshot, rolling: Bool, allowDecrease: Bool) -> Bool {
        guard let old, !allowDecrease, !rolling, old.intervalStart == new.intervalStart else { return true }
        return new.value >= old.value
    }

    /// Merges new snapshots and drops rings that no longer exist in `library`.
    mutating func merge(_ snapshots: [Ring.ID: RingSnapshot], library: RingLibrary, allowDecrease: Bool) {
        let rings = library.sets.flatMap(\.rings)
        for ring in rings {
            guard let new = snapshots[ring.id] else { continue }
            // A daily average can drop when a new day starts, like a rolling window.
            if Self.shouldReplace(self.rings[ring.id], with: new, rolling: ring.period.isRolling || ring.isAverage,
                                  allowDecrease: allowDecrease) {
                self.rings[ring.id] = new
            }
        }
        let ids = Set(rings.map(\.id))
        self.rings = self.rings.filter { ids.contains($0.key) }
    }

    /// The value to show for `ring` at `date`. A fixed ring whose cached period has ended shows 0 (a new period has
    /// started); a rolling ring shows its last value.
    func value(for ring: Ring, at date: Date, calendar: Calendar) -> Double {
        guard let snapshot = rings[ring.id] else { return 0 }
        if ring.period.isRolling { return snapshot.value }
        return ring.period.interval(containing: date, calendar: calendar).start == snapshot.intervalStart
            ? snapshot.value : 0
    }

    /// When fixed rings start a new period after `date` (within `horizon`), so a widget timeline can reset them on time.
    static func boundaries(for rings: [Ring], after date: Date, calendar: Calendar,
                           horizon: TimeInterval = 24 * 3600) -> [Date] {
        let limit = date.addingTimeInterval(horizon)
        let ends = rings.filter { !$0.period.isRolling }
            .map { $0.period.interval(containing: date, calendar: calendar).end }
            .filter { $0 > date && $0 <= limit }
        return Array(Set(ends)).sorted()
    }
}
