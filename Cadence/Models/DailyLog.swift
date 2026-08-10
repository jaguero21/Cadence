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

    // HealthKit-pulled data USED to live here. It now lives on HealthSnapshot,
    // in a separate local-only store, because this model is mirrored to
    // CloudKit and Guideline 5.1.3(ii) forbids storing personal health
    // information in iCloud. Join by date via DailyLogSnapshot.build(from:in:);
    // do not add an hk* field back to this model.

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
// Carries EVERY user-entered and HealthKit field (only media binaries and the
// isComplete flag are deliberately omitted) so reports can never silently
// drop a logged input. The didEdit* flags ride along because consumers need
// them (PatternEngine gates on didEditMetrics; Health write-back gates the
// State of Mind entry on didEditMood).
struct DailyLogSnapshot: Sendable {
    let date: Date
    let mood: Int
    let energy: Int
    let sleepHours: Double
    let sleepQuality: Int
    let painLevel: Int
    let brainFogLevel: Int
    let stressLevel: Int
    let symptoms: [SymptomEntry]
    let basicsCompleted: [String]
    let factors: [String]
    let customMetrics: [MetricEntry]
    let didEditMetrics: Bool
    let didEditMood: Bool
    let peaksAndValleysNote: String
    let hasPeaksAndValleysVoiceMemo: Bool
    let intentionsForTomorrow: String
    let freeNote: String
    let hkSteps: Int?
    let hkRestingHR: Double?
    let hkHRV: Double?
    let hkSleepHours: Double?
    let hkActiveEnergy: Double?
    let hkMindfulMinutes: Double?
    let hkWristTemp: Double?
    let hkRespiratoryRate: Double?
    let hkBloodOxygen: Double?
    let hkDaylightMinutes: Double?
    let hkDaytimeHR: Double?
    let hkWorkoutMinutes: Double?

    // `health` carries the day's objective HealthKit values, which live in a
    // separate local-only store (see HealthSnapshot) and therefore cannot be
    // reached through `log`. Defaulted to nil so the quick-log paths that only
    // need the user-entered half — watch, widget, Siri, Health write-back —
    // stay one-liners; every hk* field simply reads as "no data" there, which
    // is what all downstream consumers already handle.
    init(_ log: DailyLog, health: HealthSnapshot? = nil) {
        date           = log.date
        mood           = log.mood
        energy         = log.energy
        sleepHours     = log.sleepHours
        sleepQuality   = log.sleepQuality
        painLevel      = log.painLevel
        brainFogLevel  = log.brainFogLevel
        stressLevel    = log.stressLevel
        symptoms       = log.symptoms
        basicsCompleted = log.basicsCompleted
        factors        = log.factors
        customMetrics  = log.customMetrics
        didEditMetrics = log.didEditMetrics
        didEditMood    = log.didEditMood
        peaksAndValleysNote = log.peaksAndValleysNote
        // Voice memos live in the sectioned attachments pool now; the legacy
        // single-slot field still counts for logs saved before the migration.
        hasPeaksAndValleysVoiceMemo = log.peaksAndValleysVoiceMemo != nil
            || log.attachments.contains { $0.section == Attachment.peaksAndValleysSection && $0.kind == .audio }
        intentionsForTomorrow = log.intentionsForTomorrow
        freeNote       = log.freeNote
        hkSteps        = health?.hkSteps
        hkRestingHR    = health?.hkRestingHR
        hkHRV          = health?.hkHRV
        hkSleepHours   = health?.hkSleepHours
        hkActiveEnergy = health?.hkActiveEnergy
        hkMindfulMinutes = health?.hkMindfulMinutes
        hkWristTemp    = health?.hkWristTemp
        hkRespiratoryRate = health?.hkRespiratoryRate
        hkBloodOxygen  = health?.hkBloodOxygen
        hkDaylightMinutes = health?.hkDaylightMinutes
        hkDaytimeHR    = health?.hkDaytimeHR
        hkWorkoutMinutes = health?.hkWorkoutMinutes
    }

    init(
        date: Date,
        mood: Int = 3,
        energy: Int = 5,
        sleepHours: Double = 7.0,
        sleepQuality: Int = 5,
        painLevel: Int = 0,
        brainFogLevel: Int = 0,
        stressLevel: Int = 5,
        symptoms: [SymptomEntry] = [],
        basicsCompleted: [String] = [],
        factors: [String] = [],
        customMetrics: [MetricEntry] = [],
        didEditMetrics: Bool = false,
        didEditMood: Bool = false,
        peaksAndValleysNote: String = "",
        hasPeaksAndValleysVoiceMemo: Bool = false,
        intentionsForTomorrow: String = "",
        freeNote: String = "",
        hkSteps: Int? = nil,
        hkRestingHR: Double? = nil,
        hkHRV: Double? = nil,
        hkSleepHours: Double? = nil,
        hkActiveEnergy: Double? = nil,
        hkMindfulMinutes: Double? = nil,
        hkWristTemp: Double? = nil,
        hkRespiratoryRate: Double? = nil,
        hkBloodOxygen: Double? = nil,
        hkDaylightMinutes: Double? = nil,
        hkDaytimeHR: Double? = nil,
        hkWorkoutMinutes: Double? = nil
    ) {
        self.date = date
        self.mood = mood
        self.energy = energy
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.painLevel = painLevel
        self.brainFogLevel = brainFogLevel
        self.stressLevel = stressLevel
        self.symptoms = symptoms
        self.basicsCompleted = basicsCompleted
        self.factors = factors
        self.customMetrics = customMetrics
        self.didEditMetrics = didEditMetrics
        self.didEditMood = didEditMood
        self.peaksAndValleysNote = peaksAndValleysNote
        self.hasPeaksAndValleysVoiceMemo = hasPeaksAndValleysVoiceMemo
        self.intentionsForTomorrow = intentionsForTomorrow
        self.freeNote = freeNote
        self.hkSteps = hkSteps
        self.hkRestingHR = hkRestingHR
        self.hkHRV = hkHRV
        self.hkSleepHours = hkSleepHours
        self.hkActiveEnergy = hkActiveEnergy
        self.hkMindfulMinutes = hkMindfulMinutes
        self.hkWristTemp = hkWristTemp
        self.hkRespiratoryRate = hkRespiratoryRate
        self.hkBloodOxygen = hkBloodOxygen
        self.hkDaylightMinutes = hkDaylightMinutes
        self.hkDaytimeHR = hkDaytimeHR
        self.hkWorkoutMinutes = hkWorkoutMinutes
    }
}

extension DailyLogSnapshot {

    // THE join. DailyLog (CloudKit-mirrored) and HealthSnapshot (local-only)
    // live in different stores, so SwiftData cannot relate them — they are
    // matched on midnight-normalized `date` here, once, with a single fetch of
    // the health rows rather than a query per log.
    //
    // Every consumer that needs hk* values (PatternEngine, PDFBuilder,
    // CSVBuilder, the trend charts) takes DailyLogSnapshot and is unchanged by
    // the split; they just need their snapshots built through this instead of
    // `map(DailyLogSnapshot.init)`. A log with no health row for its day yields
    // nil hk* fields, which is exactly what a day without Health access already
    // produced before the split.
    static func build(from logs: [DailyLog], in context: ModelContext) -> [DailyLogSnapshot] {
        build(from: logs, health: HealthSnapshot.byDate(in: context))
    }

    // Preferred inside SwiftUI. Views must feed this from a `@Query` over
    // HealthSnapshot rather than calling the ModelContext overload: an
    // imperative `context.fetch` performed during a view update — or inside a
    // refresh that is itself driven by `.onChange(of:)` on a @Query — can
    // re-enter the update it was called from and spin the main thread. That
    // showed up as an app that stayed alive but stopped responding, and it hung
    // the UI smoke test rather than failing an assertion.
    static func build(from logs: [DailyLog], health: [HealthSnapshot]) -> [DailyLogSnapshot] {
        build(from: logs, health: Dictionary(
            health.map { (Calendar.current.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    private static func build(from logs: [DailyLog], health: [Date: HealthSnapshot]) -> [DailyLogSnapshot] {
        logs.map { log in
            DailyLogSnapshot(log, health: health[Calendar.current.startOfDay(for: log.date)])
        }
    }

    // Single-log convenience for the detail/edit paths.
    static func build(from log: DailyLog, in context: ModelContext) -> DailyLogSnapshot {
        DailyLogSnapshot(log, health: HealthSnapshot.row(for: log.date, in: context))
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
