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
}
