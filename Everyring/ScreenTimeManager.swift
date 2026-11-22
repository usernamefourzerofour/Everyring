#if os(iOS)
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Screen Time rings: asks for Screen Time access and tells iOS which apps each ring follows, so the monitor extension
/// is called at each threshold (see `ScreenTimeLog`). Needs the Family Controls entitlement, which Apple must approve
/// for TestFlight and the App Store; without it, access is refused and the rings stay at zero.
@MainActor
final class ScreenTimeManager {
    static let shared = ScreenTimeManager()

    /// Whether Screen Time access is granted.
    var isAuthorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }

    /// Asks for Screen Time access for this person (Face ID or passcode). Throws if refused or not available.
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    /// Why the last attempt to follow a ring failed, if it did (shown on the ring's page when it has no minutes yet).
    private(set) var lastError: String? {
        get { UserDefaults.standard.string(forKey: "screenTime.lastError") }
        set { UserDefaults.standard.set(newValue, forKey: "screenTime.lastError") }
    }

    /// The rings iOS is following right now.
    func isMonitoring(_ ring: Ring) -> Bool {
        DeviceActivityCenter().activities.contains(DeviceActivityName(ScreenTimeLog.activityName(ring: ring.id)))
    }

    /// Follows the screen time of every Screen Time ring with chosen apps, and stops following removed ones.
    func update(for library: RingLibrary) {
        guard isAuthorized else { return }
        let center = DeviceActivityCenter()
        var failure: String?
        var wanted: Set<DeviceActivityName> = []
        for ring in library.sets.flatMap(\.rings) {
            guard ring.metric == .screenTime, let selection = Self.selection(of: ring),
                  !(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
                    && selection.webDomainTokens.isEmpty) else { continue }
            let name = DeviceActivityName(ScreenTimeLog.activityName(ring: ring.id))
            wanted.insert(name)
            let events = Dictionary(uniqueKeysWithValues: ScreenTimeLog.thresholds.map { minutes in
                (DeviceActivityEvent.Name(ScreenTimeLog.eventName(minutes: minutes)),
                 DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens,
                                     webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minutes),
                                     includesPastActivity: true))
            })
            // Every day from midnight to midnight; past use today counts, so a new ring starts with today's minutes.
            let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                                                  intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                                                  repeats: true)
            center.stopMonitoring([name])
            do {
                try center.startMonitoring(name, during: schedule, events: events)
            } catch {
                failure = String(describing: error)
            }
        }
        lastError = failure
        let stale = center.activities.filter { $0.rawValue.hasPrefix("ring.") && !wanted.contains($0) }
        if !stale.isEmpty { center.stopMonitoring(stale) }
    }

    /// The apps, categories and websites a ring follows.
    static func selection(of ring: Ring) -> FamilyActivitySelection? {
        ring.screenTimeSelection.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
    }

    static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }
}
#endif
