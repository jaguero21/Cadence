import Foundation
import SwiftData

// A persisted record of a pattern insight that has been surfaced, so the user
// can review a history of detected patterns and so we only notify once per new
// pattern. Deduped by `key` (the insight title, which is stable per pattern).
@Model
final class InsightRecord {
    // Dedupe by key happens in code (InsightRecorder.record); CloudKit forbids
    // @Attribute(.unique).
    var key: String = ""
    var title: String = ""
    var detail: String = ""
    var category: String = ""
    var confidence: Double = 0
    var firstSeen: Date = Date.now
    var lastSeen: Date = Date.now

    init(key: String, title: String, detail: String, category: String, confidence: Double, firstSeen: Date = .now, lastSeen: Date = .now) {
        self.key = key
        self.title = title
        self.detail = detail
        self.category = category
        self.confidence = confidence
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}
