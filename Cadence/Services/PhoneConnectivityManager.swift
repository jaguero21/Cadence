import Foundation
import SwiftData
import WatchConnectivity
import WidgetKit
import OSLog

// Receives quick-log payloads from the Watch app and persists them as today's
// DailyLog. Payloads are plain [String: Any] dictionaries (keys: "mood",
// "energy", "date") so no model types need to be shared with the watch target.
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
        let today = Calendar.current.startOfDay(for: .now)

        // Upsert today's log so a wrist entry merges with an in-progress day.
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == today })
        let log: DailyLog
        if let existing = try? context.fetch(descriptor).first {
            log = existing
        } else {
            log = DailyLog()
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
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.log.error("Failed to save watch quick-log: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate (callbacks are nonisolated; hop to main)

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.applyQuickLog(message) }
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
