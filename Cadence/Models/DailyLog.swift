import Foundation
import SwiftData

@Model
final class DailyLog {
    // Inline defaults on every non-optional attribute are required for CloudKit
    // mirroring. Per-day uniqueness is enforced in code (callers fetch today's
    // log before creating one), not via @Attribute(.unique) — CloudKit forbids it.
    var date: Date = Calendar.current.startOfDay(for: .now)
    var symptoms: [SymptomEntry] = []
    var mood: Int = 3          // 1–5 (emoji scale)
    var energy: Int = 5        // 0–10
    var painLevel: Int = 0     // 0–10
    var brainFogLevel: Int = 0 // 0–10
    var sleepHours: Double = 7.0
    var sleepQuality: Int = 5  // 0–10
    var stressLevel: Int = 5   // 0–10  (Anxiety in UI)
    var basicsCompleted: [String] = []
    var factors: [String] = []   // contextual triggers logged that day (e.g. "Alcohol")
    var customMetrics: [MetricEntry] = []   // values for user-defined CustomTrackers
    var attachments: [Attachment] = []      // photo/voice references; binaries live on disk
    var peaksAndValleysNote: String = ""    // "What were the peaks and valleys of your day?"
    var peaksAndValleysVoiceMemo: Attachment?   // optional single voice memo; binary lives on disk (see AttachmentStore)
    var intentionsForTomorrow: String = ""  // "Write your intentions for tomorrow."
    var freeNote: String = ""
    var isComplete: Bool = false
    var didEditMood: Bool = false
    var didEditMetrics: Bool = false

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
        self.peaksAndValleysNote = ""
        self.intentionsForTomorrow = ""
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

// Sendable projection of DailyLog so PatternEngine and PDF export can run off
// any isolation context without touching the @Model (which isn't Sendable and
// would race on its SwiftData-backed fields).
struct DailyLogSnapshot: Sendable {
    let date: Date
    let mood: Int
    let energy: Int
    let sleepHours: Double
    let stressLevel: Int
    let symptoms: [SymptomEntry]
    let factors: [String]
    let customMetrics: [MetricEntry]
    let didEditMetrics: Bool
    let peaksAndValleysNote: String
    let hasPeaksAndValleysVoiceMemo: Bool
    let intentionsForTomorrow: String

    init(_ log: DailyLog) {
        date           = log.date
        mood           = log.mood
        energy         = log.energy
        sleepHours     = log.sleepHours
        stressLevel    = log.stressLevel
        symptoms       = log.symptoms
        factors        = log.factors
        customMetrics  = log.customMetrics
        didEditMetrics = log.didEditMetrics
        peaksAndValleysNote = log.peaksAndValleysNote
        hasPeaksAndValleysVoiceMemo = log.peaksAndValleysVoiceMemo != nil
        intentionsForTomorrow = log.intentionsForTomorrow
    }

    init(
        date: Date,
        mood: Int = 3,
        energy: Int = 5,
        sleepHours: Double = 7.0,
        stressLevel: Int = 5,
        symptoms: [SymptomEntry] = [],
        factors: [String] = [],
        customMetrics: [MetricEntry] = [],
        didEditMetrics: Bool = false,
        peaksAndValleysNote: String = "",
        hasPeaksAndValleysVoiceMemo: Bool = false,
        intentionsForTomorrow: String = ""
    ) {
        self.date = date
        self.mood = mood
        self.energy = energy
        self.sleepHours = sleepHours
        self.stressLevel = stressLevel
        self.symptoms = symptoms
        self.factors = factors
        self.customMetrics = customMetrics
        self.didEditMetrics = didEditMetrics
        self.peaksAndValleysNote = peaksAndValleysNote
        self.hasPeaksAndValleysVoiceMemo = hasPeaksAndValleysVoiceMemo
        self.intentionsForTomorrow = intentionsForTomorrow
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
