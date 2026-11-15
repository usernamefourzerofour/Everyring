import Foundation
import WatchConnectivity

/// Sends the ring library to the Apple Watch. The application context always holds the latest library, so the watch
/// gets it the next time it can, even if it was unreachable when the rings changed.
final class PhoneSync: NSObject, WCSessionDelegate {
    static let shared = PhoneSync()

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let lock = NSLock()
    private var pending: RingLibrary?

    func activate() {
        guard let session, session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ library: RingLibrary) {
        lock.withLock { pending = library }
        activate()
        flush()
    }

    private func flush() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let library = lock.withLock({ pending }),
              let data = try? JSONEncoder().encode(library) else { return }
        do {
            try session.updateApplicationContext([WatchMessage.libraryKey: data])
            lock.withLock { if pending == library { pending = nil } }
        } catch {
            // Kept in `pending`; sent again on the next activation or change.
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if lock.withLock({ pending }) == nil, let library = RingStore.load() {
            lock.withLock { pending = library }
        }
        flush()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // The watch app was just installed or the watch was paired: give it the library.
        if let library = RingStore.load() { send(library) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switching watches: activate again for the new one.
        session.activate()
    }
}
