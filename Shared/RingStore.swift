import Foundation

enum AppGroup {
    static let id = "group.dk.erik.everyring"

    /// The shared container, or the app's Application Support folder if the App Group isn't available (e.g. in tests).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        let url = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Everything the user configures: ring sets and settings. Shared with widgets and sent to the Watch.
struct RingLibrary: Codable, Hashable, Sendable {
    var sets: [RingSet]
    var weekStart: WeekStart = .system

    static let starter = RingLibrary(sets: [.starter])

    /// The calendar all periods are computed in.
    func calendar(_ base: Calendar = .current) -> Calendar { weekStart.calendar(base) }

    func set(id: RingSet.ID?) -> RingSet? {
        sets.first { $0.id == id } ?? sets.first
    }
}

extension RingSet {
    /// The suggested set in onboarding; the user can edit it.
    static var starter: RingSet {
        RingSet(name: String(localized: "My rings"), rings: [
            Ring(name: String(localized: "Active calories"), color: .sunrise, symbol: "flame",
                 metric: .activeEnergy, goal: 500, period: .today),
            Ring(name: String(localized: "Move minutes"), color: .magenta, symbol: "bolt.heart",
                 metric: .exerciseMinutes, goal: 150, period: .rollingDays(7)),
            Ring(name: String(localized: "Stand hours"), color: .lagoon, symbol: "figure.stand",
                 metric: .standHours, goal: 12, period: .today),
            Ring(name: String(localized: "Steps"), color: .fern, symbol: "figure.walk",
                 metric: .steps, goal: 10_000, period: .today),
            Ring(name: String(localized: "Workouts"), color: .indigo, symbol: "dumbbell",
                 metric: .workouts(.count, kind: nil), goal: 3, period: .thisWeek),
        ])
    }
}

/// Reads and writes the library as JSON in the App Group container.
enum RingStore {
    static var url: URL { AppGroup.containerURL.appending(path: "rings.json") }

    static func load(from url: URL = url) -> RingLibrary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RingLibrary.self, from: data)
    }

    static func save(_ library: RingLibrary, to url: URL = url) throws {
        let data = try JSONEncoder().encode(library)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
