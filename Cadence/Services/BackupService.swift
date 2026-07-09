import Foundation
import SwiftData
import OSLog

// Full-data JSON backup and restore. The document is a plain Codable mirror of
// the user-entered models (insight history is derivable, so it's recomputed
// rather than backed up; photo/voice binaries live outside SwiftData and are
// not included). Restore MERGES: it inserts records the store doesn't have and
// never overwrites existing ones — safe to run on a device that already has
// data (same save-time dedup philosophy CloudKit mirroring forces everywhere
// else in the app).
enum BackupService {

    static let currentVersion = 1
    private static let log = Logger(subsystem: "com.carpecadence", category: "Backup")

    // MARK: - Document

    struct Document: Codable {
        var version: Int = BackupService.currentVersion
        var exportDate: Date = .now
        var dailyLogs: [DailyLogBackup] = []
        var weeklyReviews: [WeeklyReviewBackup] = []
        var symptomTags: [SymptomTagBackup] = []
        var medications: [MedicationBackup] = []
        var flares: [FlareBackup] = []
        var customTrackers: [CustomTrackerBackup] = []
    }

    struct DailyLogBackup: Codable {
        var date: Date
        var symptoms: [SymptomEntry] = []
        var mood: Int = 3
        var energy: Int = 5
        var painLevel: Int = 0
        var brainFogLevel: Int = 0
        var sleepHours: Double = 7.0
        var sleepQuality: Int = 5
        var stressLevel: Int = 5
        var basicsCompleted: [String] = []
        var factors: [String] = []
        var customMetrics: [MetricEntry] = []
        var freeNote: String = ""
        var isComplete: Bool = false
        var didEditMood: Bool = false
        var didEditMetrics: Bool = false
        var hkSteps: Int?
        var hkRestingHR: Double?
        var hkHRV: Double?
        var hkSleepHours: Double?
        var hkActiveEnergy: Double?
        var hkMindfulMinutes: Double?
    }

    struct WeeklyReviewBackup: Codable {
        var weekStartDate: Date
        var promptResponses: [PromptResponse] = []
        var overallRating: Int = 0
        var avgMood: Double = 0
        var avgEnergy: Double = 0
        var avgSleep: Double = 0
        var topSymptoms: [String] = []
        var isComplete: Bool = false
    }

    struct SymptomTagBackup: Codable {
        var name: String
        var emoji: String = ""
        var isDefault: Bool = false
        var sortOrder: Int = 0
    }

    struct MedicationBackup: Codable {
        var name: String
        var dosage: String = ""
        var startDate: Date
        var endDate: Date?
        var notes: String = ""
    }

    struct FlareBackup: Codable {
        var startDate: Date
        var endDate: Date?
        var peakSeverity: Int = 5
        var note: String = ""
    }

    struct CustomTrackerBackup: Codable {
        // The id must round-trip: DailyLog.customMetrics values are keyed by it.
        var id: UUID
        var name: String
        var minValue: Int = 0
        var maxValue: Int = 10
        var unit: String = ""
        var sortOrder: Int = 0
    }

    // MARK: - Build

    static func document(
        logs: [DailyLog],
        reviews: [WeeklyReview],
        tags: [SymptomTag],
        medications: [Medication],
        flares: [Flare],
        trackers: [CustomTracker]
    ) -> Document {
        Document(
            dailyLogs: logs.map { log in
                DailyLogBackup(
                    date: log.date, symptoms: log.symptoms, mood: log.mood, energy: log.energy,
                    painLevel: log.painLevel, brainFogLevel: log.brainFogLevel,
                    sleepHours: log.sleepHours, sleepQuality: log.sleepQuality,
                    stressLevel: log.stressLevel, basicsCompleted: log.basicsCompleted,
                    factors: log.factors, customMetrics: log.customMetrics,
                    freeNote: log.freeNote, isComplete: log.isComplete,
                    didEditMood: log.didEditMood, didEditMetrics: log.didEditMetrics,
                    hkSteps: log.hkSteps, hkRestingHR: log.hkRestingHR, hkHRV: log.hkHRV,
                    hkSleepHours: log.hkSleepHours, hkActiveEnergy: log.hkActiveEnergy,
                    hkMindfulMinutes: log.hkMindfulMinutes
                )
            },
            weeklyReviews: reviews.map { review in
                WeeklyReviewBackup(
                    weekStartDate: review.weekStartDate, promptResponses: review.promptResponses,
                    overallRating: review.overallRating, avgMood: review.avgMood,
                    avgEnergy: review.avgEnergy, avgSleep: review.avgSleep,
                    topSymptoms: review.topSymptoms, isComplete: review.isComplete
                )
            },
            symptomTags: tags.map {
                SymptomTagBackup(name: $0.name, emoji: $0.emoji, isDefault: $0.isDefault, sortOrder: $0.sortOrder)
            },
            medications: medications.map {
                MedicationBackup(name: $0.name, dosage: $0.dosage, startDate: $0.startDate,
                                 endDate: $0.endDate, notes: $0.notes)
            },
            flares: flares.map {
                FlareBackup(startDate: $0.startDate, endDate: $0.endDate,
                            peakSeverity: $0.peakSeverity, note: $0.note)
            },
            customTrackers: trackers.map {
                CustomTrackerBackup(id: $0.id, name: $0.name, minValue: $0.minValue,
                                    maxValue: $0.maxValue, unit: $0.unit, sortOrder: $0.sortOrder)
            }
        )
    }

    // MARK: - Encode / decode

    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Document.self, from: data)
        guard document.version <= currentVersion else {
            throw BackupError.unsupportedVersion(document.version)
        }
        return document
    }

    enum BackupError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return String(localized: "This backup was made by a newer version of Cadence (format \(v)). Update the app and try again.")
            }
        }
    }

    // MARK: - Restore (merge)

    struct RestoreSummary: Equatable {
        var insertedLogs = 0
        var insertedReviews = 0
        var insertedTags = 0
        var insertedMedications = 0
        var insertedFlares = 0
        var insertedTrackers = 0
        var skipped = 0

        var insertedTotal: Int {
            insertedLogs + insertedReviews + insertedTags + insertedMedications + insertedFlares + insertedTrackers
        }
    }

    // Inserts anything the store doesn't already have; existing records win.
    // Identity: logs by day, reviews by week start, tags by name, medications by
    // (name, start date), flares by start date, trackers by id.
    @MainActor
    static func restore(_ document: Document, context: ModelContext) throws -> RestoreSummary {
        let cal = Calendar.current
        var summary = RestoreSummary()

        var existingDays = Set(try context.fetch(FetchDescriptor<DailyLog>()).map { cal.startOfDay(for: $0.date) })
        for backup in document.dailyLogs {
            let day = cal.startOfDay(for: backup.date)
            guard !existingDays.contains(day) else { summary.skipped += 1; continue }
            existingDays.insert(day)
            let log = DailyLog(date: day)
            log.symptoms = backup.symptoms
            log.mood = backup.mood
            log.energy = backup.energy
            log.painLevel = backup.painLevel
            log.brainFogLevel = backup.brainFogLevel
            log.sleepHours = backup.sleepHours
            log.sleepQuality = backup.sleepQuality
            log.stressLevel = backup.stressLevel
            log.basicsCompleted = backup.basicsCompleted
            log.factors = backup.factors
            log.customMetrics = backup.customMetrics
            log.freeNote = backup.freeNote
            log.isComplete = backup.isComplete
            log.didEditMood = backup.didEditMood
            log.didEditMetrics = backup.didEditMetrics
            log.hkSteps = backup.hkSteps
            log.hkRestingHR = backup.hkRestingHR
            log.hkHRV = backup.hkHRV
            log.hkSleepHours = backup.hkSleepHours
            log.hkActiveEnergy = backup.hkActiveEnergy
            log.hkMindfulMinutes = backup.hkMindfulMinutes
            context.insert(log)
            summary.insertedLogs += 1
        }

        var existingWeeks = Set(try context.fetch(FetchDescriptor<WeeklyReview>()).map(\.weekStartDate))
        for backup in document.weeklyReviews {
            let week = backup.weekStartDate.startOfWeek
            guard !existingWeeks.contains(week) else { summary.skipped += 1; continue }
            existingWeeks.insert(week)
            let review = WeeklyReview(weekStartDate: week)
            review.promptResponses = backup.promptResponses
            review.overallRating = backup.overallRating
            review.avgMood = backup.avgMood
            review.avgEnergy = backup.avgEnergy
            review.avgSleep = backup.avgSleep
            review.topSymptoms = backup.topSymptoms
            review.isComplete = backup.isComplete
            context.insert(review)
            summary.insertedReviews += 1
        }

        var existingTagNames = Set(try context.fetch(FetchDescriptor<SymptomTag>()).map(\.name))
        for backup in document.symptomTags {
            guard !existingTagNames.contains(backup.name) else { summary.skipped += 1; continue }
            existingTagNames.insert(backup.name)
            context.insert(SymptomTag(name: backup.name, emoji: backup.emoji,
                                      isDefault: backup.isDefault, sortOrder: backup.sortOrder))
            summary.insertedTags += 1
        }

        var existingMeds = Set(try context.fetch(FetchDescriptor<Medication>())
            .map { MedicationIdentity(name: $0.name, startDate: $0.startDate) })
        for backup in document.medications {
            let identity = MedicationIdentity(name: backup.name, startDate: cal.startOfDay(for: backup.startDate))
            guard !existingMeds.contains(identity) else { summary.skipped += 1; continue }
            existingMeds.insert(identity)
            context.insert(Medication(name: backup.name, dosage: backup.dosage,
                                      startDate: backup.startDate, endDate: backup.endDate,
                                      notes: backup.notes))
            summary.insertedMedications += 1
        }

        var existingFlareStarts = Set(try context.fetch(FetchDescriptor<Flare>()).map(\.startDate))
        for backup in document.flares {
            let start = cal.startOfDay(for: backup.startDate)
            guard !existingFlareStarts.contains(start) else { summary.skipped += 1; continue }
            existingFlareStarts.insert(start)
            context.insert(Flare(startDate: backup.startDate, endDate: backup.endDate,
                                 peakSeverity: backup.peakSeverity, note: backup.note))
            summary.insertedFlares += 1
        }

        var existingTrackerIDs = Set(try context.fetch(FetchDescriptor<CustomTracker>()).map(\.id))
        for backup in document.customTrackers {
            guard !existingTrackerIDs.contains(backup.id) else { summary.skipped += 1; continue }
            existingTrackerIDs.insert(backup.id)
            context.insert(CustomTracker(id: backup.id, name: backup.name,
                                         minValue: backup.minValue, maxValue: backup.maxValue,
                                         unit: backup.unit, sortOrder: backup.sortOrder))
            summary.insertedTrackers += 1
        }

        try context.save()
        log.info("Restore merged \(summary.insertedTotal) record(s), skipped \(summary.skipped) existing")
        return summary
    }

    private struct MedicationIdentity: Hashable {
        let name: String
        let startDate: Date
    }

    // MARK: - File helper

    // Writes the encoded document to a shareable temp file named by export date.
    static func writeBackupFile(_ document: Document) throws -> URL {
        let data = try encode(document)
        let stamp = document.exportDate.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cadence-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
