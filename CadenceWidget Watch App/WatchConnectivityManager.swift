import Foundation
import WatchConnectivity

// Sends quick-log payloads from the watch to the iPhone. Uses sendMessage when
// the phone is reachable, falling back to transferUserInfo (queued, delivered
// when the phone is next available) so a wrist entry is never lost.
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendQuickLog(mood: Int, energy: Int) {
        let payload: [String: Any] = [
            "mood": mood,
            "energy": energy,
            "date": Date().timeIntervalSinceReferenceDate,
        ]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)   // reachable but send failed → queue it
            }
        } else {
            session.transferUserInfo(payload)        // queued for later delivery
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
