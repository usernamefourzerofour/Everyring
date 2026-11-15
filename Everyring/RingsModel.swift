import Foundation
import Observation

/// The app's state: the ring library and the latest value per ring.
@MainActor
@Observable
final class RingsModel {
    var library: RingLibrary {
        didSet { try? RingStore.save(library) }
    }
    /// Latest value per ring, in the metric's base unit.
    private(set) var values: [Ring.ID: Double] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?

    private let health: HealthManager

    init(library: RingLibrary? = nil, health: HealthManager = .shared) {
        self.library = library ?? RingStore.load() ?? .starter
        self.health = health
    }

    var calendar: Calendar { library.calendar() }

    func value(for ring: Ring) -> Double { values[ring.id] ?? 0 }

    func displays(for set: RingSet) -> [RingDisplay] {
        set.rings.map { RingDisplay(id: $0.id, color: $0.color, fraction: $0.fraction(value(for: $0))) }
    }

    /// Asks for Health access for all metrics in use and reloads every ring.
    func refresh(now: Date = .now) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let rings = library.sets.flatMap(\.rings)
        do {
            try await health.requestAuthorization(for: rings.map(\.metric))
            let calendar = calendar
            var result: [Ring.ID: Double] = [:]
            for ring in rings {
                result[ring.id] = try await health.value(of: ring.metric, in: ring.period.interval(now: now, calendar: calendar))
            }
            values = result
            lastUpdated = now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
