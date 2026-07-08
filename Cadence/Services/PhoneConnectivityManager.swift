import Foundation
import SwiftData
import WatchConnectivity
import OSLog

// Receives quick-log payloads from the Watch app and persists them into the
// day they were RECORDED (payload "date"), not the day they arrive — a
// transferUserInfo payload queued overnight must not clobber the new day's
// log. Payloads are plain [String: Any] dictionaries (keys: "mood", "energy",
// "date" as timeIntervalSinceReferenceDate) so no model types are shared with
// the watch target.
@MainActor
final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()
    private static let log = Logger(subsystem: "com.carpecadence", category: "PhoneConnectivity")
    private var container: ModelContainer?

    func start(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @MainActor
    private func applyQuickLog(_ payload: [String: Any]) {
        guard let container, let mood = payload["mood"] as? Int else { return }
        let context = container.mainContext

        // Attribute the entry to the day it was recorded on the wrist.
        let recordedAt = (payload["date"] as? TimeInterval).map(Date.init(timeIntervalSinceReferenceDate:)) ?? .now
        let day = Calendar.current.startOfDay(for: recordedAt)

        // Upsert that day's log so a wrist entry merges with an in-progress day.
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == day })
        let log: DailyLog
        if let existing = try? context.fetch(descriptor).first {
            log = existing
        } else {
            log = DailyLog(date: day)
            context.insert(log)
        }

        log.mood = mood.clamped(to: 1...5)
        log.didEditMood = true
        if let energy = payload["energy"] as? Int {
            log.energy = energy.clamped(to: 0...10)
            log.didEditMetrics = true
        }

        do {
            try context.save()
            // Publish a fresh widget summary — a bare timeline reload would
            // just republish the stale App Group data.
            let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
            DashboardViewModel.publishWidgetSummary(logs: logs)
        } catch {
            Self.log.error("Failed to save watch quick-log: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate (callbacks are nonisolated; hop to main)

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.applyQuickLog(message) }
    }

    // Reply-expected variant: the watch uses the reply as a delivery ack to
    // show "Sent" vs "Queued" truthfully.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.applyQuickLog(message)
            replyHandler(["ok": true])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.applyQuickLog(userInfo) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate to keep receiving from a (re)paired watch.
        WCSession.default.activate()
    }
}
