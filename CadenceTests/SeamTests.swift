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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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

    @Test("A payload without a mood is rejected and persists nothing")
    func missingMood_isNoOp() throws {
        let context = try makeContext()
        let saved = PhoneConnectivityManager.applyQuickLog(payload(mood: nil), context: context)
        #expect(saved == false)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.isEmpty)
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
