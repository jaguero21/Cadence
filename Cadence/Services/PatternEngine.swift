import SwiftUI
import OSLog

// Stateless pattern detector. Takes Sendable snapshots so it can be invoked
// from any isolation context — and won't race with SwiftData on @Model fields.
enum PatternEngine {
    private static let log = Logger(subsystem: "com.carpecadence", category: "PatternEngine")

    static func latestInsight(from logs: [DailyLogSnapshot]) -> InsightCard? {
        allInsights(from: logs).first
    }

    static func allInsights(
        from logs: [DailyLogSnapshot],
        medications: [MedicationSnapshot] = [],
        flares: [FlareSnapshot] = [],
        trackers: [CustomTrackerSnapshot] = []
    ) -> [InsightCard] {
        guard logs.count >= PatternThreshold.minimumLogs else { return [] }
        let sorted = logs.sorted { $0.date < $1.date }
        var cards: [InsightCard] = []

        if let card = sleepHeadacheCorrelation(logs: sorted) { cards.append(card) }
        if let card = stressFatiguePattern(logs: sorted) { cards.append(card) }
        if let card = energyTrendDecline(logs: sorted) { cards.append(card) }
        if let card = moodSleepCorrelation(logs: sorted) { cards.append(card) }
        cards.append(contentsOf: medicationEffects(medications: medications, logs: sorted))
        cards.append(contentsOf: factorCorrelations(logs: sorted))
        cards.append(contentsOf: trackerCorrelations(trackers: trackers, logs: sorted))
        cards.append(contentsOf: flarePrecursors(flares: flares, logs: sorted))

        return cards
    }

    // MARK: - Statistics

    // Wilson score interval lower bound for a binomial proportion. Unlike the
    // raw successes/total ratio, this shrinks toward 0 when the sample is small,
    // so a 2-of-2 streak no longer reports 100% confidence. Used for both the
    // gate and the displayed confidence so the two never disagree; the observed
    // frequency shown in copy is computed separately from the raw ratio.
    static func wilsonLowerBound(successes: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        let n = Double(total)
        let p = Double(successes) / n
        let z = PatternThreshold.confidenceZ
        let z2 = z * z
        let denominator = 1 + z2 / n
        let center = p + z2 / (2 * n)
        let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()
        return max(0, (center - margin) / denominator)
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
        // Observed frequency drives the copy; Wilson lower bound drives the
        // gate and the card's confidence so thin samples can't read as certain.
        let observedRate = Double(poorSleepThenHeadache) / Double(poorSleepTotal)
        let confidence = wilsonLowerBound(successes: poorSleepThenHeadache, total: poorSleepTotal)
        guard confidence >= PatternThreshold.minimumConfidence else { return nil }

        return InsightCard(
            key: "sleep-headache",
            title: "Poor sleep is linked to next-day headaches",
            detail: "On \(Int(observedRate * 100))% of days after sleeping under \(Int(PatternThreshold.poorSleepHours)) hours, you logged a headache the next day.",
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
            guard logs[streak.endIndex].stressLevel >= PatternThreshold.highStressLevel else {
                Self.log.error("Streak endIndex \(streak.endIndex) is not high-stress; skipping")
                continue
            }
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
        let confidence = wilsonLowerBound(successes: fatigueFollowed, total: streaksChecked)
        guard confidence >= PatternThreshold.minimumConfidence else { return nil }
        return InsightCard(
            key: "stress-fatigue",
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
            key: "energy-decline",
            title: "Energy declining week-over-week",
            detail: "Your average energy dropped from \(String(format: "%.1f", firstAvg)) to \(String(format: "%.1f", secondAvg)) over the past two weeks.",
            icon: "arrow.down.circle.fill",
            color: CadenceColor.energyOrange,
            confidence: confidence,
            category: .energy
        )
    }

    // For each medication, compare the average number of symptoms logged per day
    // in the window before its start date against the window after (up to its end
    // date, or now). Requires enough logged days on each side. A drop reads as
    // improvement; a rise is surfaced too, since a new med tracking with *more*
    // symptoms is worth a user's attention (possible side effects).
    private static func medicationEffects(medications: [MedicationSnapshot], logs: [DailyLogSnapshot]) -> [InsightCard] {
        guard !medications.isEmpty else { return [] }
        let cal = Calendar.current
        let sorted = logs.sorted { $0.date < $1.date }
        var cards: [InsightCard] = []

        for med in medications {
            let start = cal.startOfDay(for: med.startDate)
            let windowEnd = med.endDate.map { cal.startOfDay(for: $0) }
            let before = sorted.filter { $0.date < start }
            let after = sorted.filter { log in
                guard log.date >= start else { return false }
                if let windowEnd { return log.date <= windowEnd }
                return true
            }
            guard before.count >= PatternThreshold.minimumMedEffectDays,
                  after.count >= PatternThreshold.minimumMedEffectDays else { continue }

            let beforeAvg = before.map { Double($0.symptoms.count) }.reduce(0, +) / Double(before.count)
            let afterAvg = after.map { Double($0.symptoms.count) }.reduce(0, +) / Double(after.count)
            let delta = beforeAvg - afterAvg   // positive = fewer symptoms after starting
            guard abs(delta) >= PatternThreshold.medSymptomDeltaThreshold else { continue }

            let improved = delta > 0
            cards.append(InsightCard(
                // Direction-independent key: when the delta flips sign the SAME
                // record updates in place instead of minting a "new" pattern.
                key: "med-effect:\(med.name)",
                title: improved
                    ? "Fewer symptoms since starting \(med.name)"
                    : "More symptoms since starting \(med.name)",
                detail: "Your average daily symptoms went from \(String(format: "%.1f", beforeAvg)) to \(String(format: "%.1f", afterAvg)) after you started \(med.displayLabel).",
                icon: "pills.fill",
                color: improved ? CadenceColor.successGreen : CadenceColor.stressRed,
                confidence: min(abs(delta) / PatternThreshold.confidenceScale, 1.0),
                category: .symptom
            ))
        }
        return cards
    }

    // For each contextual factor the user logged, compare the average number of
    // symptoms on days with that factor against days without it. A meaningful
    // increase surfaces the factor as a likely trigger. Requires enough days on
    // each side so a single coincidental day can't drive the result.
    private static func factorCorrelations(logs: [DailyLogSnapshot]) -> [InsightCard] {
        let allFactors = Set(logs.flatMap { $0.factors })
        guard !allFactors.isEmpty else { return [] }
        var cards: [InsightCard] = []

        for factor in allFactors.sorted() {
            let withFactor = logs.filter { $0.factors.contains(factor) }
            let withoutFactor = logs.filter { !$0.factors.contains(factor) }
            guard withFactor.count >= PatternThreshold.minimumFactorDays,
                  withoutFactor.count >= PatternThreshold.minimumFactorDays else { continue }

            let withAvg = withFactor.map { Double($0.symptoms.count) }.reduce(0, +) / Double(withFactor.count)
            let withoutAvg = withoutFactor.map { Double($0.symptoms.count) }.reduce(0, +) / Double(withoutFactor.count)
            let delta = withAvg - withoutAvg   // positive = more symptoms on factor days
            guard delta >= PatternThreshold.factorSymptomDeltaThreshold else { continue }

            cards.append(InsightCard(
                key: "factor:\(factor)",
                title: "\(factor) days tend to have more symptoms",
                detail: "On days you logged \(factor), you averaged \(String(format: "%.1f", withAvg)) symptoms versus \(String(format: "%.1f", withoutAvg)) on other days.",
                icon: "exclamationmark.triangle.fill",
                color: CadenceColor.stressRed,
                confidence: min(delta / PatternThreshold.confidenceScale, 1.0),
                category: .symptom
            ))
        }
        return cards
    }

    // For each custom tracker, split its logged days at the tracker's mean value
    // and compare average daily symptom count on high days vs low days. Either
    // direction is surfaced (a "Hydration" tracker correlates low-side; a "Screen
    // time" tracker high-side). Keyed by the tracker's stable id, not its name,
    // so a rename updates the same insight record instead of minting a new one.
    private static func trackerCorrelations(trackers: [CustomTrackerSnapshot], logs: [DailyLogSnapshot]) -> [InsightCard] {
        guard !trackers.isEmpty else { return [] }
        var cards: [InsightCard] = []

        for tracker in trackers {
            let entries: [(log: DailyLogSnapshot, value: Double)] = logs.compactMap { log in
                log.customMetrics.first { $0.trackerID == tracker.id }.map { (log, Double($0.value)) }
            }
            guard entries.count >= 2 * PatternThreshold.minimumTrackerDays else { continue }
            let mean = entries.map(\.value).reduce(0, +) / Double(entries.count)
            let high = entries.filter { $0.value > mean }
            let low = entries.filter { $0.value <= mean }
            guard high.count >= PatternThreshold.minimumTrackerDays,
                  low.count >= PatternThreshold.minimumTrackerDays else { continue }

            let highAvg = high.map { Double($0.log.symptoms.count) }.reduce(0, +) / Double(high.count)
            let lowAvg = low.map { Double($0.log.symptoms.count) }.reduce(0, +) / Double(low.count)
            let delta = highAvg - lowAvg   // positive = more symptoms on high-value days
            guard abs(delta) >= PatternThreshold.trackerSymptomDeltaThreshold else { continue }

            let moreOnHigh = delta > 0
            cards.append(InsightCard(
                // Direction-independent key (see med-effect): a flipped delta
                // updates the same record.
                key: "tracker:\(tracker.id.uuidString)",
                title: moreOnHigh
                    ? "Higher \(tracker.name) days tend to have more symptoms"
                    : "Lower \(tracker.name) days tend to have more symptoms",
                detail: "On days your \(tracker.name) was \(moreOnHigh ? "above" : "at or below") its average, you logged \(String(format: "%.1f", max(highAvg, lowAvg))) symptoms versus \(String(format: "%.1f", min(highAvg, lowAvg))) on other days.",
                icon: "slider.horizontal.3",
                color: CadenceColor.accent,
                confidence: min(abs(delta) / PatternThreshold.confidenceScale, 1.0),
                category: .symptom
            ))
        }
        return cards
    }

    // Compare the run-up window before each flare against baseline days (days
    // that are neither inside a flare nor in a run-up window). A stress rise or
    // a sleep drop in the run-up surfaces as an early-warning pattern.
    private static func flarePrecursors(flares: [FlareSnapshot], logs: [DailyLogSnapshot]) -> [InsightCard] {
        guard flares.count >= PatternThreshold.minimumFlaresForPattern else { return [] }
        let cal = Calendar.current

        // Classify each log day: pre-flare (within the window before a start),
        // in-flare, or baseline.
        var preFlareLogs: [DailyLogSnapshot] = []
        var baselineLogs: [DailyLogSnapshot] = []
        var flaresWithRunUpData = Set<Date>()

        for log in logs {
            let day = cal.startOfDay(for: log.date)
            var isPre = false
            var isDuring = false
            for flare in flares {
                let start = cal.startOfDay(for: flare.startDate)
                let end = flare.endDate.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: .now)
                if day >= start && day <= end {
                    isDuring = true
                    break
                }
                if let windowStart = cal.date(byAdding: .day, value: -PatternThreshold.flarePrecursorWindowDays, to: start),
                   day >= windowStart && day < start {
                    isPre = true
                    flaresWithRunUpData.insert(start)
                }
            }
            if isDuring { continue }
            if isPre { preFlareLogs.append(log) } else { baselineLogs.append(log) }
        }

        guard flaresWithRunUpData.count >= PatternThreshold.minimumFlaresForPattern,
              preFlareLogs.count >= PatternThreshold.flarePrecursorWindowDays,
              !baselineLogs.isEmpty else { return [] }

        var cards: [InsightCard] = []
        let preStress = preFlareLogs.map { Double($0.stressLevel) }.reduce(0, +) / Double(preFlareLogs.count)
        let baseStress = baselineLogs.map { Double($0.stressLevel) }.reduce(0, +) / Double(baselineLogs.count)
        if preStress - baseStress >= PatternThreshold.flareStressDeltaThreshold {
            cards.append(InsightCard(
                key: "flare-stress",
                title: "Stress tends to rise before your flares",
                detail: "In the \(PatternThreshold.flarePrecursorWindowDays) days before a flare, your average stress was \(String(format: "%.1f", preStress)) versus \(String(format: "%.1f", baseStress)) on typical days.",
                icon: "flame.fill",
                color: CadenceColor.stressRed,
                confidence: min((preStress - baseStress) / PatternThreshold.confidenceScale, 1.0),
                category: .stress
            ))
        }

        let preSleep = preFlareLogs.map(\.sleepHours).reduce(0, +) / Double(preFlareLogs.count)
        let baseSleep = baselineLogs.map(\.sleepHours).reduce(0, +) / Double(baselineLogs.count)
        if baseSleep - preSleep >= PatternThreshold.flareSleepDeltaThreshold {
            cards.append(InsightCard(
                key: "flare-sleep",
                title: "Sleep tends to dip before your flares",
                detail: "In the \(PatternThreshold.flarePrecursorWindowDays) days before a flare, you averaged \(String(format: "%.1f", preSleep)) hours of sleep versus \(String(format: "%.1f", baseSleep)) on typical days.",
                icon: "moon.zzz.fill",
                color: CadenceColor.sleepPurple,
                confidence: min((baseSleep - preSleep) / PatternThreshold.confidenceScale, 1.0),
                category: .sleep
            ))
        }

        // Overnight wrist temperature (HealthKit, Watch Series 8+): only days
        // that carry a measurement participate; users without a watch simply
        // never see this card. Requires readings on both sides so a single
        // warm night can't fabricate a pattern.
        let preTemps = preFlareLogs.compactMap(\.hkWristTemp)
        let baseTemps = baselineLogs.compactMap(\.hkWristTemp)
        if preTemps.count >= PatternThreshold.minimumFlaresForPattern,
           baseTemps.count >= PatternThreshold.minimumLogs {
            let preTemp = preTemps.reduce(0, +) / Double(preTemps.count)
            let baseTemp = baseTemps.reduce(0, +) / Double(baseTemps.count)
            if preTemp - baseTemp >= PatternThreshold.flareTempDeltaThreshold {
                cards.append(InsightCard(
                    key: "flare-temp",
                    title: "Wrist temperature tends to run high before your flares",
                    detail: "In the \(PatternThreshold.flarePrecursorWindowDays) days before a flare, your overnight wrist temperature averaged \(String(format: "%.1f", preTemp))°C versus \(String(format: "%.1f", baseTemp))°C on typical days.",
                    icon: "thermometer.medium",
                    color: CadenceColor.energyOrange,
                    confidence: min((preTemp - baseTemp) / (2 * PatternThreshold.flareTempDeltaThreshold), 1.0),
                    category: .symptom
                ))
            }
        }
        return cards
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
            key: "mood-sleep",
            title: "More sleep correlates with better mood",
            detail: "On days with above-average sleep your mood is \(String(format: "%.1f", diff)) points higher on average.",
            icon: "sparkles",
            color: CadenceColor.moodBlue,
            confidence: confidence,
            category: .mood
        )
    }
}
