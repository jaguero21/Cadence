import Foundation
import SwiftData
import OSLog

// What today's log looked like before a quick check-in wrote to it.
//
// Siri can mishear a mood, and the check-in lands without the app ever coming to
// the foreground — so the record has to outlive that process. It goes in
// UserDefaults (local only, never mirrored to iCloud) rather than the store: it
// is transient UI state about one write, not part of the user's history.
struct QuickLogUndoRecord: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case siri, watch, widget }

    let day: Date                      // start of the day the entry landed on
    let source: Source
    let createdLog: Bool               // the quick log inserted the DailyLog itself
    let previousMood: Int
    let previousDidEditMood: Bool
    let previousEnergy: Int
    let previousDidEditMetrics: Bool
    let appliedMood: Int               // what it wrote, for the staleness check
    let appliedEnergy: Int?
    let recordedAt: Date
}

enum QuickLogUndo {

    // MARK: - Storage

    static func store(_ record: QuickLogUndoRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKey.lastQuickLogUndo)
    }

    // A record that won't decode (an older shape, say) is dropped rather than
    // surfaced: a stale undo offer is worse than none, and this must never be
    // able to block a check-in.
    static func stored() -> QuickLogUndoRecord? {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.lastQuickLogUndo) else { return nil }
        guard let record = try? JSONDecoder().decode(QuickLogUndoRecord.self, from: data) else {
            clear()
            return nil
        }
        return record
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.lastQuickLogUndo)
    }

    // MARK: - Offering

    // The record only counts while the quick log is still the last word on
    // today: if the person has since edited the day, undoing would throw away
    // work they did by hand, and if they deleted the log there is nothing left
    // to undo.
    static func availableRecord(in context: ModelContext) -> QuickLogUndoRecord? {
        guard let record = stored() else { return nil }
        guard record.day == Calendar.current.startOfDay(for: .now) else { return nil }

        let day = record.day
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == day })
        guard let log = (try? context.fetch(descriptor))?.first else { return nil }
        guard log.mood == record.appliedMood, log.didEditMood else { return nil }
        if let appliedEnergy = record.appliedEnergy, log.energy != appliedEnergy { return nil }
        return record
    }

    // MARK: - Applying

    // Deleting is the honest inverse when the check-in created the day: the day
    // had no entry before, and leaving an empty one would show it as started.
    // Callers re-publish to Health afterwards — publish(log:) deletes and
    // rewrites the day's samples, so a removed log leaves nothing behind.
    static func undo(record: QuickLogUndoRecord, in context: ModelContext) {
        let day = record.day
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == day })
        guard let log = (try? context.fetch(descriptor))?.first else {
            clear()
            return
        }

        if record.createdLog {
            context.delete(log)
        } else {
            log.mood = record.previousMood
            log.didEditMood = record.previousDidEditMood
            log.energy = record.previousEnergy
            log.didEditMetrics = record.previousDidEditMetrics
        }

        do {
            try context.save()
            clear()
        } catch {
            // Leave the record in place: the day is unchanged, so the offer is
            // still true and the person can try again.
            Self.log.error("Undoing a quick check-in failed: \(error.localizedDescription)")
        }
    }

    private static let log = Logger(subsystem: "com.carpecadence", category: "QuickLogUndo")
}
