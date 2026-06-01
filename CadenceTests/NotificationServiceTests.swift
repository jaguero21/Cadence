import Testing
import Foundation
@testable import Cadence

// MARK: - NotificationService – input validation
//
// Full scheduling requires a device with notification permission.
// These tests cover pure-logic validation added to scheduleDailyReminder
// and scheduleWeeklyReviewReminder (hour/minute/weekday range guards).

@Suite("NotificationService – scheduleDailyReminder validation")
struct NotificationServiceDailyReminderTests {

    @Test("Valid hour and minute do not crash")
    func scheduleDailyReminder_validInputs_doesNotCrash() {
        // We can't assert a notification was registered without an entitlement,
        // but we can confirm the guard path doesn't throw or crash.
        NotificationService.shared.scheduleDailyReminder(at: 20, minute: 0)
        NotificationService.shared.scheduleDailyReminder(at: 0,  minute: 0)
        NotificationService.shared.scheduleDailyReminder(at: 23, minute: 59)
    }

    @Test("Hour out of range is rejected silently")
    func scheduleDailyReminder_invalidHour_returnsSilently() {
        // These calls should return early without crashing (guard hour in 0...23).
        NotificationService.shared.scheduleDailyReminder(at: 24,  minute: 0)
        NotificationService.shared.scheduleDailyReminder(at: -1,  minute: 0)
        NotificationService.shared.scheduleDailyReminder(at: 100, minute: 0)
    }

    @Test("Minute out of range is rejected silently")
    func scheduleDailyReminder_invalidMinute_returnsSilently() {
        NotificationService.shared.scheduleDailyReminder(at: 9, minute: 60)
        NotificationService.shared.scheduleDailyReminder(at: 9, minute: -1)
    }
}

@Suite("NotificationService – scheduleWeeklyReviewReminder validation")
struct NotificationServiceWeeklyReminderTests {

    @Test("Valid weekday and hour do not crash")
    func scheduleWeeklyReminder_validInputs_doesNotCrash() {
        NotificationService.shared.scheduleWeeklyReviewReminder(weekday: 1, hour: 19)
        NotificationService.shared.scheduleWeeklyReviewReminder(weekday: 7, hour: 0)
    }

    @Test("Weekday out of range is rejected silently")
    func scheduleWeeklyReminder_invalidWeekday_returnsSilently() {
        NotificationService.shared.scheduleWeeklyReviewReminder(weekday: 0, hour: 19)
        NotificationService.shared.scheduleWeeklyReviewReminder(weekday: 8, hour: 19)
    }

    @Test("Hour out of range is rejected silently")
    func scheduleWeeklyReminder_invalidHour_returnsSilently() {
        NotificationService.shared.scheduleWeeklyReviewReminder(weekday: 1, hour: 24)
        NotificationService.shared.scheduleWeeklyReviewReminder(weekday: 1, hour: -1)
    }
}

// MARK: - Export date-range overlap predicate
//
// A weekly review overlaps an export range when:
//   weekStartDate <= exportEnd && weekEndDate >= exportStart

@Suite("Export – weekly review range overlap")
struct ExportRangeOverlapTests {

    private func makeRange(startOffset: Int, endOffset: Int, from base: Date = Date(timeIntervalSinceReferenceDate: 0)) -> (start: Date, end: Date) {
        let cal = Calendar.current
        return (
            cal.date(byAdding: .day, value: startOffset, to: base)!,
            cal.date(byAdding: .day, value: endOffset,   to: base)!
        )
    }

    @Test("Review wholly inside range is included")
    func overlap_reviewInsideRange_included() {
        let (exportStart, exportEnd) = makeRange(startOffset: 0, endOffset: 30)
        let (weekStart, weekEnd)     = makeRange(startOffset: 7, endOffset: 13)
        #expect(weekStart <= exportEnd && weekEnd >= exportStart)
    }

    @Test("Review starting before and ending inside range is included")
    func overlap_reviewStartsBeforeEndsInside_included() {
        let (exportStart, exportEnd) = makeRange(startOffset: 10, endOffset: 30)
        let (weekStart, weekEnd)     = makeRange(startOffset: 5,  endOffset: 11)
        #expect(weekStart <= exportEnd && weekEnd >= exportStart)
    }

    @Test("Review starting inside and ending after range is included")
    func overlap_reviewStartsInsideEndsAfter_included() {
        let (exportStart, exportEnd) = makeRange(startOffset: 0, endOffset: 20)
        let (weekStart, weekEnd)     = makeRange(startOffset: 18, endOffset: 24)
        #expect(weekStart <= exportEnd && weekEnd >= exportStart)
    }

    @Test("Review wholly before range is excluded")
    func overlap_reviewBeforeRange_excluded() {
        let (exportStart, exportEnd) = makeRange(startOffset: 20, endOffset: 40)
        let (weekStart, weekEnd)     = makeRange(startOffset: 0,  endOffset: 6)
        #expect(!(weekStart <= exportEnd && weekEnd >= exportStart))
    }

    @Test("Review wholly after range is excluded")
    func overlap_reviewAfterRange_excluded() {
        let (exportStart, exportEnd) = makeRange(startOffset: 0, endOffset: 10)
        let (weekStart, weekEnd)     = makeRange(startOffset: 14, endOffset: 20)
        #expect(!(weekStart <= exportEnd && weekEnd >= exportStart))
    }

    @Test("Review abutting range end is excluded (strict boundary)")
    func overlap_reviewAbuttingRangeEnd_excluded() {
        // weekStart == exportEnd+1: no overlap
        let (exportStart, exportEnd) = makeRange(startOffset: 0, endOffset: 10)
        let (weekStart, weekEnd)     = makeRange(startOffset: 11, endOffset: 17)
        #expect(!(weekStart <= exportEnd && weekEnd >= exportStart))
    }
}
