import SwiftUI

actor PatternEngine {
    static let shared = PatternEngine()
    private init() {}

    func latestInsight(from logs: [DailyLog]) -> InsightCard? {
        allInsights(from: logs).first
    }

    func allInsights(from logs: [DailyLog]) -> [InsightCard] {
        guard logs.count >= 5 else { return [] }
        let sorted = logs.sorted { $0.date < $1.date }
        var cards: [InsightCard] = []

        if let card = sleepHeadacheCorrelation(logs: sorted) { cards.append(card) }
        if let card = stressFatiguePattern(logs: sorted) { cards.append(card) }
        if let card = energyTrendDecline(logs: sorted) { cards.append(card) }
        if let card = moodSleepCorrelation(logs: sorted) { cards.append(card) }

        return cards
    }

    // MARK: - Pattern Detectors

    private func sleepHeadacheCorrelation(logs: [DailyLog]) -> InsightCard? {
        var poorSleepThenHeadache = 0
        var poorSleepTotal = 0

        for i in 0..<logs.count - 1 {
            if logs[i].sleepHours < 6 {
                poorSleepTotal += 1
                let nextDaySymptoms = logs[i + 1].symptoms.map { $0.name.lowercased() }
                if nextDaySymptoms.contains(where: { $0.contains("headache") }) {
                    poorSleepThenHeadache += 1
                }
            }
        }

        guard poorSleepTotal >= 3 else { return nil }
        let confidence = Double(poorSleepThenHeadache) / Double(poorSleepTotal)
        guard confidence >= 0.5 else { return nil }

        return InsightCard(
            title: "Poor sleep is linked to next-day headaches",
            detail: "On \(Int(confidence * 100))% of days after sleeping under 6 hours, you logged a headache the next day.",
            icon: "moon.zzz.fill",
            color: CadenceColor.sleepPurple,
            confidence: confidence,
            category: .sleep
        )
    }

    private func stressFatiguePattern(logs: [DailyLog]) -> InsightCard? {
        var consecutiveStress = 0
        var streaksChecked = 0
        var fatigueFollowed = 0

        for i in 0..<logs.count {
            if logs[i].stressLevel >= 7 {
                consecutiveStress += 1
            } else {
                if consecutiveStress >= 3 {
                    streaksChecked += 1
                    let recoverySymptoms = logs[i].symptoms.map { $0.name.lowercased() }
                    if recoverySymptoms.contains(where: { $0.contains("fatigue") || $0.contains("tired") }) {
                        fatigueFollowed += 1
                    }
                }
                consecutiveStress = 0
            }
        }

        guard fatigueFollowed >= 2, streaksChecked > 0 else { return nil }
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

    private func energyTrendDecline(logs: [DailyLog]) -> InsightCard? {
        // logs is sorted ascending; take the last 14 (most recent)
        let recent = logs.suffix(14)
        let firstHalf  = Array(recent.prefix(7)).map { Double($0.energy) }   // older 7
        let secondHalf = Array(recent.suffix(7)).map { Double($0.energy) }   // recent 7
        guard firstHalf.count == 7, secondHalf.count == 7 else { return nil }
        let firstAvg = firstHalf.reduce(0,+) / 7
        let secondAvg = secondHalf.reduce(0,+) / 7
        let drop = firstAvg - secondAvg
        guard drop > 1.5 else { return nil }
        let confidence = min(drop / 5.0, 1.0)
        return InsightCard(
            title: "Energy declining week-over-week",
            detail: "Your average energy dropped from \(String(format: "%.1f", firstAvg)) to \(String(format: "%.1f", secondAvg)) over the past two weeks.",
            icon: "arrow.down.circle.fill",
            color: CadenceColor.energyOrange,
            confidence: confidence,
            category: .energy
        )
    }

    private func moodSleepCorrelation(logs: [DailyLog]) -> InsightCard? {
        let pairs = logs.filter { $0.sleepHours > 0 && $0.didEditMetrics }
        guard pairs.count >= 7 else { return nil }
        let sleepAvg = pairs.map(\.sleepHours).reduce(0,+) / Double(pairs.count)
        let goodSleepMood = pairs.filter { $0.sleepHours > sleepAvg }.map { Double($0.mood) }
        let poorSleepMood = pairs.filter { $0.sleepHours <= sleepAvg }.map { Double($0.mood) }
        guard !goodSleepMood.isEmpty, !poorSleepMood.isEmpty else { return nil }
        let diff = goodSleepMood.reduce(0,+)/Double(goodSleepMood.count) - poorSleepMood.reduce(0,+)/Double(poorSleepMood.count)
        guard diff > 1.0 else { return nil }
        let confidence = min(diff / 5.0, 1.0)
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
