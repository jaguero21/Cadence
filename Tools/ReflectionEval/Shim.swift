import Foundation
// Minimal copies of the two value types WeekReflectionService.promptText reads.
// Field names/types mirror Cadence/Models; a mismatch fails compilation.
struct SymptomEntry: Sendable { var name: String; var severity: Int; var emoji: String = "" }
struct DailyLogSnapshot: Sendable {
    var date: Date
    var mood: Int = 3
    var energy: Int = 5
    var sleepHours: Double = 7.0
    var symptoms: [SymptomEntry] = []
    var factors: [String] = []
    var peaksAndValleysNote: String = ""
    var freeNote: String = ""
    var intentionsForTomorrow: String = ""
    var didEditMood: Bool = true
    var didEditMetrics: Bool = true
}
