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
        let stored = WidgetData.Summary(date: day(0, from: now), loggedToday: true, streak: 7)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved == stored)
    }

    // Regression for the review finding: after midnight the widget must not
    // keep showing yesterday's "Logged today" — but yesterday's streak is
    // still alive until tonight.
    @Test("Yesterday's summary drops loggedToday but keeps the streak")
    func yesterdaySummary_dropsLoggedTodayKeepsStreak() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-1, from: now), loggedToday: true, streak: 7)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.loggedToday == false)
        #expect(resolved.streak == 7)
    }

    @Test("A summary older than yesterday resets the streak to zero")
    func olderSummary_breaksStreak() {
        let now = Date.now
        let stored = WidgetData.Summary(date: day(-3, from: now), loggedToday: true, streak: 7)
        let resolved = WidgetData.resolved(stored, now: now)
        #expect(resolved.loggedToday == false)
        #expect(resolved.streak == 0)
    }
}
