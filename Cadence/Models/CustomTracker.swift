import Foundation
import SwiftData

// A user-defined numeric tracker (e.g. "Joint pain", "Hydration", 0–10) logged
// alongside the built-in body metrics. Per-day values are stored on DailyLog as
// MetricEntry rows keyed by this tracker's stable id, so renaming a tracker
// doesn't orphan its history.
@Model
final class CustomTracker {
    @Attribute(.unique) var id: UUID
    var name: String
    var minValue: Int
    var maxValue: Int
    var unit: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, minValue: Int = 0, maxValue: Int = 10, unit: String = "", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.minValue = minValue
        self.maxValue = maxValue
        self.unit = unit
        self.sortOrder = sortOrder
    }

    // Guard against an inverted/degenerate range from bad input.
    var range: ClosedRange<Int> { minValue...Swift.max(minValue + 1, maxValue) }
    var midpoint: Int { (range.lowerBound + range.upperBound) / 2 }
}

// A logged value for a custom tracker on a given day. Codable so it persists in
// DailyLog.customMetrics; Sendable so it rides DailyLogSnapshot across actors.
struct MetricEntry: Codable, Sendable, Identifiable {
    var trackerID: UUID
    var value: Int
    var id: UUID { trackerID }
}

// Sendable projection for PDF export.
struct CustomTrackerSnapshot: Sendable {
    let id: UUID
    let name: String
    let unit: String

    init(_ tracker: CustomTracker) {
        id = tracker.id
        name = tracker.name
        unit = tracker.unit
    }
}
