import Foundation
import WatchConnectivity

// Sends quick-log payloads from the watch to the iPhone. Uses sendMessage with
// a reply ack when the phone is reachable, falling back to transferUserInfo
// (queued, delivered when the phone is next available) so a wrist entry is
// never lost. The payload carries the recording date so the phone attributes
// a queued entry to the day it was made, not the day it arrives.
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    enum DeliveryState {
        case sent     // phone acked the message
        case queued   // handed to the system for background transfer
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendQuickLog(mood: Int, energy: Int, completion: @escaping @Sendable (DeliveryState) -> Void) {
        let payload: [String: Any] = [
            "mood": mood,
            "energy": energy,
            "date": Date().timeIntervalSinceReferenceDate,
        ]
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in
                completion(.sent)
            }, errorHandler: { _ in
                session.transferUserInfo(payload)   // send failed → queue it
                completion(.queued)
            })
        } else {
            // Not reachable (or still activating): queue for background delivery.
            session.transferUserInfo(payload)
            completion(.queued)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
