import Testing
import Foundation
import SwiftData
@testable import Cadence

// MARK: - Seam tests
//
// The code-review pass showed the real bugs live at the boundaries between
// subsystems (watch↔phone, app↔widget), not inside the unit logic. These tests
// pin the two seams that carry user data across process/device lines.

// MARK: Watch → phone quick-log upsert

@Suite("PhoneConnectivityManager – applyQuickLog")
@MainActor
struct QuickLogSeamTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func payload(mood: Int? = 4, energy: Int? = 6, daysAgo: Int? = 0) -> [String: Any] {
        var p: [String: Any] = [:]
        if let mood { p["mood"] = mood }
        if let energy { p["energy"] = energy }
        if let daysAgo {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            p["date"] = date.timeIntervalSinceReferenceDate
        }
        return p
    }

    // Regression for the review's top finding: a payload queued overnight must
    // land on the day it was RECORDED, not the day it arrives.
    @Test("A payload recorded yesterday lands on yesterday's log")
    func queuedPayload_landsOnRecordedDay() throws {
        let context = try makeContext()
        let saved = PhoneConnectivityManager.applyQuickLog(payload(daysAgo: 1), context: context)
        #expect(saved)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
        #expect(logs.first?.date == yesterday)
    }

    @Test("A queued payload from yesterday does not touch today's log")
    func queuedPayload_doesNotClobberToday() throws {
        let context = try makeContext()
        let todayLog = DailyLog()
        todayLog.mood = 5
        todayLog.didEditMood = true
        context.insert(todayLog)
        try context.save()

        PhoneConnectivityManager.applyQuickLog(payload(mood: 1, daysAgo: 1), context: context)

        let logs = try context.fetch(FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date)]))
        #expect(logs.count == 2)                       // yesterday created, today untouched
        let today = logs.last
        #expect(today?.mood == 5)                      // today's user-entered mood survives
        #expect(logs.first?.mood == 1)                 // wrist entry on yesterday
    }

    @Test("A same-day payload merges into the existing log, preserving other fields")
    func samedayPayload_mergesIntoExistingLog() throws {
        let context = try makeContext()
        let existing = DailyLog()
        existing.freeNote = "already writing today"
        existing.sleepHours = 6.5
        context.insert(existing)
        try context.save()

        PhoneConnectivityManager.applyQuickLog(payload(mood: 2, energy: 3, daysAgo: 0), context: context)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)                       // merged, no same-date duplicate
        #expect(logs.first?.mood == 2)
        #expect(logs.first?.energy == 3)
        #expect(logs.first?.didEditMetrics == true)
        #expect(logs.first?.freeNote == "already writing today")   // untouched
        #expect(logs.first?.sleepHours == 6.5)                     // untouched
    }

    @Test("A payload without a date lands on today")
    func missingDate_defaultsToToday() throws {
        let context = try makeContext()
        PhoneConnectivityManager.applyQuickLog(payload(daysAgo: nil), context: context)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.first?.date == Calendar.current.startOfDay(for: .now))
    }

    @Test("Out-of-range values are clamped to the model's scales")
    func outOfRangeValues_areClamped() throws {
        let context = try makeContext()
        PhoneConnectivityManager.applyQuickLog(payload(mood: 99, energy: -3), context: context)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.first?.mood == 5)
        #expect(logs.first?.energy == 0)
    }

    @Test("A quick log records what the day looked like before it")
    func quickLog_recordsPreviousState() throws {
        QuickLogUndo.clear()
        let context = try makeContext()
        let existing = DailyLog()
        existing.mood = 2
        existing.didEditMood = true
        existing.energy = 7
        existing.didEditMetrics = true
        context.insert(existing)
        try context.save()

        PhoneConnectivityManager.applyQuickLog(payload(mood: 5, energy: 9, daysAgo: 0), context: context, source: .siri)

        let record = try #require(QuickLogUndo.stored())
        #expect(record.createdLog == false)
        #expect(record.previousMood == 2)
        #expect(record.previousEnergy == 7)
        #expect(record.previousDidEditMood)
        #expect(record.appliedMood == 5)
        #expect(record.source == .siri)
    }

    @Test("A quick log on a fresh day records that it created the log")
    func quickLog_recordsCreation() throws {
        QuickLogUndo.clear()
        let context = try makeContext()
        PhoneConnectivityManager.applyQuickLog(payload(mood: 3, daysAgo: 0), context: context, source: .watch)
        let record = try #require(QuickLogUndo.stored())
        #expect(record.createdLog)
        #expect(record.source == .watch)
    }

    @Test("A payload without a mood is rejected and persists nothing")
    func missingMood_isNoOp() throws {
        let context = try makeContext()
        let saved = PhoneConnectivityManager.applyQuickLog(payload(mood: nil), context: context)
        #expect(saved == false)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.isEmpty)
    }
}

// MARK: Watch payload → Sendable value

// WCSessionDelegate hands us `[String: Any]`, which can't cross to the main
// actor under Swift 6. QuickLogPayload is the Sendable form, parsed on the
// delegate side. It does TYPE EXTRACTION ONLY: clamping stays in the upsert
// (covered by QuickLogSeamTests.outOfRangeValues_areClamped above).
@Suite("QuickLogPayload – parsing")
struct QuickLogPayloadTests {

    @Test("A complete payload keeps mood, energy, and date")
    func completePayload_keepsAllFields() throws {
        let recorded = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let parsed = try #require(QuickLogPayload(["mood": 4, "energy": 6, "date": recorded.timeIntervalSinceReferenceDate]))
        #expect(parsed.mood == 4)
        #expect(parsed.energy == 6)
        #expect(parsed.date == recorded)
    }

    @Test("A payload without a mood doesn't parse")
    func missingMood_isNil() {
        #expect(QuickLogPayload(["energy": 6]) == nil)
    }

    @Test("A non-integer mood doesn't parse")
    func nonIntegerMood_isNil() {
        #expect(QuickLogPayload(["mood": "3"]) == nil)
    }

    @Test("A non-integer energy is dropped, not fatal")
    func nonIntegerEnergy_isIgnored() throws {
        let parsed = try #require(QuickLogPayload(["mood": 2, "energy": "high"]))
        #expect(parsed.mood == 2)
        #expect(parsed.energy == nil)
    }

    @Test("A payload without a date is stamped now")
    func missingDate_isNow() throws {
        let parsed = try #require(QuickLogPayload(["mood": 3]))
        #expect(abs(parsed.date.timeIntervalSinceNow) < 1)
    }

    @Test("Out-of-range values pass through unclamped")
    func outOfRange_isNotClamped() throws {
        let parsed = try #require(QuickLogPayload(["mood": 99, "energy": -3]))
        #expect(parsed.mood == 99)
        #expect(parsed.energy == -3)
    }
}

// MARK: App → widget summary staleness

@Suite("WidgetData – resolved summary staleness")
struct WidgetStalenessTests {

    private func day(_ offset: Int, from now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now))!
    }

    @Test("No stored summary resolves to not-logged with no streak")
    func noSummary_resolvesToZeros() {
        let resolved = WidgetData.resolved(nil, now: .now)
        #expect(resolved.loggedToday == false)
        #expect(resolved.streak == 0)
    }

    @Test("A summary from today passes through unchanged")
    func todaySummary_passesThrough() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(0, from: now), loggedToday: true, streak: 7, mascotPose: .welcoming)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved == stored)
    }

    // Regression for the review finding: after midnight the widget must not
    // keep showing yesterday's "Logged today" — but yesterday's streak is
    // still alive until tonight.
    @Test("Yesterday's summary drops loggedToday but keeps the streak")
    func yesterdaySummary_dropsLoggedTodayKeepsStreak() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-1, from: now), loggedToday: true, streak: 7, mascotPose: .welcoming)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.loggedToday == false)
        #expect(resolved.streak == 7)
    }

    @Test("A summary older than yesterday resets the streak to zero")
    func olderSummary_breaksStreak() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-3, from: now), loggedToday: true, streak: 7, mascotPose: .welcoming)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.loggedToday == false)
        #expect(resolved.streak == 0)
    }

    // Regression: .soaking's whole meaning is "streak >= threshold" — once
    // the streak resets to zero it must not keep showing, since it would
    // directly contradict the zeroed streak count displayed beside it.
    @Test("A broken streak downgrades a soaking pose to resting")
    func olderSummary_downgradesSoakingPose() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-3, from: now), loggedToday: true, streak: 7, mascotPose: .soaking)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.streak == 0)
        #expect(resolved.mascotPose == .resting)
    }

    // Regression: unlike .soaking, .cozy isn't derived from the streak
    // number, so a broken streak shouldn't touch it — the flare/mood signal
    // that triggered it may still hold.
    @Test("A broken streak leaves a cozy pose untouched")
    func olderSummary_leavesCozyPoseUntouched() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-3, from: now), loggedToday: true, streak: 7, mascotPose: .cozy)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.streak == 0)
        #expect(resolved.mascotPose == .cozy)
    }

    // Regression: the one-day grace period means the streak (and therefore
    // .soaking's validity) hasn't actually broken yet — no downgrade.
    @Test("Yesterday's summary keeps a soaking pose (streak still alive)")
    func yesterdaySummary_keepsSoakingPose() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-1, from: now), loggedToday: true, streak: 7, mascotPose: .soaking)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.streak == 7)
        #expect(resolved.mascotPose == .soaking)
    }

    // Regression: a Summary persisted by a build from before `mascotPose`
    // existed has no such key. It must decode (defaulting the pose to
    // welcoming) so the real streak/loggedToday survive — a hard decode
    // failure there would reset the widget to zeros on the first launch
    // after updating. `date` is a bare TimeInterval to match the default
    // JSONEncoder WidgetData.write uses.
    @Test("A pre-mascot summary blob decodes, defaulting the pose and keeping the streak")
    func legacySummary_withoutMascotPose_decodes() throws {
        let legacy = Data(#"{"date": 0, "loggedToday": true, "streak": 9}"#.utf8)
        let decoded = try JSONDecoder().decode(WidgetData.Summary.self, from: legacy)
        #expect(decoded.streak == 9)
        #expect(decoded.loggedToday == true)
        #expect(decoded.mascotPose == .welcoming)
    }
}

// MARK: Widget → app pending quick-log queue

// The widget's mood buttons can't write to SwiftData; they stash taps in the
// App Group and the app applies them on foreground through the same upsert
// seam the watch uses. These tests pin the queue semantics with an isolated
// UserDefaults suite.
@Suite("WidgetData – pending quick logs")
@MainActor
struct PendingQuickLogTests {

    private func isolatedDefaults() -> UserDefaults {
        let name = "pending-quicklog-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Stash then consume returns the tap and clears the queue")
    func stashConsumeRoundTrip() {
        let defaults = isolatedDefaults()
        WidgetData.stashPendingQuickLog(mood: 4, defaults: defaults)

        let consumed = WidgetData.consumePendingQuickLogs(defaults: defaults)
        #expect(consumed.map(\.mood) == [4])
        #expect(WidgetData.consumePendingQuickLogs(defaults: defaults).isEmpty)
    }

    @Test("Multiple taps queue in order and consume together")
    func multipleTaps() {
        let defaults = isolatedDefaults()
        WidgetData.stashPendingQuickLog(mood: 2, defaults: defaults)
        WidgetData.stashPendingQuickLog(mood: 5, defaults: defaults)

        #expect(WidgetData.consumePendingQuickLogs(defaults: defaults).map(\.mood) == [2, 5])
    }

    @Test("pendingMood returns the latest tap for the given day only")
    func pendingMoodPerDay() {
        let defaults = isolatedDefaults()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        WidgetData.stashPendingQuickLog(mood: 1, date: yesterday, defaults: defaults)
        WidgetData.stashPendingQuickLog(mood: 3, defaults: defaults)
        WidgetData.stashPendingQuickLog(mood: 5, defaults: defaults)

        #expect(WidgetData.pendingMood(on: .now, defaults: defaults) == 5)
        #expect(WidgetData.pendingMood(on: yesterday, defaults: defaults) == 1)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        #expect(WidgetData.pendingMood(on: tomorrow, defaults: defaults) == nil)
    }

    @Test("The queue is bounded: oldest taps drop past the cap")
    func queueIsBounded() {
        let defaults = isolatedDefaults()
        for mood in 0..<40 {
            WidgetData.stashPendingQuickLog(mood: (mood % 5) + 1, defaults: defaults)
        }
        #expect(WidgetData.consumePendingQuickLogs(defaults: defaults).count == 30)
    }

    // End-to-end: a tap stashed yesterday flows through the payload bridge into
    // the same wrong-day-safe upsert the watch path uses.
    @Test("A stashed tap from yesterday lands on yesterday's log via the upsert seam")
    func stashedTapLandsOnRecordedDay() throws {
        let defaults = isolatedDefaults()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        WidgetData.stashPendingQuickLog(mood: 2, date: yesterday, defaults: defaults)

        let schema = Schema([DailyLog.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))

        for entry in WidgetData.consumePendingQuickLogs(defaults: defaults) {
            #expect(PhoneConnectivityManager.applyQuickLog(entry.payload, context: context))
        }

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.date == Calendar.current.startOfDay(for: yesterday))
        #expect(logs.first?.mood == 2)
    }
}

// MARK: Legally required links

// App Review Guideline 3.1.2 requires functional Terms of Use and Privacy
// Policy links on the purchase screen. Both call sites (ProPaywallView and
// SettingsView.proSection) render them behind `if let`, so a malformed URL
// would not crash — it would silently omit a link Apple requires and reject
// the build for. These parse checks make that failure loud and local.
@Suite("CadenceURL – required links parse")
struct CadenceURLTests {

    @Test("Every public URL parses")
    func allURLsParse() {
        #expect(CadenceURL.privacyPolicy != nil)
        #expect(CadenceURL.terms != nil)
        #expect(CadenceURL.site != nil)
    }

    @Test("The two links Guideline 3.1.2 requires are absolute https URLs")
    func legalLinksAreAbsoluteHTTPS() throws {
        for url in [try #require(CadenceURL.terms), try #require(CadenceURL.privacyPolicy)] {
            #expect(url.scheme == "https")
            #expect(url.host?.isEmpty == false)
        }
    }
}

// MARK: - Dashboard 7-Day Snapshot

// The first card a user sees. It previously took `logs.prefix(7)` out of a
// 90-day query (so a month-old week still read "7 / 7") and averaged over
// DailyLog's DEFAULTS for days the user never edited (mood 3, energy 5,
// sleep 7.0) — inventing numbers nobody entered.
@Suite("DashboardViewModel – sevenDayStats")
struct SevenDayStatsTests {

    private let today = Calendar.current.startOfDay(for: .now)

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    private func log(_ daysAgo: Int, mood: Int = 3, energy: Int = 5, sleep: Double = 7.0,
                     editedMood: Bool = true, editedMetrics: Bool = true) -> DailyLogSnapshot {
        DailyLogSnapshot(date: day(daysAgo), mood: mood, energy: energy, sleepHours: sleep,
                         didEditMetrics: editedMetrics, didEditMood: editedMood)
    }

    @Test("Logs older than the trailing seven days are excluded")
    func excludesLogsOutsideTheWindow() {
        // Seven real logs, but all of them three weeks ago — the exact shape
        // that used to report a perfect week.
        let stale = (21...27).map { log($0) }
        let stats = DashboardViewModel.sevenDayStats(from: stale, referenceDate: today)
        #expect(stats.loggedDays == 0)
        #expect(stats.averageMood == nil)
        #expect(stats.averageSleepHours == nil)
    }

    @Test("The window is seven calendar days including today")
    func windowIsInclusiveOfToday() {
        let stats = DashboardViewModel.sevenDayStats(
            from: [log(0), log(6), log(7)],   // today, the edge, and one day past it
            referenceDate: today
        )
        #expect(stats.loggedDays == 2)
    }

    @Test("Unedited days never contribute their model defaults to an average")
    func unEditedDaysDoNotSkewAverages() {
        let stats = DashboardViewModel.sevenDayStats(
            from: [
                log(0, mood: 5, energy: 9, sleep: 9.0),
                // A widget mood tap: mood is real, the sliders were never touched.
                log(1, mood: 1, energy: 5, sleep: 7.0, editedMood: true, editedMetrics: false),
            ],
            referenceDate: today
        )
        #expect(stats.loggedDays == 2)
        #expect(stats.averageMood == 3.0)          // (5 + 1) / 2 — both moods are real
        #expect(stats.averageEnergy == 9.0)        // only the edited day counts
        #expect(stats.averageSleepHours == 9.0)    // not 8.0, which the 7.0 default would give
    }

    @Test("A week with logs but no edited values reports days without inventing averages")
    func loggedButUneditedReportsNilAverages() {
        let stats = DashboardViewModel.sevenDayStats(
            from: [log(0, editedMood: false, editedMetrics: false)],
            referenceDate: today
        )
        #expect(stats.loggedDays == 1)
        #expect(stats.averageMood == nil)
        #expect(stats.averageEnergy == nil)
        #expect(stats.averageSleepHours == nil)
    }

    @Test("Duplicate logs for one day count once (CloudKit can create them)")
    func duplicateDaysCountOnce() {
        let stats = DashboardViewModel.sevenDayStats(from: [log(2), log(2)], referenceDate: today)
        #expect(stats.loggedDays == 1)
    }

    @Test("No logs at all yields an empty snapshot")
    func emptyInputIsEmpty() {
        #expect(DashboardViewModel.sevenDayStats(from: [], referenceDate: today) == DashboardViewModel.SevenDayStats())
    }
}

// MARK: Undo for a quick check-in

// The offer has to retire itself: undoing after the person has edited the day
// would throw away work they did by hand.
@Suite("QuickLogUndo – offering and applying")
@MainActor
struct QuickLogUndoTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func payload(mood: Int, energy: Int? = nil) -> [String: Any] {
        var p: [String: Any] = ["mood": mood, "date": Date.now.timeIntervalSinceReferenceDate]
        if let energy { p["energy"] = energy }
        return p
    }

    @Test("Undo restores the mood and energy the day had before")
    func undo_restoresPreviousValues() throws {
        QuickLogUndo.clear()
        let context = try makeContext()
        let existing = DailyLog()
        existing.mood = 2; existing.didEditMood = true
        existing.energy = 7; existing.didEditMetrics = true
        context.insert(existing); try context.save()

        PhoneConnectivityManager.applyQuickLog(payload(mood: 5, energy: 9), context: context, source: .siri)
        let record = try #require(QuickLogUndo.availableRecord(in: context))
        QuickLogUndo.undo(record: record, in: context)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.mood == 2)
        #expect(logs.first?.energy == 7)
        #expect(QuickLogUndo.stored() == nil)
    }

    @Test("Undo deletes the log the quick check-in created")
    func undo_deletesCreatedLog() throws {
        QuickLogUndo.clear()
        let context = try makeContext()
        PhoneConnectivityManager.applyQuickLog(payload(mood: 4), context: context, source: .siri)
        let record = try #require(QuickLogUndo.availableRecord(in: context))
        QuickLogUndo.undo(record: record, in: context)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).isEmpty)
    }

    @Test("Editing the day by hand retires the offer")
    func manualEdit_retiresRecord() throws {
        QuickLogUndo.clear()
        let context = try makeContext()
        PhoneConnectivityManager.applyQuickLog(payload(mood: 4), context: context, source: .siri)
        let log = try #require(try context.fetch(FetchDescriptor<DailyLog>()).first)
        log.mood = 1                       // the person changed it themselves
        try context.save()
        #expect(QuickLogUndo.availableRecord(in: context) == nil)
    }

    @Test("A record from another day is never offered")
    func staleDay_isNotOffered() throws {
        QuickLogUndo.clear()
        let context = try makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        QuickLogUndo.store(QuickLogUndoRecord(day: yesterday, source: .siri, createdLog: true,
                                              previousMood: 3, previousDidEditMood: false,
                                              previousEnergy: 5, previousDidEditMetrics: false,
                                              appliedMood: 4, appliedEnergy: nil, recordedAt: yesterday))
        #expect(QuickLogUndo.availableRecord(in: context) == nil)
    }
}

// MARK: - Streak breadth

// The Dashboard's @Query is capped at 90 days, and computeStreak walks
// consecutive days backward until a gap, so reading the streak off that slice
// silently truncated it at the window edge. Every other publish path fetches
// the unbounded table, so the Dashboard and the widget disagreed about a long
// streak and each republish undid the other's stored summary.
@MainActor
@Suite("DashboardViewModel – streak breadth")
struct StreakBreadthTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self, HealthSnapshot.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    // 120 consecutive complete days — comfortably past the 90-day window, so a
    // window-limited walk would stop at 90 and this would fail at exactly that
    // boundary rather than by some arbitrary amount.
    @Test("A streak longer than the Dashboard's 90-day window is not truncated")
    func streakSurvivesPastTheQueryWindow() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        for daysAgo in 0..<120 {
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let log = DailyLog(date: date)
            log.isComplete = true
            context.insert(log)
        }
        try context.save()

        #expect(DashboardViewModel.computeStreak(in: context) == 120)
    }

    // The walk must still stop at a real gap — otherwise the fix above would
    // "pass" by counting every complete log regardless of adjacency.
    @Test("The streak still stops at the first missing day")
    func streakStopsAtAGap() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        // Days 0-2 complete, day 3 missing, days 4-100 complete.
        for daysAgo in Array(0...2) + Array(4...100) {
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let log = DailyLog(date: date)
            log.isComplete = true
            context.insert(log)
        }
        try context.save()

        #expect(DashboardViewModel.computeStreak(in: context) == 3)
    }

    // The actual regression. The three tests above exercise computeStreak(in:)
    // directly, which is new code — none of them could have failed before this
    // fix, because the function didn't exist. THIS one pins the bug: refresh
    // receives the view's 90-day slice as `logs`, exactly as DashboardView
    // passes it, and the streak it publishes must still be the true one. Swap
    // `computeStreak(in: context)` back to `computeStreak(from: logs)` in
    // refresh and this returns 90.
    @Test("refresh reports the true streak even though its logs are a 90-day slice")
    func refreshIgnoresTheWindowForStreak() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        var all: [DailyLog] = []
        for daysAgo in 0..<120 {
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let log = DailyLog(date: date)
            log.isComplete = true
            context.insert(log)
            all.append(log)
        }
        try context.save()

        // What DashboardView's @Query would hand over: the newest 90 days only.
        let windowed = Array(all.prefix(90))
        let vm = DashboardViewModel()
        vm.refresh(logs: windowed, health: [], reviews: [],
                   notifications: StreakFakeNotificationService(), context: context)

        #expect(vm.streak == 120)
    }

    // The probe/fallback boundary, and the whole reason the probe is not a cap.
    // computeStreak(in:) fetches only the last StreakThreshold.probeDays first;
    // a streak that fills that window must fall through to the unbounded fetch
    // and still report the exact number. If the fallback were dropped this
    // returns probeDays + 1 (401) instead of 450 — the same class of silent
    // truncation the 90-day @Query caused, just further out.
    @Test("A streak longer than the probe window falls back and stays exact")
    func streakBeyondProbeWindowIsExact() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        let length = StreakThreshold.probeDays + 50
        for daysAgo in 0..<length {
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let log = DailyLog(date: date)
            log.isComplete = true
            context.insert(log)
        }
        try context.save()

        #expect(DashboardViewModel.computeStreak(in: context) == length)
    }

    // The mirror image: a gap just inside the probe window must be found by the
    // probe alone. Together with the test above this pins both sides of the
    // boundary — one proves the fallback fires when needed, this proves the
    // probe is trusted when it shouldn't.
    @Test("A gap inside the probe window is answered without the fallback")
    func gapInsideProbeWindow() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        // Complete right up to one day short of the probe edge, then a gap,
        // then a long older run that must not be counted.
        let runLength = StreakThreshold.probeDays - 1
        for daysAgo in Array(0..<runLength) + Array((runLength + 1)..<(runLength + 200)) {
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let log = DailyLog(date: date)
            log.isComplete = true
            context.insert(log)
        }
        try context.save()

        #expect(DashboardViewModel.computeStreak(in: context) == runLength)
    }

    // Incomplete days are not streak days, and the predicate must be what
    // filters them — not the walk finding them out of order.
    @Test("Incomplete days don't count toward the streak")
    func incompleteDaysExcluded() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        for daysAgo in 0..<5 {
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let log = DailyLog(date: date)
            log.isComplete = (daysAgo != 2)
            context.insert(log)
        }
        try context.save()

        #expect(DashboardViewModel.computeStreak(in: context) == 2)
    }
}

/// Keeps refresh's streak-risk scheduling out of the real notification centre
/// during the streak-breadth tests.
@MainActor
private final class StreakFakeNotificationService: NotificationServiceProtocol {
    func requestAuthorization() async -> Bool { true }
    func checkAuthorizationStatus() async -> Bool { true }
    func scheduleDailyReminder(at hour: Int, minute: Int) {}
    func scheduleWeeklyReviewReminder(weekday: Int, hour: Int) {}
    func scheduleStreakAtRisk() {}
    func sendInsightNotification(title: String) {}
    func syncMedicationReminders(_ medications: [MedicationSnapshot]) async {}
    func removeNotification(id: String) {}
    func removeAll() {}
}
