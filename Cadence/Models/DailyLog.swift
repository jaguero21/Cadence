import Foundation
import SwiftData

@Model
final class DailyLog {
    @Attribute(.unique) var date: Date
    var symptoms: [SymptomEntry]
    var mood: Int          // 1–5 (emoji scale)
    var energy: Int        // 0–10
    var painLevel: Int     // 0–10
    var brainFogLevel: Int // 0–10
    var sleepHours: Double
    var sleepQuality: Int  // 0–10
    var stressLevel: Int   // 0–10  (Anxiety in UI)
    var basicsCompleted: [String]
    var medications: [String]
    var foodNotes: String
    var freeNote: String
    var isComplete: Bool
    var didEditMood: Bool
    var didEditMetrics: Bool

    // HealthKit-pulled data
    var hkSteps: Int?
    var hkRestingHR: Double?
    var hkHRV: Double?
    var hkSleepHours: Double?
    var hkActiveEnergy: Double?
    var hkMindfulMinutes: Double?

    init(date: Date = .now) {
        self.date = Calendar.current.startOfDay(for: date)
        self.symptoms = []
        self.mood = 3
        self.energy = 5
        self.painLevel = 0
        self.brainFogLevel = 0
        self.sleepHours = 7.0
        self.sleepQuality = 5
        self.stressLevel = 5
        self.basicsCompleted = []
        self.medications = []
        self.foodNotes = ""
        self.freeNote = ""
        self.isComplete = false
        self.didEditMood = false
        self.didEditMetrics = false
    }

    var dateLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    var completionScore: Double {
        var filled = 0
        let total = 3
        if didEditMood            { filled += 1 }
        if didEditMetrics         { filled += 1 }
        if !freeNote.isEmpty      { filled += 1 }
        return Double(filled) / Double(total)
    }
}

struct SymptomEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var severity: Int  // 1–10
    var emoji: String
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
