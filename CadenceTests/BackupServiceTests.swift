import Testing
import Foundation
import SwiftData
@testable import Cadence

// Backup/restore: the encode→decode round trip must be lossless for every
// user-entered field, and restore must merge (never clobber) against a store
// that already has data. Also covers the CloudSyncMonitor's pure state fold.
@MainActor
@Suite struct BackupServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!)
    }

    private func sampleDocument(trackerID: UUID = UUID()) -> BackupService.Document {
        var log = BackupService.DailyLogBackup(date: day(3))
        log.mood = 4
        log.energy = 7
        log.symptoms = [SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")]
        log.factors = ["Alcohol"]
        log.customMetrics = [MetricEntry(trackerID: trackerID, value: 5)]
        log.freeNote = "rough morning"
        log.isComplete = true
        log.hkSteps = 8200
        log.hkWorkoutMinutes = 52
        log.peaksAndValleysNote = "Best: a walk. Worst: a headache."
        log.intentionsForTomorrow = "Sleep earlier"

        var review = BackupService.WeeklyReviewBackup(weekStartDate: day(10).startOfWeek)
        review.overallRating = 4
        review.promptResponses = [PromptResponse(section: "Wins This Week", prompt: "What went well?", response: "Slept more")]
        review.isComplete = true
        review.intentionsForTomorrow = "Start the week with a plan"

        return BackupService.Document(
            dailyLogs: [log],
            weeklyReviews: [review],
            symptomTags: [BackupService.SymptomTagBackup(name: "Tinnitus", emoji: "🔔", isDefault: false, sortOrder: 9)],
            medications: [BackupService.MedicationBackup(name: "Sertraline", dosage: "50 mg", startDate: day(30), reminderMinutes: [540])],
            flares: [BackupService.FlareBackup(startDate: day(14), endDate: day(12), peakSeverity: 8, note: "bad stretch")],
            customTrackers: [BackupService.CustomTrackerBackup(id: trackerID, name: "Hydration", minValue: 0, maxValue: 8, unit: "glasses", sortOrder: 0)]
        )
    }

    @Test("Encode → decode round trip preserves every field")
    func roundTrip() throws {
        let trackerID = UUID()
        let document = sampleDocument(trackerID: trackerID)

        let decoded = try BackupService.decode(try BackupService.encode(document))

        #expect(decoded.version == BackupService.currentVersion)
        let log = try #require(decoded.dailyLogs.first)
        #expect(log.mood == 4)
        #expect(log.symptoms.first?.name == "Headache")
        #expect(log.factors == ["Alcohol"])
        #expect(log.customMetrics.first?.trackerID == trackerID)
        #expect(log.hkSteps == 8200)
        #expect(log.hkWorkoutMinutes == 52)
        #expect(log.peaksAndValleysNote == "Best: a walk. Worst: a headache.")
        #expect(log.intentionsForTomorrow == "Sleep earlier")
        let review = try #require(decoded.weeklyReviews.first)
        #expect(review.promptResponses.first?.response == "Slept more")
        #expect(review.intentionsForTomorrow == "Start the week with a plan")
        #expect(decoded.symptomTags.first?.name == "Tinnitus")
        #expect(decoded.medications.first?.dosage == "50 mg")
        #expect(decoded.medications.first?.reminderMinutes == [540])
        #expect(decoded.flares.first?.peakSeverity == 8)
        let tracker = try #require(decoded.customTrackers.first)
        #expect(tracker.id == trackerID)
        #expect(tracker.unit == "glasses")
    }

    @Test("Restore into an empty store inserts everything")
    func restoreIntoEmptyStore() throws {
        let context = try makeContext()
        let trackerID = UUID()

        let summary = try BackupService.restore(sampleDocument(trackerID: trackerID), context: context)

        #expect(summary.insertedTotal == 6)
        #expect(summary.skipped == 0)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.customMetrics.first?.trackerID == trackerID)
        #expect(logs.first?.peaksAndValleysNote == "Best: a walk. Worst: a headache.")
        #expect(logs.first?.intentionsForTomorrow == "Sleep earlier")
        // Tracker id must survive restore — metric history is keyed by it.
        let trackers = try context.fetch(FetchDescriptor<CustomTracker>())
        #expect(trackers.first?.id == trackerID)
        let reviews = try context.fetch(FetchDescriptor<WeeklyReview>())
        #expect(reviews.first?.intentionsForTomorrow == "Start the week with a plan")
    }

    @Test("Restore merges: existing records win, missing ones are added")
    func restoreMergesWithoutClobbering() throws {
        let context = try makeContext()

        // The device already has a log for the same day with different data.
        let existing = DailyLog(date: day(3))
        existing.mood = 1
        existing.freeNote = "device copy"
        context.insert(existing)
        try context.save()

        let summary = try BackupService.restore(sampleDocument(), context: context)

        // The log was skipped; everything else inserted.
        #expect(summary.insertedLogs == 0)
        #expect(summary.skipped == 1)
        #expect(summary.insertedTotal == 5)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.freeNote == "device copy")
    }

    @Test("Restoring the same backup twice is a no-op the second time")
    func restoreIsIdempotent() throws {
        let context = try makeContext()
        let document = sampleDocument()

        _ = try BackupService.restore(document, context: context)
        let second = try BackupService.restore(document, context: context)

        #expect(second.insertedTotal == 0)
        #expect(second.skipped == 6)
    }

    @Test("A backup from a newer format version is rejected")
    func newerVersionRejected() throws {
        var document = sampleDocument()
        document.version = BackupService.currentVersion + 1

        let data = try BackupService.encode(document)
        #expect(throws: BackupService.BackupError.self) {
            _ = try BackupService.decode(data)
        }
    }
}

@MainActor
@Suite struct CloudSyncStateTests {

    @Test("An in-flight event reads as syncing")
    func inFlightEvent() {
        let state = CloudSyncMonitor.stateAfterEvent(
            finished: false, succeeded: false, endDate: nil,
            errorDescription: nil, previous: .waiting
        )
        #expect(state == .syncing)
    }

    @Test("A successful finished event reads as synced at its end date")
    func successfulEvent() {
        let end = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let state = CloudSyncMonitor.stateAfterEvent(
            finished: true, succeeded: true, endDate: end,
            errorDescription: nil, previous: .syncing
        )
        #expect(state == .synced(end))
    }

    @Test("A failed finished event surfaces the error")
    func failedEvent() {
        let state = CloudSyncMonitor.stateAfterEvent(
            finished: true, succeeded: false, endDate: .now,
            errorDescription: "quota exceeded", previous: .synced(.now)
        )
        #expect(state == .error("quota exceeded"))
    }
}
