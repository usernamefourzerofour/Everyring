import DeviceActivity
import Foundation
import WidgetKit

/// Runs in the background when a Screen Time ring's apps reach another threshold today (5, 10, 15 … minutes) and
/// records it for the app and widgets. Apple doesn't let the app read screen time itself.
final class ScreenTimeMonitor: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let ring = ScreenTimeLog.ring(fromActivity: activity.rawValue),
              let minutes = ScreenTimeLog.minutes(fromEvent: event.rawValue) else { return }
        ScreenTimeLog.record(ring: ring, minutes: Double(minutes))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
