import SwiftUI
import WatchKit

@main
struct EveryringWatchApp: App {
    @State private var model = RingsModel()

    init() {
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
                .task { WatchSync.shared.model = model }
        }
        .backgroundTask(.appRefresh(WatchRefresh.identifier)) {
            // Keep the complications fresh even when no new Health samples wake the app.
            await BackgroundUpdater.shared.update()
            await WatchRefresh.schedule()
        }
    }
}

enum WatchRefresh {
    static let identifier = "dk.erik.everyring.refresh"

    /// Asks watchOS to wake the app in about 30 minutes.
    @MainActor
    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: .now.addingTimeInterval(30 * 60), userInfo: identifier as NSString) { _ in }
    }
}
