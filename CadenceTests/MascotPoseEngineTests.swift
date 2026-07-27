import Testing
import Foundation
@testable import Cadence

// Local helper — PatternEngineTests.swift's makeSnapshot is `private` to
// that file and can't be reused across files.
private func makeLog(daysAgo: Int, mood: Int = 3) -> DailyLogSnapshot {
    DailyLogSnapshot(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, mood: mood)
}

@Suite("MascotPoseEngine – pose")
struct MascotPoseEngineTests {

    @Test("No logs at all returns welcoming")
    func pose_noLogs_isWelcoming() {
        let pose = MascotPoseEngine.pose(for: [], activeFlare: nil, streakDays: 0)
        #expect(pose == .welcoming)
    }

    @Test("Has history, nothing else triggered, returns resting")
    func pose_hasHistory_defaultsToResting() {
        let logs = [makeLog(daysAgo: 0), makeLog(daysAgo: 1)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 2)
        #expect(pose == .resting)
    }

    @Test("Streak at or above the soaking threshold returns soaking")
    func pose_streakAtThreshold_isSoaking() {
        let logs = [makeLog(daysAgo: 0)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: MascotThreshold.streakDaysForSoaking)
        #expect(pose == .soaking)
    }

    @Test("Streak just below the soaking threshold does not trigger soaking")
    func pose_streakBelowThreshold_isNotSoaking() {
        let logs = [makeLog(daysAgo: 0)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: MascotThreshold.streakDaysForSoaking - 1)
        #expect(pose != .soaking)
    }

    @Test("An active flare returns cozy even with a qualifying streak")
    func pose_activeFlare_isCozy_outranksSoaking() {
        let logs = [makeLog(daysAgo: 0)]
        let flare = FlareSnapshot(startDate: Date(), endDate: nil)
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: flare, streakDays: 30)
        #expect(pose == .cozy)
    }

    @Test("An ended flare does not trigger cozy")
    func pose_endedFlare_doesNotTriggerCozy() {
        let logs = [makeLog(daysAgo: 0)]
        let flare = FlareSnapshot(startDate: Date(), endDate: Date())
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: flare, streakDays: 0)
        #expect(pose != .cozy)
    }

    @Test("Three consecutive days below the overall average mood returns cozy")
    func pose_lowMoodTrend_isCozy() {
        // Two good days establish a higher average, then three low days in a row.
        let logs = [
            makeLog(daysAgo: 4, mood: 5),
            makeLog(daysAgo: 3, mood: 5),
            makeLog(daysAgo: 2, mood: 1),
            makeLog(daysAgo: 1, mood: 1),
            makeLog(daysAgo: 0, mood: 1),
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose == .cozy)
    }

    @Test("Fewer than lowMoodTrendDays logs never trigger the mood-trend cozy path")
    func pose_tooFewLogs_doesNotTriggerMoodTrend() {
        let logs = [makeLog(daysAgo: 1, mood: 1), makeLog(daysAgo: 0, mood: 1)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose != .cozy)
    }

    @Test("Exactly lowMoodTrendDays logs with no older baseline never trigger cozy, regardless of mood")
    func pose_exactlyThresholdLogs_noBaseline_doesNotTriggerMoodTrend() {
        let logs = [makeLog(daysAgo: 2, mood: 1), makeLog(daysAgo: 1, mood: 1), makeLog(daysAgo: 0, mood: 1)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose != .cozy)
    }

    @Test("A single low day among otherwise-average recent days does not trigger cozy")
    func pose_singleLowDay_doesNotTriggerMoodTrend() {
        let logs = [
            makeLog(daysAgo: 3, mood: 3),  // baseline
            makeLog(daysAgo: 2, mood: 3),
            makeLog(daysAgo: 1, mood: 3),
            makeLog(daysAgo: 0, mood: 1),  // the one low day
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose != .cozy)
    }

    // Logs older than the insight window don't count toward "has history",
    // so a user whose only logs predate the window reads as welcoming — the
    // same condition the Dashboard's empty state gates on (its 90-day
    // @Query is empty), keeping the widget and Dashboard consistent.
    @Test("Logs older than the insight window are ignored, returning welcoming")
    func pose_logsOlderThanWindow_isWelcoming() {
        let logs = [
            makeLog(daysAgo: PatternThreshold.insightWindowDays + 10, mood: 3),
            makeLog(daysAgo: PatternThreshold.insightWindowDays + 5, mood: 3),
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 2)
        #expect(pose == .welcoming)
    }

    // Regression for the cross-surface disagreement finding: the pose must
    // not change based on how much OLDER-than-window history a caller
    // happens to pass. The Dashboard passes its 90-day @Query slice; the
    // widget-publish paths pass the unbounded table. Feeding the same
    // recent window plus a pile of out-of-window history must yield the
    // identical pose, or the two surfaces disagree for the same day.
    @Test("Out-of-window history does not change the pose (surfaces can't disagree)")
    func pose_windowInvariant_ignoresOutOfWindowHistory() {
        // In-window recent stretch: two good days then three low days — cozy.
        let recentWindow = [
            makeLog(daysAgo: 4, mood: 5),
            makeLog(daysAgo: 3, mood: 5),
            makeLog(daysAgo: 2, mood: 1),
            makeLog(daysAgo: 1, mood: 1),
            makeLog(daysAgo: 0, mood: 1),
        ]
        // What an unbounded caller additionally carries: a long stretch of
        // high-mood days from well before the window, which — if they leaked
        // into the baseline — would drag the average up and could flip the
        // verdict.
        let outOfWindowHistory = (0..<40).map {
            makeLog(daysAgo: PatternThreshold.insightWindowDays + 1 + $0, mood: 5)
        }

        let dashboardPose = MascotPoseEngine.pose(for: recentWindow, activeFlare: nil, streakDays: 0)
        let widgetPose = MascotPoseEngine.pose(for: recentWindow + outOfWindowHistory, activeFlare: nil, streakDays: 0)

        #expect(dashboardPose == .cozy)
        #expect(widgetPose == dashboardPose)
    }

    // A CloudKit merge can leave two DailyLogs for the same calendar day.
    // Two low records for today plus one for yesterday is only 2 distinct
    // low days — it must NOT satisfy the 3-distinct-day low-mood trend the
    // way it would if same-day duplicates each counted as their own day.
    @Test("A duplicated day does not fabricate a three-day low-mood trend")
    func pose_duplicateSameDay_doesNotFabricateMoodTrend() {
        let logs = [
            makeLog(daysAgo: 3, mood: 5),
            makeLog(daysAgo: 2, mood: 5),
            makeLog(daysAgo: 1, mood: 1),
            makeLog(daysAgo: 0, mood: 1),
            makeLog(daysAgo: 0, mood: 1),  // duplicate of today (CloudKit merge)
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose != .cozy)
    }

    // The mirror case: three genuinely distinct low days below a higher
    // baseline still trigger cozy even when one of those days carries a
    // duplicate record, so dedup doesn't suppress a real trend.
    @Test("A real three-day low trend survives a duplicate record on one day")
    func pose_duplicateOnRealTrend_stillCozy() {
        let logs = [
            makeLog(daysAgo: 4, mood: 5),
            makeLog(daysAgo: 3, mood: 5),
            makeLog(daysAgo: 2, mood: 1),
            makeLog(daysAgo: 2, mood: 1),  // duplicate of a genuinely-low day
            makeLog(daysAgo: 1, mood: 1),
            makeLog(daysAgo: 0, mood: 1),
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose == .cozy)
    }
}
