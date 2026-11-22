import Foundation

/// Screen time per ring, as recorded by the Screen Time monitor extension. Apple doesn't let an app read screen time
/// directly: the monitor is told each time a ring's apps reach another threshold (5, 10, 15 … minutes today) and writes
/// it here, in the App Group, where the app and widgets read it. So values come in steps (5 minutes at first), and the
/// history starts when the ring was made.
///
/// Self-contained (no other Everyring types), because the monitor extension builds only this folder.
struct ScreenTimeLog: Codable, Hashable, Sendable {
    /// One reading: by `t`, the ring's apps had been used `minutes` that day.
    struct Reading: Codable, Hashable, Sendable {
        var t: Date
        var minutes: Double
    }

    /// Readings per ring, oldest first.
    var rings: [UUID: [Reading]] = [:]

    static let appGroup = "group.dk.erik.everyring"

    /// Thresholds the monitor is told about: every 5 minutes up to 4 hours, every 10 up to 8, every 30 up to 16.
    static let thresholds: [Int] = Array(stride(from: 5, through: 240, by: 5)) + Array(stride(from: 250, through: 480, by: 10))
        + Array(stride(from: 510, through: 960, by: 30))

    /// The monitor's event name for a threshold, and back.
    static func eventName(minutes: Int) -> String { "m\(minutes)" }
    static func minutes(fromEvent name: String) -> Int? { name.hasPrefix("m") ? Int(name.dropFirst()) : nil }

    /// The monitor's activity name for a ring, and back.
    static func activityName(ring: UUID) -> String { "ring.\(ring.uuidString)" }
    static func ring(fromActivity name: String) -> UUID? {
        name.hasPrefix("ring.") ? UUID(uuidString: String(name.dropFirst(5))) : nil
    }

    // MARK: Storage

    static var url: URL {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
        return container.appending(path: "screentime.json")
    }

    static func load(from url: URL = url) -> ScreenTimeLog {
        guard let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode(ScreenTimeLog.self, from: data) else { return ScreenTimeLog() }
        return log
    }

    func save(to url: URL = Self.url) throws {
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Records that `ring`'s apps reached `minutes` today by `date`, keeping about 120 days.
    mutating func record(ring: UUID, minutes: Double, at date: Date, calendar: Calendar = .current) {
        var readings = rings[ring] ?? []
        let day = calendar.startOfDay(for: date)
        // Thresholds can arrive late or out of order: never go down within a day.
        let todayMax = readings.filter { calendar.startOfDay(for: $0.t) == day }.map(\.minutes).max() ?? 0
        guard minutes > todayMax else { return }
        readings.append(Reading(t: date, minutes: minutes))
        let oldest = calendar.date(byAdding: .day, value: -120, to: day) ?? day
        rings[ring] = readings.filter { $0.t >= oldest }.sorted { $0.t < $1.t }
    }

    /// Records a reading in the shared log (used by the monitor extension).
    static func record(ring: UUID, minutes: Double, at date: Date = .now) {
        var log = load()
        log.record(ring: ring, minutes: minutes, at: date)
        try? log.save()
    }

    // MARK: Reading

    /// Minutes per day (keyed by start of day): the highest reading of each day.
    func daily(ring: UUID, calendar: Calendar) -> [Date: Double] {
        (rings[ring] ?? []).reduce(into: [:]) { result, reading in
            let day = calendar.startOfDay(for: reading.t)
            result[day] = max(result[day] ?? 0, reading.minutes)
        }
    }

    /// Minutes per hour inside `interval` (keyed by start of hour): how much each reading added in its day.
    func hourly(ring: UUID, in interval: DateInterval, calendar: Calendar) -> [Date: Double] {
        var result: [Date: Double] = [:]
        var lastDay: Date?
        var last = 0.0
        for reading in rings[ring] ?? [] {
            let day = calendar.startOfDay(for: reading.t)
            if day != lastDay { last = 0; lastDay = day }
            let added = reading.minutes - last
            last = reading.minutes
            guard interval.contains(reading.t), added > 0 else { continue }
            let hour = calendar.dateInterval(of: .hour, for: reading.t)?.start ?? reading.t
            result[hour, default: 0] += added
        }
        return result
    }
}
