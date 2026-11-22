import Foundation
import WatchConnectivity
import WidgetKit

/// Receives the ring library from the iPhone. The watch keeps no editing of its own: the iPhone's library wins.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Set by the app so a received library updates the visible rings at once.
    @MainActor weak var model: RingsModel?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context[WatchMessage.libraryKey] as? Data,
              let library = try? JSONDecoder().decode(RingLibrary.self, from: data) else { return }
        Task { @MainActor in
            if let model = self.model {
                model.library = library
            } else if RingStore.load() != library {
                try? RingStore.save(library)
                WidgetCenter.shared.invalidateConfigurationRecommendations()
                BackgroundUpdater.shared.start(library: library)
                await BackgroundUpdater.shared.update(force: true)
            }
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Pick up a library sent while the watch app wasn't running.
        if state == .activated { receive(session.receivedApplicationContext) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }
}
