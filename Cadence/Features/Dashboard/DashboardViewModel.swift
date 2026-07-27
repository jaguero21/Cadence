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
    var mascotPose: WidgetData.MascotPose = .welcoming

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
        let activeFlare = flares.first(where: \.isActive)
        mascotPose = Self.resolvePose(logs: logs, activeFlare: activeFlare, streakDays: streak)

        if streak > 0 && todayLog?.isComplete != true {
            notifications.scheduleStreakAtRisk()
        } else {
            notifications.removeNotification(id: NotificationID.streakRisk)
        }

        // Hand the already-computed streak/pose through so publishWidgetSummary
        // doesn't recompute them (and re-map logs to snapshots) from scratch.
        Self.publishWidgetSummary(logs: logs, activeFlare: activeFlare, streak: streak, mascotPose: mascotPose)
    }

    // Shared by refresh (for the Dashboard's own mascotPose) and
    // publishWidgetSummary (for the widget's copy) so the two can never
    // disagree about how the active flare or streak feeds into the pose. The
    // log breadth still differs by caller — refresh passes the Dashboard's
    // 90-day @Query slice, the other publish paths pass the unbounded
    // DailyLog table — but MascotPoseEngine.pose windows its input to
    // PatternThreshold.insightWindowDays internally, so both converge to the
    // identical set and produce the identical pose.
    private static func resolvePose(logs: [DailyLog], activeFlare: Flare?, streakDays: Int) -> WidgetData.MascotPose {
        MascotPoseEngine.pose(
            for: logs.map(DailyLogSnapshot.init),
            activeFlare: activeFlare.map(FlareSnapshot.init),
            streakDays: streakDays
        )
    }

    // The single active flare (endDate == nil), fetched predicate-scoped so
    // the store returns just the 0–1 ongoing rows rather than materializing
    // the whole flare history. For the save/quick-log paths that publish a
    // widget summary without a Flare @Query already in scope; the predicate
    // inlines Flare.isActive's rule (a #Predicate can't call the computed
    // property).
    static func activeFlare(in context: ModelContext) -> Flare? {
        var descriptor = FetchDescriptor<Flare>(predicate: #Predicate { $0.endDate == nil })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // Single publish point for the home-screen widget, callable from any save
    // path (dashboard refresh, watch quick-log, log flow). Skips the write AND
    // the timeline reload when nothing changed — reloads are system-budgeted,
    // and burning the budget on no-op refreshes leaves real changes stranded.
    //
    // `activeFlare` is required, not defaulted: a caller that published
    // without it would silently overwrite an active flare's stored `.cozy`
    // pose with whatever `.soaking`/`.resting`/`.welcoming` the flare-blind
    // computation produces instead — not a staleness lag, an active
    // downgrade, since `pose` is recomputed from scratch each call and the
    // `summary != WidgetData.read()` guard republishes any different value it
    // gets. Save paths pass `activeFlare(in:)`; the Dashboard passes its
    // @Query's active flare.
    //
    // `streak`/`mascotPose` let a caller (refresh) that already computed them
    // for its own UI hand them in, skipping a duplicate computeStreak +
    // resolvePose (each of which re-maps every log to a snapshot) on the same
    // inputs. Unlike `activeFlare`, omitting them is only slower, never wrong
    // — they're derived from the same `logs`/`activeFlare` — so they default
    // to nil for the save paths, which have nothing precomputed.
    static func publishWidgetSummary(
        logs: [DailyLog],
        activeFlare: Flare?,
        streak: Int? = nil,
        mascotPose: WidgetData.MascotPose? = nil
    ) {
        let streak = streak ?? computeStreak(from: logs)
        let pose = mascotPose ?? resolvePose(logs: logs, activeFlare: activeFlare, streakDays: streak)
        let summary = WidgetData.Summary(
            date: Calendar.current.startOfDay(for: .now),
            loggedToday: logs.first { Calendar.current.isDateInToday($0.date) }?.isComplete == true,
            streak: streak,
            mascotPose: pose
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
