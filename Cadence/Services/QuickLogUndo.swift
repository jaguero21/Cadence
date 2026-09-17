import Foundation
import SwiftData

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
}
