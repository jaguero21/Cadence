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
        // HealthSnapshot included: restore writes hk* values into that model
        // now (it lives in a separate local-only store in the app), so a
        // container without it would not exercise the real restore path.
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self, HealthSnapshot.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        // hk* values land in the separate local-only health store, keyed by day.
        #expect(summary.restoredHealthDays == 1)
        let health = try #require(HealthSnapshot.row(for: day(3), in: context))
        #expect(health.hkSteps == 8200)
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

    // MARK: - Health rows

    // The case that matters most, and the one that used to be skipped entirely:
    // HealthSnapshot lives on the local-only store, so on a new device CloudKit
    // delivers the diary by itself and the backup file is the ONLY route back
    // for the health half. Restoring health only when the log was also missing
    // made restore a no-op in exactly that situation.
    @Test("Health data restores for a day whose log already exists")
    func restoreRecoversHealthForExistingLog() throws {
        let context = try makeContext()
        let existing = DailyLog(date: day(3))
        existing.freeNote = "arrived via CloudKit"
        context.insert(existing)
        try context.save()

        let summary = try BackupService.restore(sampleDocument(), context: context)

        #expect(summary.insertedLogs == 0)
        #expect(summary.skipped == 1)
        #expect(summary.restoredHealthDays == 1)
        let health = try #require(HealthSnapshot.row(for: day(3), in: context))
        #expect(health.hkSteps == 8200)
        #expect(health.hkWorkoutMinutes == 52)
        // The log itself is untouched — the device's copy still wins.
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.freeNote == "arrived via CloudKit")
    }

    @Test("Restore fills gaps in an existing health row without overwriting it")
    func restoreBackfillsHealthRow() throws {
        let context = try makeContext()
        // A row this device measured itself after the backup was written.
        let stored = HealthSnapshot(date: day(3))
        stored.hkSteps = 111
        context.insert(stored)
        try context.save()

        let summary = try BackupService.restore(sampleDocument(), context: context)

        #expect(summary.restoredHealthDays == 1)
        let health = try #require(HealthSnapshot.row(for: day(3), in: context))
        #expect(health.hkSteps == 111)          // device value kept, not the file's 8200
        #expect(health.hkWorkoutMinutes == 52)  // gap filled from the file
        let rows = try context.fetch(FetchDescriptor<HealthSnapshot>())
        #expect(rows.count == 1)                // merged, not duplicated
    }

    @Test("Restoring health that is already present reports nothing recovered")
    func restoreHealthIsIdempotent() throws {
        let context = try makeContext()
        let document = sampleDocument()

        let first = try BackupService.restore(document, context: context)
        let second = try BackupService.restore(document, context: context)

        #expect(first.restoredHealthDays == 1)
        #expect(second.restoredHealthDays == 0)
        let rows = try context.fetch(FetchDescriptor<HealthSnapshot>())
        #expect(rows.count == 1)
    }

    // Mirrors HealthSnapshot.upsert's rule: a backup written before Health
    // access was granted must not litter the store with empty rows.
    @Test("A backup carrying no health values creates no health row")
    func restoreWithoutHealthCreatesNoRow() throws {
        let context = try makeContext()
        var document = sampleDocument()
        document.dailyLogs[0].hkSteps = nil
        document.dailyLogs[0].hkWorkoutMinutes = nil

        let summary = try BackupService.restore(document, context: context)

        #expect(summary.insertedLogs == 1)
        #expect(summary.restoredHealthDays == 0)
        let rows = try context.fetch(FetchDescriptor<HealthSnapshot>())
        #expect(rows.isEmpty)
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

    @Test("A finished, successful import is the one event worth reacting to")
    func reactsToFinishedSuccessfulImport() {
        #expect(CloudSyncMonitor.shouldReactTo(isImport: true, finished: true, succeeded: true))
    }

    @Test("An export is this device's own write, so it triggers nothing")
    func ignoresExport() {
        #expect(!CloudSyncMonitor.shouldReactTo(isImport: false, finished: true, succeeded: true))
    }

    @Test("An in-flight import has nothing to show yet")
    func ignoresUnfinishedImport() {
        #expect(!CloudSyncMonitor.shouldReactTo(isImport: true, finished: false, succeeded: false))
    }

    @Test("A failed import must not trigger a refresh")
    func ignoresFailedImport() {
        #expect(!CloudSyncMonitor.shouldReactTo(isImport: true, finished: true, succeeded: false))
    }
}

// MARK: - Backup across the split stores

// hk* values live on HealthSnapshot (local-only) while everything else lives on
// DailyLog (CloudKit-mirrored). The backup file format is unchanged and still
// carries hk* per day, so these pin that the values survive the trip out of one
// store and back into the other.
@MainActor
@Suite("BackupService – health data across stores", .serialized)
struct BackupHealthStoreTests {

    // Each container gets a UNIQUE configuration name. The restore tests stand
    // up two stores at once (a source device and a target device), and
    // identically-configured in-memory containers created concurrently collide
    // and take the whole test process down — the tests pass individually and
    // crash the bundle when run together. `.serialized` on the suite plus a
    // distinct name per container removes both halves of that race.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self,
                             Medication.self, Flare.self, CustomTracker.self,
                             InsightRecord.self, HealthSnapshot.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test("Backing up reads hk* from the health store, not the log")
    func documentCarriesHealthValues() throws {
        let context = try makeContext()
        let day = Calendar.current.startOfDay(for: .now)
        let log = DailyLog(date: day)
        log.mood = 4
        context.insert(log)
        let health = HealthSnapshot(date: day)
        health.hkSteps = 8200
        health.hkWorkoutMinutes = 52
        context.insert(health)
        try context.save()

        let document = BackupService.document(
            logs: [log], reviews: [], tags: [], medications: [], flares: [], trackers: [],
            health: HealthSnapshot.byDate(in: context)
        )

        let backedUp = try #require(document.dailyLogs.first)
        #expect(backedUp.mood == 4)
        #expect(backedUp.hkSteps == 8200)
        #expect(backedUp.hkWorkoutMinutes == 52)
    }

    @Test("Restoring writes hk* into the health store, keyed to the same day")
    func restoreRebuildsHealthRow() throws {
        let source = try makeContext()
        let day = Calendar.current.startOfDay(for: .now)
        let log = DailyLog(date: day)
        log.freeNote = "travel day"
        source.insert(log)
        let health = HealthSnapshot(date: day)
        health.hkSteps = 8200
        health.hkWristTemp = 35.4
        source.insert(health)
        try source.save()

        let document = BackupService.document(
            logs: [log], reviews: [], tags: [], medications: [], flares: [], trackers: [],
            health: HealthSnapshot.byDate(in: source)
        )

        // Restore into a fresh device.
        let target = try makeContext()
        _ = try BackupService.restore(document, context: target)

        let restoredLog = try #require(try target.fetch(FetchDescriptor<DailyLog>()).first)
        #expect(restoredLog.freeNote == "travel day")

        let restoredHealth = try #require(HealthSnapshot.row(for: day, in: target))
        #expect(restoredHealth.hkSteps == 8200)
        #expect(restoredHealth.hkWristTemp == 35.4)

        // And the join puts them back together for the report/chart consumers.
        let joined = try #require(DailyLogSnapshot.build(from: [restoredLog], in: target).first)
        #expect(joined.hkSteps == 8200)
    }

    @Test("A backup with no health values creates no empty health row")
    func restoreWithoutHealthValuesCreatesNoRow() throws {
        let source = try makeContext()
        let log = DailyLog(date: .now)
        source.insert(log)
        try source.save()

        // No `health:` argument — the same shape as a backup taken on a device
        // that never granted Health access.
        let document = BackupService.document(
            logs: [log], reviews: [], tags: [], medications: [], flares: [], trackers: []
        )

        let target = try makeContext()
        _ = try BackupService.restore(document, context: target)

        #expect(try target.fetch(FetchDescriptor<DailyLog>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<HealthSnapshot>()).isEmpty)
    }
}

// MARK: - Reacting to a CloudKit import

@MainActor
@Suite struct RemoteImportRefreshTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self, HealthSnapshot.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    // Every test below calls applyRemoteImport, which republishes through
    // DashboardViewModel.publishWidgetSummary into the REAL App Group suite
    // (group.com.carpecadence.app, via WidgetData) — CadenceTests hosts
    // inside the app, so there is no test-only container to redirect writes
    // to, and every run was previously leaving a fabricated summary behind
    // for the simulator's actual widget to read, with nothing restoring it.
    // WidgetData's only surface is write(_:)/read() -> Summary? — there is no
    // clear/delete API to hand a nil-prior test back to "nothing stored" — so
    // that case is handled by reaching into the same suite/key WidgetData
    // itself uses. The key string duplicates WidgetData's own private `key`
    // constant ("todaySummary"); that duplication is the price of restoring
    // state correctly without adding a delete API to production code for
    // what only this test file needs.
    private static let widgetSummaryKey = "todaySummary"

    private func restoreWidgetSummary(_ prior: WidgetData.Summary?) {
        if let prior {
            WidgetData.write(prior)
        } else {
            UserDefaults(suiteName: WidgetData.appGroup)?.removeObject(forKey: Self.widgetSummaryKey)
        }
    }

    // applyRemoteImport now also writes UserDefaultsKey.lastRemoteImportFingerprint
    // (see Fix 1) into the same real, process-wide UserDefaults.standard the
    // throttle key already lives in — same restoration need as the widget
    // summary above, for the same reason: a leftover value from an earlier
    // run must not leak into this one.
    private func restoreFingerprint(_ prior: String?) {
        if let prior {
            UserDefaults.standard.set(prior, forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        }
    }

    // Populated-store case: the normal path, where the fetch returns a real
    // row and publishWidgetSummary has actual log data to compute
    // loggedToday/streak/pose from. This used to be word-for-word identical
    // to emptyStoreIsSafe below (same zero-row makeContext(), same seed, same
    // call, same assertion) — nothing distinguished "clears the throttle"
    // from "survives an empty store". Inserting a log here makes this test
    // own the populated-store path exclusively, leaving emptyStoreIsSafe as
    // the only test covering the empty one.
    @Test("A remote import clears the insight throttle so the next foreground recomputes")
    func clearsInsightThrottle() throws {
        let context = try makeContext()
        let log = DailyLog(date: .now)
        log.isComplete = true
        context.insert(log)
        try context.save()

        let today = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        UserDefaults.standard.set(today, forKey: UserDefaultsKey.lastInsightCheckDay)

        // applyRemoteImport republishes the widget summary as a side effect
        // of clearing the throttle (see suite-level comment) — snapshot/
        // restore even though this test's focus is the throttle, or the
        // populated log inserted above would leave a real summary behind.
        let priorSummary = WidgetData.read()
        defer { restoreWidgetSummary(priorSummary) }
        // Fix 1 gates the throttle clear on a fingerprint; snapshot/restore it
        // too, or this run's fingerprint leaks into whichever test runs next.
        // There's no sub-millisecond timestamp to lean on here — DailyLog.init
        // normalizes `date` to startOfDay, so this test's fingerprint is
        // byte-identical on every run made on the same calendar day (and
        // identical to unchangedImportDoesNotClearThrottle's). Seed a sentinel
        // guaranteed to differ, the same way emptyStoreIsSafe below does, or a
        // leftover value from an earlier run that died between
        // applyRemoteImport and this defer (host crash mid-run — see
        // BackupServiceTests' own restoration comments elsewhere) would read
        // as "unchanged" and this assertion would flake.
        let priorFingerprint = UserDefaults.standard.string(forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        defer { restoreFingerprint(priorFingerprint) }
        UserDefaults.standard.set("sentinel-guaranteed-to-differ", forKey: UserDefaultsKey.lastRemoteImportFingerprint)

        CadenceApp.applyRemoteImport(context: context)

        #expect(UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay) == 0)
    }

    // Empty-store case: a first sync on a new device imports into an empty
    // log table before any DailyLog exists locally, and the fetch must
    // default to `[]` rather than trap. Now that clearsInsightThrottle above
    // populates its store, this is the only test left covering that empty-
    // fetch path — the two exercise genuinely different inputs to the same
    // function rather than duplicating each other. Seeded to a nonzero value
    // first, same as clearsInsightThrottle — an UNSET key already reads back
    // as 0, so without seeding this would still pass even if
    // applyRemoteImport's body were deleted entirely.
    @Test("A remote import into an empty store does not trap")
    func emptyStoreIsSafe() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        UserDefaults.standard.set(today, forKey: UserDefaultsKey.lastInsightCheckDay)

        // Same reasoning as clearsInsightThrottle: applyRemoteImport always
        // republishes, empty store or not, so this must restore too.
        let priorSummary = WidgetData.read()
        defer { restoreWidgetSummary(priorSummary) }

        // Unlike clearsInsightThrottle, an empty store's fingerprint
        // ("0 logs | no date | 0 complete") is the SAME every single run —
        // there's no `.now` timestamp to make it differ. A leftover value
        // from an earlier run of this exact test would already match, the
        // guard in applyRemoteImport would see "unchanged", and the throttle
        // would wrongly stay set — for the same reason
        // republishesWidgetSummary below seeds a stale widget summary, seed a
        // sentinel here that's guaranteed to differ from the real empty-store
        // fingerprint.
        let priorFingerprint = UserDefaults.standard.string(forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        defer { restoreFingerprint(priorFingerprint) }
        UserDefaults.standard.set("sentinel-guaranteed-to-differ", forKey: UserDefaultsKey.lastRemoteImportFingerprint)

        CadenceApp.applyRemoteImport(context: context)

        #expect(UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay) == 0)
    }

    // The widget republish is the OTHER reaction applyRemoteImport performs,
    // and until now nothing asserted it — the publishWidgetSummary call could
    // be deleted and every test here would still pass. The App Group suite is
    // a real file that outlives a single test run, so a summary left over from
    // an earlier pass could already equal what today's insert should produce;
    // publishWidgetSummary's own `guard summary != WidgetData.read() else {
    // return }` would then skip the write, and a stale-but-matching value on
    // disk would pass this test for the wrong reason. Seeding a summary that's
    // guaranteed to differ (an old date, not logged) rules that out: the
    // assertions below can only hold if applyRemoteImport actually recomputed
    // and wrote a fresh summary.
    @Test("A remote import republishes the widget summary for today's log")
    func republishesWidgetSummary() throws {
        let context = try makeContext()
        // isComplete is the flag publishWidgetSummary reads for `loggedToday`
        // (DashboardViewModel.publishWidgetSummary: `logs.first { ... }?.isComplete
        // == true`) — set directly, the same way DailyLogViewModel.save() and
        // the sampleDocument() log above do; it isn't derived from the other
        // fields.
        let log = DailyLog(date: .now)
        log.isComplete = true
        context.insert(log)
        try context.save()

        // Captured before this test's own seed write below, not just before
        // applyRemoteImport — the stale-summary seed is itself a write to the
        // real App Group store that must be undone too.
        let priorSummary = WidgetData.read()
        defer { restoreWidgetSummary(priorSummary) }
        // Widget republish is unconditional (see Fix 1 comment on
        // applyRemoteImport), so this test doesn't depend on the fingerprint
        // at all — restored purely so this run doesn't leave a value behind
        // for a later test to trip over.
        let priorFingerprint = UserDefaults.standard.string(forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        defer { restoreFingerprint(priorFingerprint) }

        let staleDate = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        WidgetData.write(WidgetData.Summary(date: staleDate, loggedToday: false, streak: 0, mascotPose: .welcoming))

        CadenceApp.applyRemoteImport(context: context)

        let summary = try #require(WidgetData.read())
        #expect(Calendar.current.isDateInToday(summary.date))
        #expect(summary.loggedToday == true)
    }

    // Fix 1: NSPersistentCloudKitContainer reports succeeded == true for an
    // import pass that changed nothing — including the pass that fires from
    // THIS device's own export, since CloudKit echoes every push back as a
    // change notification. Without the fingerprint check in
    // applyRemoteImport, a single-device Pro user would clear
    // lastInsightCheckDay (and pay the synchronous 90-day PatternEngine pass)
    // on every one of their own writes instead of once a day.
    @Test("A second import with unchanged data does not clear the insight throttle")
    func unchangedImportDoesNotClearThrottle() throws {
        let context = try makeContext()
        let log = DailyLog(date: .now)
        log.isComplete = true
        context.insert(log)
        try context.save()

        let priorSummary = WidgetData.read()
        defer { restoreWidgetSummary(priorSummary) }
        let priorFingerprint = UserDefaults.standard.string(forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        defer { restoreFingerprint(priorFingerprint) }
        let priorCheckDay = UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay)
        defer { UserDefaults.standard.set(priorCheckDay, forKey: UserDefaultsKey.lastInsightCheckDay) }

        // First pass establishes the fingerprint baseline for this exact log
        // set (and, incidentally, clears the throttle — that's covered by
        // clearsInsightThrottle above, not the point here).
        CadenceApp.applyRemoteImport(context: context)

        // Simulate the state a real device is in right after that first
        // import let the foreground path run: today's date is stamped.
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        UserDefaults.standard.set(today, forKey: UserDefaultsKey.lastInsightCheckDay)

        // React to the SAME data again — the no-op pass this device's own
        // export triggers. Must not clear the throttle.
        CadenceApp.applyRemoteImport(context: context)

        #expect(UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay) == today)
    }

    @Test("An import that adds a log clears the insight throttle")
    func addedLogClearsThrottle() throws {
        let context = try makeContext()
        let firstLog = DailyLog(date: .now)
        firstLog.isComplete = true
        context.insert(firstLog)
        try context.save()

        let priorSummary = WidgetData.read()
        defer { restoreWidgetSummary(priorSummary) }
        let priorFingerprint = UserDefaults.standard.string(forKey: UserDefaultsKey.lastRemoteImportFingerprint)
        defer { restoreFingerprint(priorFingerprint) }
        let priorCheckDay = UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay)
        defer { UserDefaults.standard.set(priorCheckDay, forKey: UserDefaultsKey.lastInsightCheckDay) }

        // Baseline fingerprint for the first log only.
        CadenceApp.applyRemoteImport(context: context)
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        UserDefaults.standard.set(today, forKey: UserDefaultsKey.lastInsightCheckDay)

        // A second day arrives from the remote import — count and completed
        // count both change. Latest date does NOT: this log lands at -1 day,
        // so firstLog's (today's) date stays the max() of the two.
        let secondLog = DailyLog(date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .distantPast)
        secondLog.isComplete = true
        context.insert(secondLog)
        try context.save()

        CadenceApp.applyRemoteImport(context: context)

        #expect(UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay) == 0)
    }

    // CloudKit delivers one sync pass as a burst of events. WidgetCenter
    // reloads are system-budgeted, so the burst must cost one refresh.
    @Test("A burst of import events collapses into a single refresh")
    func coalescesBurst() async throws {
        let monitor = CloudSyncMonitor()
        monitor.coalesceInterval = .milliseconds(50)
        var calls = 0
        monitor.onRemoteImport = { calls += 1 }

        for _ in 0..<5 {
            monitor.apply(isImport: true, finished: true, succeeded: true,
                          endDate: .now, errorDescription: nil)
        }
        try await Task.sleep(for: .milliseconds(300))

        #expect(calls == 1)
    }

    @Test("An export never reaches the refresh callback")
    func exportDoesNotTriggerRefresh() async throws {
        let monitor = CloudSyncMonitor()
        monitor.coalesceInterval = .milliseconds(50)
        var calls = 0
        monitor.onRemoteImport = { calls += 1 }

        monitor.apply(isImport: false, finished: true, succeeded: true,
                      endDate: .now, errorDescription: nil)
        try await Task.sleep(for: .milliseconds(300))

        #expect(calls == 0)
    }
}
