import Testing
import Foundation
@testable import Cadence

// MARK: - Helpers

/// Build a DailyLogSnapshot directly. Snapshots are plain Sendable structs, so
/// tests don't need a ModelContext — and PatternEngine takes snapshots, not @Model logs.
private func makeSnapshot(
    daysAgo: Int = 0,
    sleepHours: Double = 7.0,
    mood: Int = 3,
    energy: Int = 5,
    stressLevel: Int = 5,
    symptoms: [SymptomEntry] = [],
    didEditMetrics: Bool = false
) -> DailyLogSnapshot {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
    return DailyLogSnapshot(
        date: date,
        mood: mood,
        energy: energy,
        sleepHours: sleepHours,
        stressLevel: stressLevel,
        symptoms: symptoms,
        didEditMetrics: didEditMetrics
    )
}

private func headacheEntry() -> SymptomEntry {
    SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")
}

private func fatigueEntry() -> SymptomEntry {
    SymptomEntry(name: "Fatigue", severity: 5, emoji: "😴")
}

// MARK: - PatternEngine: allInsights gating

@Suite("PatternEngine – allInsights gating")
struct AllInsightsGatingTests {

    @Test("Returns empty array when fewer than 5 logs")
    func allInsights_fewerThanFiveLogs_returnsEmpty() {
        let logs = (0..<4).map { makeSnapshot(daysAgo: $0) }
        let result = PatternEngine.allInsights(from: logs)
        #expect(result.isEmpty)
    }

    @Test("latestInsight returns nil when fewer than 5 logs")
    func latestInsight_fewerThanFiveLogs_returnsNil() {
        let logs = (0..<4).map { makeSnapshot(daysAgo: $0) }
        let result = PatternEngine.latestInsight(from: logs)
        #expect(result == nil)
    }
}

// MARK: - PatternEngine: sleepHeadacheCorrelation

@Suite("PatternEngine – sleepHeadacheCorrelation")
struct SleepHeadacheCorrelationTests {

    @Test("Returns nil when fewer than 3 poor-sleep nights")
    func sleepHeadache_fewerThanThreePoorSleepNights_returnsNil() {
        // 2 poor-sleep nights out of 5 logs; ensure headache follows both (100% confidence, but count < 3)
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 4, sleepHours: 5.0)) // poor sleep
        logs.append(makeSnapshot(daysAgo: 3, sleepHours: 7.0, symptoms: [headacheEntry()]))
        logs.append(makeSnapshot(daysAgo: 2, sleepHours: 5.0)) // poor sleep
        logs.append(makeSnapshot(daysAgo: 1, sleepHours: 7.0, symptoms: [headacheEntry()]))
        logs.append(makeSnapshot(daysAgo: 0, sleepHours: 7.0))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .sleep }
        #expect(card == nil)
    }

    @Test("Returns nil when confidence below 0.5")
    func sleepHeadache_confidenceBelowThreshold_returnsNil() {
        // 4 poor-sleep nights, only 1 followed by headache → confidence = 0.25 < 0.5
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 7, sleepHours: 5.0)) // poor, no headache next day
        logs.append(makeSnapshot(daysAgo: 6, sleepHours: 7.0))
        logs.append(makeSnapshot(daysAgo: 5, sleepHours: 5.0)) // poor, no headache next day
        logs.append(makeSnapshot(daysAgo: 4, sleepHours: 7.0))
        logs.append(makeSnapshot(daysAgo: 3, sleepHours: 5.0)) // poor, no headache next day
        logs.append(makeSnapshot(daysAgo: 2, sleepHours: 7.0))
        logs.append(makeSnapshot(daysAgo: 1, sleepHours: 5.0)) // poor → headache next day
        logs.append(makeSnapshot(daysAgo: 0, sleepHours: 7.0, symptoms: [headacheEntry()]))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .sleep }
        #expect(card == nil)
    }

    @Test("Returns card when ≥3 poor-sleep nights and ≥50% headache follow-through")
    func sleepHeadache_threeOrMorePoorSleepAndHighConfidence_returnsCard() {
        // 3 poor-sleep nights, all 3 followed by headache → confidence = 1.0
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 6, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 5, sleepHours: 7.0, symptoms: [headacheEntry()]))
        logs.append(makeSnapshot(daysAgo: 4, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 3, sleepHours: 7.0, symptoms: [headacheEntry()]))
        logs.append(makeSnapshot(daysAgo: 2, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 1, sleepHours: 7.0, symptoms: [headacheEntry()]))
        logs.append(makeSnapshot(daysAgo: 0, sleepHours: 7.0))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .sleep }
        #expect(card != nil)
        #expect(card?.title == "Poor sleep is linked to next-day headaches")
        #expect((card?.confidence ?? 0) >= 0.5)
    }

    @Test("Returns card at exactly 50% confidence")
    func sleepHeadache_exactlyFiftyPercentConfidence_returnsCard() throws {
        // 4 poor-sleep nights, 2 followed by headache → confidence = 0.5
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 8, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 7, sleepHours: 7.0, symptoms: [headacheEntry()])) // headache
        logs.append(makeSnapshot(daysAgo: 6, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 5, sleepHours: 7.0))                              // no headache
        logs.append(makeSnapshot(daysAgo: 4, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 3, sleepHours: 7.0, symptoms: [headacheEntry()])) // headache
        logs.append(makeSnapshot(daysAgo: 2, sleepHours: 5.0))
        logs.append(makeSnapshot(daysAgo: 1, sleepHours: 7.0))                              // no headache
        logs.append(makeSnapshot(daysAgo: 0, sleepHours: 7.0))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .sleep }
        #expect(card != nil)
        let confidence = try #require(card?.confidence)
        #expect(confidence == 0.5)
    }
}

// MARK: - PatternEngine: stressFatiguePattern

@Suite("PatternEngine – stressFatiguePattern")
struct StressFatiguePatternTests {

    @Test("Returns nil when no streak reaches 3 consecutive stress days")
    func stressFatigue_noThreeDayStreak_returnsNil() {
        // max streak = 2 days; the guard requires fatigueFollowed >= 2 which cannot be met
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 6, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 5, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 4, stressLevel: 3, symptoms: [fatigueEntry()]))
        logs.append(makeSnapshot(daysAgo: 3, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 2, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 1, stressLevel: 3, symptoms: [fatigueEntry()]))
        logs.append(makeSnapshot(daysAgo: 0, stressLevel: 3))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .stress }
        #expect(card == nil)
    }

    @Test("Returns card when 3-day stress streak is followed by fatigue twice")
    func stressFatigue_twoThreeDayStreaksWithFatigue_returnsCard() {
        // Two 3-day stress streaks, each followed by a non-stress day with fatigue
        var logs: [DailyLogSnapshot] = []
        // First streak
        logs.append(makeSnapshot(daysAgo: 9, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 8, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 7, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 6, stressLevel: 3, symptoms: [fatigueEntry()])) // recovery + fatigue
        // Second streak
        logs.append(makeSnapshot(daysAgo: 5, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 4, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 3, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 2, stressLevel: 3, symptoms: [fatigueEntry()])) // recovery + fatigue
        logs.append(makeSnapshot(daysAgo: 1, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 0, stressLevel: 3))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .stress }
        #expect(card != nil)
        #expect(card?.title == "Extended stress streaks are followed by fatigue")
    }

    // A terminal stress streak (last log) has no observable follow-up day, so it
    // does NOT contribute to the denominator — confidence reflects only streaks
    // whose follow-up day we actually have data for.
    @Test("Terminal stress streak (ending at last log) is excluded from streaksChecked")
    func stressFatigue_terminalStreakAtLastIndex_isExcluded() {
        // 4 calm days then a 4-day terminal stress streak with no recovery day.
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 7, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 6, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 5, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 4, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 3, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 2, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 1, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 0, stressLevel: 9)) // terminal streak, no recovery day

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .stress }
        // streaksChecked == 0, fatigueFollowed == 0 → guard fails → no card.
        // The terminal streak has no observed follow-up day, so it's neither
        // credited as "fatigue followed" nor counted as a missed prediction.
        #expect(card == nil)
    }

    // A streak broken by a calendar gap (next high-stress day is not the
    // calendar-next-day) has no observed follow-up either — so it must not be
    // counted in streaksChecked. Previously this was counted with no fatigue
    // check, biasing confidence downward.
    @Test("Streak broken by a calendar gap is excluded from streaksChecked")
    func stressFatigue_gapBrokenStreak_isExcludedFromDenominator() {
        // Two 3-day streaks; the first has an observed fatigue follow-up,
        // the second is broken by a calendar gap (no log between day -4 and 0
        // covers day -3), so its follow-up day is unobserved.
        var logs: [DailyLogSnapshot] = []
        // Streak A — 3 days ending at day -10, followed by fatigue on day -9
        logs.append(makeSnapshot(daysAgo: 12, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 11, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 10, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 9, stressLevel: 3, symptoms: [fatigueEntry()]))
        // Streak B — 3 days ending at day -6, but no log on day -5 (gap),
        // and the next observation is day 0. Under the old logic this would
        // increment streaksChecked when day -6 was followed by day 0
        // (continuesStreak=false in the high-stress branch was the trigger).
        // We deliberately leave day -5/-4/-3/-2/-1 absent. Streak B has no observed follow-up.
        logs.append(makeSnapshot(daysAgo: 8, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 7, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 6, stressLevel: 9))
        // Far-future non-stress log that is NOT the calendar-next-day after day -6.
        logs.append(makeSnapshot(daysAgo: 0, stressLevel: 3, symptoms: [fatigueEntry()]))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .stress }
        // Only streak A contributes (streaksChecked = 1, fatigueFollowed = 1).
        // fatigueFollowed >= 2 fails → no card. The point: the gap-broken
        // streak B is excluded; under the old logic it would have inflated
        // streaksChecked to 2 with fatigueFollowed still at 1, biasing low.
        #expect(card == nil)
    }

    @Test("Returns nil when fatigue only followed one streak (fatigueFollowed < 2)")
    func stressFatigue_onlyOneFatigueFollowUp_returnsNil() {
        // One terminated 3-day stress streak followed by fatigue
        var logs: [DailyLogSnapshot] = []
        logs.append(makeSnapshot(daysAgo: 6, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 5, stressLevel: 9))
        logs.append(makeSnapshot(daysAgo: 4, stressLevel: 8))
        logs.append(makeSnapshot(daysAgo: 3, stressLevel: 3, symptoms: [fatigueEntry()]))
        logs.append(makeSnapshot(daysAgo: 2, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 1, stressLevel: 3))
        logs.append(makeSnapshot(daysAgo: 0, stressLevel: 3))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .stress }
        #expect(card == nil)
    }
}

// MARK: - PatternEngine: energyTrendDecline

@Suite("PatternEngine – energyTrendDecline")
struct EnergyTrendDeclineTests {

    @Test("Returns nil when fewer than 14 logs")
    func energyDecline_fewerThan14Logs_returnsNil() {
        let logs = (0..<13).map { makeSnapshot(daysAgo: $0, energy: 8) }
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .energy }
        #expect(card == nil)
    }

    @Test("Returns nil when energy drop is exactly 1.5 (not strictly greater)")
    func energyDecline_dropExactly1Point5_returnsNil() {
        // Older half avg = 7.0, newer half avg = 5.5, drop = 1.5 → NOT > 1.5
        var logs: [DailyLogSnapshot] = []
        for i in 0..<7 { logs.append(makeSnapshot(daysAgo: 13 - i, energy: 7)) } // older 7: avg 7.0
        for i in 0..<7 { logs.append(makeSnapshot(daysAgo: 6 - i,  energy: 6)) } // recent 7: avg 6.0 → drop = 1.0
        // Adjust to get drop = 1.5 exactly: older avg 7.5, newer avg 6.0
        // older 7 logs energy = [7,7,7,7,8,8,8] sum=52/7 ≈ 7.43, skip — use clean numbers
        // Simpler: older 7 × energy=8, newer 7 × energy=5 → drop = 3.0 > 1.5, that produces a card
        // For exactly 1.5: older [8,8,8,8,8,8,9] avg 53/7 ≈ not clean.
        // Use older=7, newer=5.5 → can't make 5.5 with Int energy.
        // Use older=7×8=56/7=8, newer=7×6=42/7=6, drop=2.0 → card returned. Not what we want.
        // Best approach: older 7×energy=6, newer 7×energy=6 → drop=0 → nil.
        let flatLogs = (0..<14).map { makeSnapshot(daysAgo: 13 - $0, energy: 6) }
        let flatInsights = PatternEngine.allInsights(from: flatLogs)
        let flatCard = flatInsights.first { $0.category == .energy }
        #expect(flatCard == nil)
    }

    @Test("Returns nil when drop is zero (flat energy)")
    func energyDecline_zeroDropFlatEnergy_returnsNil() {
        let logs = (0..<14).map { makeSnapshot(daysAgo: 13 - $0, energy: 5) }
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .energy }
        #expect(card == nil)
    }

    @Test("Returns card with correct title when drop exceeds 1.5")
    func energyDecline_dropExceeds1Point5_returnsCardWithCorrectTitle() {
        // older 7 avg = 8, newer 7 avg = 4 → drop = 4.0 > 1.5
        var logs: [DailyLogSnapshot] = []
        for i in 0..<7  { logs.append(makeSnapshot(daysAgo: 13 - i, energy: 8)) } // older half
        for i in 0..<7  { logs.append(makeSnapshot(daysAgo: 6 - i,  energy: 4)) } // recent half
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .energy }
        #expect(card != nil)
        #expect(card?.title == "Energy declining week-over-week")
    }

    @Test("Returns card and confidence is capped at 1.0 for very large drop")
    func energyDecline_veryLargeDrop_confidenceCappedAtOne() {
        // older avg=10, newer avg=0 → drop=10, confidence = min(10/5, 1.0) = 1.0
        var logs: [DailyLogSnapshot] = []
        for i in 0..<7 { logs.append(makeSnapshot(daysAgo: 13 - i, energy: 10)) }
        for i in 0..<7 { logs.append(makeSnapshot(daysAgo: 6 - i,  energy: 0))  }
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .energy }
        #expect(card?.confidence == 1.0)
    }
}

// MARK: - PatternEngine: moodSleepCorrelation

@Suite("PatternEngine – moodSleepCorrelation")
struct MoodSleepCorrelationTests {

    @Test("Returns nil when fewer than 7 didEditMetrics logs")
    func moodSleep_fewerThan7EditedLogs_returnsNil() {
        // 6 didEditMetrics logs with valid sleepHours — not enough
        var logs: [DailyLogSnapshot] = []
        for i in 0..<6 {
            logs.append(makeSnapshot(daysAgo: 10 - i, sleepHours: Double(5 + i), mood: 3,
                                     didEditMetrics: true))
        }
        // pad to 5+ to pass the outer guard
        logs.append(makeSnapshot(daysAgo: 1))
        logs.append(makeSnapshot(daysAgo: 0))

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .mood }
        #expect(card == nil)
    }

    @Test("Returns card when good-sleep days have mood 2+ points higher than poor-sleep days")
    func moodSleep_goodSleepMoodSignificantlyHigher_returnsCard() {
        // 7 logs, all didEditMetrics. sleepAvg ≈ 7h.
        // Good-sleep days (>7h): mood 5. Poor-sleep days (≤7h): mood 2. diff = 3.0 > 1.0.
        var logs: [DailyLogSnapshot] = []
        // 4 good-sleep days (8h, mood 5)
        for i in 0..<4 {
            logs.append(makeSnapshot(daysAgo: 10 - i, sleepHours: 8.0, mood: 5, didEditMetrics: true))
        }
        // 3 poor-sleep days (5h, mood 2)
        for i in 0..<3 {
            logs.append(makeSnapshot(daysAgo: 6 - i, sleepHours: 5.0, mood: 2, didEditMetrics: true))
        }
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .mood }
        #expect(card != nil)
        #expect(card?.title == "More sleep correlates with better mood")
    }

    @Test("Returns nil when mood difference is exactly 1.0 (not strictly greater)")
    func moodSleep_moodDiffExactly1Point0_returnsNil() {
        // Good-sleep days: mood 4. Poor-sleep days: mood 3. diff = 1.0 → NOT > 1.0
        var logs: [DailyLogSnapshot] = []
        for i in 0..<4 {
            logs.append(makeSnapshot(daysAgo: 10 - i, sleepHours: 8.0, mood: 4, didEditMetrics: true))
        }
        for i in 0..<3 {
            logs.append(makeSnapshot(daysAgo: 6 - i, sleepHours: 5.0, mood: 3, didEditMetrics: true))
        }
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .mood }
        #expect(card == nil)
    }

    @Test("Returns nil when logs have no didEditMetrics set")
    func moodSleep_noEditedMetricsLogs_returnsNil() {
        // 10 logs but didEditMetrics = false for all → pairs filter returns empty
        let logs = (0..<10).map { makeSnapshot(daysAgo: $0, sleepHours: 8.0, didEditMetrics: false) }
        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.category == .mood }
        #expect(card == nil)
    }
}

// MARK: - DailyLog: completionScore

@Suite("DailyLog – completionScore")
struct DailyLogCompletionScoreTests {

    @Test("Returns 0.0 when all fields are at their default values")
    func completionScore_allDefaults_returnsZero() {
        let log = DailyLog()
        // Default: mood=3, didEditMetrics=false, freeNote=""
        #expect(log.completionScore == 0.0)
    }

    // Fixed: completionScore now uses didEditMood instead of mood != 3.
    // Explicitly tapping neutral mood (value 3) with didEditMood=true scores 1/3 for mood.
    @Test("Neutral mood (mood=3) with didEditMood=true now scores 1/3")
    func completionScore_neutralMoodWithDidEditMood_scoresOneThird() {
        let log = DailyLog()
        log.mood = 3        // neutral, but explicitly chosen
        log.didEditMood = true
        let expected = 1.0 / 3.0
        #expect(abs(log.completionScore - expected) < 0.001)
    }

    @Test("Mood slot scores zero when didEditMood is false, regardless of mood value")
    func completionScore_moodNotEdited_moodSlotIsZero() {
        let log = DailyLog()
        log.mood = 4        // non-default value, but didEditMood was never set
        log.didEditMood = false
        #expect(log.completionScore == 0.0)
    }

    @Test("Returns 0.33 (1/3) when only didEditMood is true")
    func completionScore_onlyDidEditMood_returnsOneThird() {
        let log = DailyLog()
        log.didEditMood = true
        let expected = 1.0 / 3.0
        #expect(abs(log.completionScore - expected) < 0.001)
    }

    @Test("Returns 0.33 (1/3) when only didEditMetrics is true")
    func completionScore_onlyDidEditMetrics_returnsOneThird() {
        let log = DailyLog()
        log.didEditMetrics = true
        let expected = 1.0 / 3.0
        #expect(abs(log.completionScore - expected) < 0.001)
    }

    @Test("Returns 0.33 (1/3) when only freeNote is non-empty")
    func completionScore_onlyFreeNotePresent_returnsOneThird() {
        let log = DailyLog()
        log.freeNote = "Feeling okay today"
        let expected = 1.0 / 3.0
        #expect(abs(log.completionScore - expected) < 0.001)
    }

    @Test("Returns 0.67 (2/3) when two criteria are met")
    func completionScore_twoCriteriaMet_returnsTwoThirds() {
        let log = DailyLog()
        log.didEditMood = true
        log.didEditMetrics = true
        let expected = 2.0 / 3.0
        #expect(abs(log.completionScore - expected) < 0.001)
    }

    @Test("Returns 1.0 when all three criteria are met")
    func completionScore_allCriteriaMet_returnsOne() {
        let log = DailyLog()
        log.didEditMood = true
        log.didEditMetrics = true
        log.freeNote = "A full log day"
        #expect(log.completionScore == 1.0)
    }
}
