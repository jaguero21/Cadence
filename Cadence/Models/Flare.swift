import Foundation
import SwiftData

// A flare is a multi-day episode of worsened symptoms — the real unit of a
// chronic condition, distinct from a single day's log.
@Model
final class Flare {
    var startDate: Date
    var endDate: Date?       // nil = still ongoing
    var peakSeverity: Int    // 1–10
    var note: String

    init(startDate: Date = .now, endDate: Date? = nil, peakSeverity: Int = 5, note: String = "") {
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.peakSeverity = peakSeverity
        self.note = note
    }

    var isActive: Bool { endDate == nil }

    // Inclusive day count; an ongoing flare counts through today.
    var durationDays: Int {
        let end = endDate ?? Calendar.current.startOfDay(for: .now)
        let days = Calendar.current.dateComponents([.day], from: startDate, to: end).day ?? 0
        return max(1, days + 1)
    }
}

// Sendable projection for PDF export (mirrors the other snapshot types).
struct FlareSnapshot: Sendable {
    let startDate: Date
    let endDate: Date?
    let peakSeverity: Int
    let note: String
    let durationDays: Int

    init(_ flare: Flare) {
        startDate = flare.startDate
        endDate = flare.endDate
        peakSeverity = flare.peakSeverity
        note = flare.note
        durationDays = flare.durationDays
    }
}
