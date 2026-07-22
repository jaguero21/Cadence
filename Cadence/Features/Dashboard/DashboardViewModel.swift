import SwiftUI
import SwiftData
import WidgetKit

@MainActor
@Observable
final class DashboardViewModel {
    var todayLog: DailyLog?
    var thisWeekReview: WeeklyReview?
    var streak: Int = 0
    var latestInsight: InsightCard?

    func refresh(logs: [DailyLog], reviews: [WeeklyReview], medications: [Medication] = [], flares: [Flare] = [], customTrackers: [CustomTracker] = [], notifications: (any NotificationServiceProtocol)? = nil) {
        let notifications = notifications ?? NotificationService.shared
        todayLog = logs.first { Calendar.current.isDateInToday($0.date) }
        thisWeekReview = reviews.first { $0.weekStartDate.isThisWeek }
        streak = Self.computeStreak(from: logs)
        // Snapshot @Model values on the main actor before handing them to
        // PatternEngine. Every input PatternEngine takes is included so the
        // dashboard headline agrees with the Insights tab / notifications
        // about the top pattern (all three run off the same input set).
        latestInsight = PatternEngine.allInsights(
            from: logs.map(DailyLogSnapshot.init),
            medications: medications.map(MedicationSnapshot.init),
            flares: flares.map(FlareSnapshot.init),
            trackers: customTrackers.map(CustomTrackerSnapshot.init)
        ).first

        if streak > 0 && todayLog?.isComplete != true {
            notifications.scheduleStreakAtRisk()
        } else {
            notifications.removeNotification(id: NotificationID.streakRisk)
        }

        Self.publishWidgetSummary(logs: logs, flares: flares)
    }

    // Single publish point for the home-screen widget, callable from any save
    // path (dashboard refresh, watch quick-log, log flow). Skips the write AND
    // the timeline reload when nothing changed — reloads are system-budgeted,
    // and burning the budget on no-op refreshes leaves real changes stranded.
    //
    // `flares` defaults to `[]`: only `refresh` (the Dashboard's own full
    // refresh path) has flare data in scope for free. The other callers —
    // CadenceApp's foreground sweep, LogInputFlow's save, the watch/Siri
    // quick-log paths, and SyncBackupSection's restore — are narrow,
    // single-purpose paths; adding a Flare fetch to each just for the
    // mascot would be disproportionate for a decorative feature. They
    // publish with a flare-blind pose, which self-corrects on the next full
    // Dashboard refresh — the same brief-staleness tradeoff the widget
    // already accepts elsewhere (its interim "mood saved" state).
    static func publishWidgetSummary(logs: [DailyLog], flares: [Flare] = []) {
        let streak = computeStreak(from: logs)
        let activeFlare = flares.first { $0.endDate == nil }
        let summary = WidgetData.Summary(
            date: Calendar.current.startOfDay(for: .now),
            loggedToday: logs.first { Calendar.current.isDateInToday($0.date) }?.isComplete == true,
            streak: streak,
            mascotPose: MascotPoseEngine.pose(
                for: logs.map(DailyLogSnapshot.init),
                activeFlare: activeFlare.map(FlareSnapshot.init),
                streakDays: streak
            )
        )
        guard summary != WidgetData.read() else { return }
        WidgetData.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func computeStreak(from logs: [DailyLog]) -> Int {
        // Dedup to unique days first — CloudKit sync can leave two complete
        // logs for the same day (no @Attribute(.unique) on DailyLog), and a
        // second entry for a day already counted would otherwise mismatch the
        // decremented `check` and cut the streak short.
        let sorted = Set(logs.filter(\.isComplete).map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >)
        var streak = 0
        let todayComplete = logs.contains { Calendar.current.isDateInToday($0.date) && $0.isComplete }
        var check: Date
        if todayComplete {
            check = Calendar.current.startOfDay(for: .now)
        } else {
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) else { return 0 }
            check = Calendar.current.startOfDay(for: yesterday)
        }
        for day in sorted {
            if day == check {
                streak += 1
                guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: check) else { break }
                check = prev
            } else {
                break
            }
        }
        return streak
    }
}
