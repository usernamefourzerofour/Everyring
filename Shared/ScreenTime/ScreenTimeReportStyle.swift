import SwiftUI

/// What the Screen Time report extension needs to draw a ring's history in the ring's own look: its colours and daily
/// goal. The app writes it to the App Group just before it shows the report (the report itself can't be handed
/// anything else, and it can only read, never send data back).
///
/// Self-contained (no other Everyring types), because the report extension builds only this folder.
struct ScreenTimeReportStyle: Codable, Hashable, Sendable {
    var deep: Color.Resolved
    var light: Color.Resolved
    /// The ring's goal or limit in minutes a day, if it has one per day.
    var dailyMinutes: Double?
    /// "Stay under" rings: days over the line are drawn in the warning colour.
    var isLimit: Bool
    /// The month the History calendar shows (its first day).
    var calendarMonth: Date?
    /// Whether the ring has a past-the-limit mark (a cross in History); off, over-limit days look like the others.
    var marksOverLimit: Bool = true

    private static let key = "screenTime.reportStyle"

    static func load() -> ScreenTimeReportStyle? {
        guard let data = UserDefaults(suiteName: ScreenTimeLog.appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: ScreenTimeLog.appGroup)?.set(data, forKey: Self.key)
    }
}
