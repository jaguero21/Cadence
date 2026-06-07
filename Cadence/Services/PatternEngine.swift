import SwiftUI

// Stateless pattern detector. Takes Sendable snapshots so it can be invoked
// from any isolation context — and won't race with SwiftData on @Model fields.
enum PatternEngine {

    static func latestInsight(from logs: [DailyLogSnapshot]) -> InsightCard? {
        allInsights(from: logs).first
    }

    static func allInsights(from logs: [DailyLogSnapshot]) -> [InsightCard] {
        guard logs.count >= PatternThreshold.minimumLogs else { return [] }
        let sorted = logs.sorted { $0.date < $1.date }
        var cards: [InsightCard] = []

        if let card = sleepHeadacheCorrelation(logs: sorted) { cards.append(card) }
        if let card = stressFatiguePattern(logs: sorted) { cards.append(card) }
        if let card = energyTrendDecline(logs: sorted) { cards.append(card) }
        if let card = moodSleepCorrelation(logs: sorted) { cards.append(card) }

        return cards
    }

    // MARK: - Pattern Detectors

    private static func isNextCalendarDay(_ date: Date, after previous: Date) -> Bool {
        let cal = Calendar.current
        guard let expectedNext = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: previous)) else {
            return false
        }
        return cal.isDate(date, inSameDayAs: expectedNext)
    }

    private static func sleepHeadacheCorrelation(logs: [DailyLogSnapshot]) -> InsightCard? {
        var poorSleepThenHeadache = 0
        var poorSleepTotal = 0

        for i in logs.indices.dropLast() {
            guard logs[i].sleepHours < PatternThreshold.poorSleepHours,
                  isNextCalendarDay(logs[i + 1].date, after: logs[i].date) else { continue }
            poorSleepTotal += 1
            if logs[i + 1].symptoms.contains(where: { $0.name.localizedCaseInsensitiveContains("headache") }) {
                poorSleepThenHeadache += 1
            }
        }

        guard poorSleepTotal >= PatternThreshold.minimumPoorSleepEvents else { return nil }
        let confidence = Double(poorSleepThenHeadache) / Double(poorSleepTotal)
        guard confidence >= PatternThreshold.minimumConfidence else { return nil }

        return InsightCard(
            title: "Poor sleep is linked to next-day headaches",
            detail: "On \(Int(confidence * 100))% of days after sleeping under \(Int(PatternThreshold.poorSleepHours)) hours, you logged a headache the next day.",
            icon: "moon.zzz.fill",
            color: CadenceColor.sleepPurple,
            confidence: confidence,
            category: .sleep
        )
    }

    private static func stressFatiguePattern(logs: [DailyLogSnapshot]) -> InsightCard? {
        var consecutiveStress = 0
        var streaksChecked = 0
        var fatigueFollowed = 0
        var lastHighStressDate: Date? = nil

        // Only count a streak in the denominator when we actually observe its
        // follow-up day in the log set. Streaks broken by a calendar gap, and
        // streaks ending at the last log, have no observed follow-up — counting
        // them would bias confidence (low under the previous implementation,
        // since fatigue could never increment without a follow-up day).
        for i in 0..<logs.count {
            if logs[i].stressLevel >= PatternThreshold.highStressLevel {
                let continuesStreak = lastHighStressDate.map {
                    isNextCalendarDay(logs[i].date, after: $0)
                } ?? false
                consecutiveStress = continuesStreak ? consecutiveStress + 1 : 1
                lastHighStressDate = logs[i].date
            } else {
                // The streak's true follow-up is the day immediately after it ended.
                // Only credit this log to the streak if it's that calendar-next-day.
                if consecutiveStress >= PatternThreshold.consecutiveStressDays,
                   let lastDate = lastHighStressDate,
                   isNextCalendarDay(logs[i].date, after: lastDate) {
                    streaksChecked += 1
                    if logs[i].symptoms.contains(where: { $0.name.localizedCaseInsensitiveContains("fatigue") || $0.name.localizedCaseInsensitiveContains("tired") }) {
                        fatigueFollowed += 1
                    }
                }
                consecutiveStress = 0
                lastHighStressDate = nil
            }
        }

        guard fatigueFollowed >= PatternThreshold.minimumStressFatigueEvents, streaksChecked > 0 else { return nil }
        let confidence = Double(fatigueFollowed) / Double(streaksChecked)
        return InsightCard(
            title: "Extended stress streaks are followed by fatigue",
            detail: "When you log high stress 3+ consecutive days, a fatigue spike tends to follow.",
            icon: "brain.head.profile",
            color: CadenceColor.stressRed,
            confidence: confidence,
            category: .stress
        )
    }

    private static func energyTrendDecline(logs: [DailyLogSnapshot]) -> InsightCard? {
        // logs is sorted ascending; take the most recent window, split into two halves
        let halfWindow = PatternThreshold.energyTrendWindow / 2
        let recent = logs.suffix(PatternThreshold.energyTrendWindow)
        guard recent.count == PatternThreshold.energyTrendWindow else { return nil }
        let firstHalf  = Array(recent.prefix(halfWindow)).map { Double($0.energy) }
        let secondHalf = Array(recent.suffix(halfWindow)).map { Double($0.energy) }
        let firstAvg = firstHalf.reduce(0,+) / Double(halfWindow)
        let secondAvg = secondHalf.reduce(0,+) / Double(halfWindow)
        let drop = firstAvg - secondAvg
        guard drop > PatternThreshold.energyDropThreshold else { return nil }
        let confidence = min(drop / PatternThreshold.confidenceScale, 1.0)
        return InsightCard(
            title: "Energy declining week-over-week",
            detail: "Your average energy dropped from \(String(format: "%.1f", firstAvg)) to \(String(format: "%.1f", secondAvg)) over the past two weeks.",
            icon: "arrow.down.circle.fill",
            color: CadenceColor.energyOrange,
            confidence: confidence,
            category: .energy
        )
    }

    private static func moodSleepCorrelation(logs: [DailyLogSnapshot]) -> InsightCard? {
        let pairs = logs.filter { $0.sleepHours > 0 && $0.didEditMetrics }
        guard pairs.count >= PatternThreshold.minimumMoodSleepPairs else { return nil }
        let sleepAvg = pairs.map(\.sleepHours).reduce(0,+) / Double(pairs.count)
        let goodSleepMood = pairs.filter { $0.sleepHours > sleepAvg }.map { Double($0.mood) }
        let poorSleepMood = pairs.filter { $0.sleepHours <= sleepAvg }.map { Double($0.mood) }
        guard !goodSleepMood.isEmpty, !poorSleepMood.isEmpty else { return nil }
        let diff = goodSleepMood.reduce(0,+)/Double(goodSleepMood.count) - poorSleepMood.reduce(0,+)/Double(poorSleepMood.count)
        guard diff > PatternThreshold.moodDiffThreshold else { return nil }
        let confidence = min(diff / PatternThreshold.confidenceScale, 1.0)
        return InsightCard(
            title: "More sleep correlates with better mood",
            detail: "On days with above-average sleep your mood is \(String(format: "%.1f", diff)) points higher on average.",
            icon: "sparkles",
            color: CadenceColor.moodBlue,
            confidence: confidence,
            category: .mood
        )
    }
}
