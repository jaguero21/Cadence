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
        let cal = Calendar.current

        // Phase 1: Find stress streaks (3+ high-stress entries, tolerating
        // 1-day logging gaps so Mon-Wed-Thu still counts as consecutive).
        struct Streak { let endDate: Date; let endIndex: Int }
        var streaks: [Streak] = []
        var runLength = 0
        var runLastDate: Date?
        var runEndIndex: Int?

        for (i, log) in logs.enumerated() {
            let isHigh = log.stressLevel >= PatternThreshold.highStressLevel
            let gap = runLastDate.flatMap {
                cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: log.date)).day
            } ?? Int.max

            if isHigh {
                if gap <= 2 {
                    runLength += 1
                } else {
                    if runLength >= PatternThreshold.consecutiveStressDays,
                       let endDate = runLastDate, let endIdx = runEndIndex {
                        streaks.append(Streak(endDate: endDate, endIndex: endIdx))
                    }
                    runLength = 1
                }
                runLastDate = log.date
                runEndIndex = i
            } else {
                if runLength >= PatternThreshold.consecutiveStressDays,
                   let endDate = runLastDate, let endIdx = runEndIndex {
                    streaks.append(Streak(endDate: endDate, endIndex: endIdx))
                }
                runLength = 0
                runLastDate = nil
                runEndIndex = nil
            }
        }
        if runLength >= PatternThreshold.consecutiveStressDays,
           let endDate = runLastDate, let endIdx = runEndIndex {
            streaks.append(Streak(endDate: endDate, endIndex: endIdx))
        }

        // Phase 2: For each streak, check the next logged entry within 3
        // calendar days for fatigue symptoms.
        var streaksChecked = 0
        var fatigueFollowed = 0

        for streak in streaks {
            guard streak.endIndex + 1 < logs.count,
                  let windowEnd = cal.date(byAdding: .day, value: 3, to: cal.startOfDay(for: streak.endDate))
            else { continue }
            let followUp = logs[streak.endIndex + 1]
            guard cal.startOfDay(for: followUp.date) <= windowEnd else { continue }
            streaksChecked += 1
            if followUp.symptoms.contains(where: {
                $0.name.localizedCaseInsensitiveContains("fatigue") ||
                $0.name.localizedCaseInsensitiveContains("tired")
            }) {
                fatigueFollowed += 1
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
