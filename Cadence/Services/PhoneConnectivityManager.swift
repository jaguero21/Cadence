import Foundation
import SwiftData
import WatchConnectivity
import OSLog

// The Sendable form of a quick-log payload. WatchConnectivity delivers
// `[String: Any]`, which Swift 6 won't let cross from the nonisolated delegate
// callbacks to the main actor, so they parse into this first. Type extraction
// only: clamping to the model's scales stays in the upsert that writes the model.
struct QuickLogPayload: Sendable {
    let mood: Int
    let energy: Int?
    let date: Date

    // "mood" must be an Int or nothing is logged. A non-Int "energy" is dropped
    // rather than rejecting the whole entry. A missing "date" means now.
    init?(_ dict: [String: Any]) {
        guard let mood = dict["mood"] as? Int else { return nil }
        self.mood = mood
        self.energy = dict["energy"] as? Int
        self.date = (dict["date"] as? TimeInterval).map(Date.init(timeIntervalSinceReferenceDate:)) ?? .now
    }
}

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

    // Core upsert, static and context-injected so tests can exercise it against
    // an in-memory container (the seam the watch↔phone bridge hinges on).
    // Returns whether anything was persisted. The dictionary entry point is what
    // the widget queue, the Siri intent, and the tests call; it parses and
    // delegates, so QuickLogPayload is the only parser.
    @discardableResult
    static func applyQuickLog(_ payload: [String: Any], context: ModelContext,
                              source: QuickLogUndoRecord.Source = .siri) -> Bool {
        guard let parsed = QuickLogPayload(payload) else { return false }
        return applyQuickLog(parsed, context: context, source: source)
    }

    @discardableResult
    static func applyQuickLog(_ payload: QuickLogPayload, context: ModelContext,
                              source: QuickLogUndoRecord.Source = .siri) -> Bool {
        // Attribute the entry to the day it was recorded on the wrist.
        let day = Calendar.current.startOfDay(for: payload.date)

        // Upsert that day's log so a wrist entry merges with an in-progress day.
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == day })
        let log: DailyLog
        let createdLog: Bool
        if let existing = try? context.fetch(descriptor).first {
            log = existing
            createdLog = false
        } else {
            log = DailyLog(date: day)
            context.insert(log)
            createdLog = true
        }

        // Captured before the write: what the day looked like, so the app can
        // offer Undo after a misheard Siri check-in (see QuickLogUndo).
        let previousMood = log.mood
        let previousDidEditMood = log.didEditMood
        let previousEnergy = log.energy
        let previousDidEditMetrics = log.didEditMetrics

        log.mood = payload.mood.clamped(to: 1...5)
        log.didEditMood = true
        if let energy = payload.energy {
            log.energy = energy.clamped(to: 0...10)
            log.didEditMetrics = true
        }

        do {
            try context.save()
            // Only after a successful save: an undo offer for a write that
            // never landed would delete something the person did enter.
            QuickLogUndo.store(QuickLogUndoRecord(
                day: day, source: source, createdLog: createdLog,
                previousMood: previousMood, previousDidEditMood: previousDidEditMood,
                previousEnergy: previousEnergy, previousDidEditMetrics: previousDidEditMetrics,
                appliedMood: log.mood, appliedEnergy: payload.energy.map { $0.clamped(to: 0...10) },
                recordedAt: .now
            ))
            return true
        } catch {
            Self.log.error("Failed to save watch quick-log: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private func applyQuickLog(_ payload: QuickLogPayload) {
        guard let container else { return }
        let context = container.mainContext
        if Self.applyQuickLog(payload, context: context, source: .watch) {
            // Publish a fresh widget summary — a bare timeline reload would
            // just republish the stale App Group data.
            let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
            DashboardViewModel.publishWidgetSummary(logs: logs, activeFlare: DashboardViewModel.activeFlare(in: context))
            // Mirror the mood into Health's State of Mind — a wrist check-in
            // is still a check-in. Best-effort, fire-and-forget.
            let day = Calendar.current.startOfDay(for: payload.date)
            if let log = logs.first(where: { $0.date == day }) {
                let snapshot = DailyLogSnapshot(log)
                Task { await HealthKitService.shared.publish(log: snapshot) }
            }
        }
    }

    // MARK: - WCSessionDelegate (callbacks arrive on a background thread; parse
    // into the Sendable QuickLogPayload here, then hop to main)

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let payload = QuickLogPayload(message) else { return }
        Task { @MainActor in self.applyQuickLog(payload) }
    }

    // Reply-expected variant: the watch uses the reply as a delivery ack to
    // show "Sent" vs "Queued" truthfully, so the reply goes out only after the
    // save has been attempted. It acks even an unparseable message, as it
    // always has — the ack means "received", not "saved".
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let payload = QuickLogPayload(message)
        // The one unsafe escape in this file. The SDK doesn't mark the reply
        // block Sendable, and Apple's docs say only that the delegate method
        // runs on a background thread and must call it, not which thread may.
        // This keeps the pre-Swift-6 behaviour exactly: reply from the main
        // actor after the apply. The block is called once, and never touched
        // on this side again.
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            if let payload { self.applyQuickLog(payload) }
            reply(["ok": true])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payload = QuickLogPayload(userInfo) else { return }
        Task { @MainActor in self.applyQuickLog(payload) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate to keep receiving from a (re)paired watch.
        WCSession.default.activate()
    }
}
