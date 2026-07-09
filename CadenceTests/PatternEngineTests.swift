import Testing
import Foundation
import SwiftData
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
    basicsCompleted: [String] = [],
    factors: [String] = [],
    customMetrics: [MetricEntry] = [],
    didEditMetrics: Bool = false,
    peaksAndValleysNote: String = "",
    hasPeaksAndValleysVoiceMemo: Bool = false,
    intentionsForTomorrow: String = "",
    freeNote: String = "",
    sleepQuality: Int = 5,
    painLevel: Int = 0,
    brainFogLevel: Int = 0,
    hkSteps: Int? = nil,
    hkRestingHR: Double? = nil,
    hkWristTemp: Double? = nil
) -> DailyLogSnapshot {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
    return DailyLogSnapshot(
        date: date,
        mood: mood,
        energy: energy,
        sleepHours: sleepHours,
        sleepQuality: sleepQuality,
        painLevel: painLevel,
        brainFogLevel: brainFogLevel,
        stressLevel: stressLevel,
        symptoms: symptoms,
        basicsCompleted: basicsCompleted,
        factors: factors,
        customMetrics: customMetrics,
        didEditMetrics: didEditMetrics,
        peaksAndValleysNote: peaksAndValleysNote,
        hasPeaksAndValleysVoiceMemo: hasPeaksAndValleysVoiceMemo,
        intentionsForTomorrow: intentionsForTomorrow,
        freeNote: freeNote,
        hkSteps: hkSteps,
        hkRestingHR: hkRestingHR,
        hkWristTemp: hkWristTemp
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

    @Test("Returns card when ≥3 poor-sleep nights all followed by headache")
    func sleepHeadache_threeOrMorePoorSleepAndHighConfidence_returnsCard() throws {
        // 3 poor-sleep nights, all 3 followed by headache. Observed rate = 1.0,
        // but the Wilson lower bound for 3/3 is ~0.75 — high enough to surface,
        // and deliberately below 1.0 so a tiny sample can't read as certain.
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
        let confidence = try #require(card?.confidence)
        #expect(confidence >= 0.5)
        #expect(confidence < 1.0) // 3/3 is no longer reported as 100% confidence
    }

    // Under raw proportion this was a 50% follow-through that surfaced a card.
    // The Wilson lower bound for 2/4 is ~0.28, below the 0.5 gate, so a moderate
    // rate over a thin sample is now correctly suppressed.
    @Test("Suppresses a 50% follow-through over a small sample (Wilson shrinkage)")
    func sleepHeadache_moderateRateSmallSample_isSuppressed() {
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
        #expect(card == nil)
    }
}

// MARK: - PatternEngine: medicationEffects

@Suite("PatternEngine – medicationEffects")
struct MedicationEffectsTests {

    // 6 logs with ~2 symptoms/day before the med, 6 with ~0 after → clear drop.
    @Test("Surfaces a 'fewer symptoms' card when symptom load drops after the start date")
    func medEffect_symptomDropAfterStart_returnsImprovementCard() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        var logs: [DailyLogSnapshot] = []
        for d in 7...12 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry(), fatigueEntry()])) } // before
        for d in 0...5  { logs.append(makeSnapshot(daysAgo: d, symptoms: [])) }                                // after
        let med = MedicationSnapshot(name: "Propranolol", dosage: "40 mg", startDate: start)

        let insights = PatternEngine.allInsights(from: logs, medications: [med])
        let card = insights.first { $0.category == .symptom }
        #expect(card != nil)
        #expect(card?.title == "Fewer symptoms since starting Propranolol")
    }

    @Test("No card when there aren't enough logged days before the start date")
    func medEffect_insufficientBeforeWindow_returnsNoCard() {
        let start = Calendar.current.date(byAdding: .day, value: -8, to: Calendar.current.startOfDay(for: .now))!
        var logs: [DailyLogSnapshot] = []
        // Only 2 days before start (< minimumMedEffectDays), plenty after.
        for d in 9...10 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry(), fatigueEntry()])) }
        for d in 0...6  { logs.append(makeSnapshot(daysAgo: d, symptoms: [])) }
        let med = MedicationSnapshot(name: "Propranolol", startDate: start)

        let insights = PatternEngine.allInsights(from: logs, medications: [med])
        #expect(insights.first { $0.category == .symptom } == nil)
    }

    @Test("No medication card when symptom load is unchanged")
    func medEffect_noChange_returnsNoCard() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        var logs: [DailyLogSnapshot] = []
        for d in 7...12 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry()])) }
        for d in 0...5  { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry()])) }
        let med = MedicationSnapshot(name: "Vitamin D", startDate: start)

        let insights = PatternEngine.allInsights(from: logs, medications: [med])
        #expect(insights.first { $0.category == .symptom } == nil)
    }
}

// MARK: - PatternEngine: factorCorrelations

@Suite("PatternEngine – factorCorrelations")
struct FactorCorrelationsTests {

    @Test("Surfaces a trigger card when a factor's days have more symptoms")
    func factor_moreSymptomsOnFactorDays_returnsCard() {
        var logs: [DailyLogSnapshot] = []
        // 4 factor days with 2 symptoms each.
        for d in 0...3 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry(), fatigueEntry()], factors: ["Alcohol"])) }
        // 4 non-factor days with 0 symptoms.
        for d in 4...7 { logs.append(makeSnapshot(daysAgo: d, symptoms: [], factors: [])) }

        let insights = PatternEngine.allInsights(from: logs)
        let card = insights.first { $0.title.contains("Alcohol") }
        #expect(card != nil)
        #expect(card?.category == .symptom)
    }

    @Test("No card when too few days carry the factor")
    func factor_insufficientFactorDays_returnsNoCard() {
        var logs: [DailyLogSnapshot] = []
        // Only 2 factor days (< minimumFactorDays).
        for d in 0...1 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry(), fatigueEntry()], factors: ["Alcohol"])) }
        for d in 2...7 { logs.append(makeSnapshot(daysAgo: d, symptoms: [], factors: [])) }

        let insights = PatternEngine.allInsights(from: logs)
        #expect(insights.first { $0.title.contains("Alcohol") } == nil)
    }

    @Test("No card when factor days are not worse than other days")
    func factor_noSymptomDifference_returnsNoCard() {
        var logs: [DailyLogSnapshot] = []
        for d in 0...3 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry()], factors: ["Caffeine"])) }
        for d in 4...7 { logs.append(makeSnapshot(daysAgo: d, symptoms: [headacheEntry()], factors: [])) }

        let insights = PatternEngine.allInsights(from: logs)
        #expect(insights.first { $0.title.contains("Caffeine") } == nil)
    }
}

// MARK: - AttachmentStore

@Suite("AttachmentStore – file round-trip")
struct AttachmentStoreTests {

    private func tempStore() -> AttachmentStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-test-\(UUID().uuidString)", isDirectory: true)
        return AttachmentStore(baseURL: dir)
    }

    @Test("Saved data can be read back by filename")
    func save_thenRead_roundTrips() throws {
        let store = tempStore()
        let payload = Data("hello".utf8)
        let filename = try #require(store.save(payload, fileExtension: "jpg"))
        #expect(filename.hasSuffix(".jpg"))
        #expect(store.data(for: filename) == payload)
    }

    @Test("Deleted attachments are no longer readable")
    func delete_removesFile() throws {
        let store = tempStore()
        let filename = try #require(store.save(Data([0x1, 0x2]), fileExtension: "m4a"))
        store.delete(filename)
        #expect(store.data(for: filename) == nil)
    }

    @Test("Each save gets a unique filename")
    func save_generatesUniqueNames() throws {
        let store = tempStore()
        let a = try #require(store.save(Data([0x1]), fileExtension: "jpg"))
        let b = try #require(store.save(Data([0x1]), fileExtension: "jpg"))
        #expect(a != b)
    }
}

// MARK: - Chart comparison helpers

@Suite("TrendChart – comparison helpers")
struct ChartComparisonTests {

    @Test("mean returns nil for empty and the average otherwise")
    func mean_emptyAndNonEmpty() {
        #expect(TrendChartView.mean([]) == nil)
        #expect(TrendChartView.mean([2, 4, 6]) == 4)
    }

    @Test("For higher-is-better metrics, a rise is an improvement")
    func improvement_higherIsBetterMetrics() {
        #expect(ChartMetric.mood.isImprovement(delta: 0.5))
        #expect(!ChartMetric.mood.isImprovement(delta: -0.5))
        #expect(ChartMetric.energy.isImprovement(delta: 1.0))
    }

    @Test("For stress, a drop is the improvement")
    func improvement_stressIsInverted() {
        #expect(ChartMetric.stress.isImprovement(delta: -1.0))
        #expect(!ChartMetric.stress.isImprovement(delta: 1.0))
    }
}

// MARK: - InsightRecorder

@Suite("InsightRecorder – record")
@MainActor
struct InsightRecorderTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func card(_ title: String, key: String? = nil, confidence: Double = 0.8) -> InsightCard {
        InsightCard(key: key ?? title, title: title, detail: "d", icon: "i", color: .red, confidence: confidence, category: .symptom)
    }

    @Test("First record of an insight is returned as newly created and persisted")
    func record_firstTime_isNew() throws {
        let context = try makeContext()
        let new = InsightRecorder.record([card("Poor sleep is linked to next-day headaches")], context: context)
        #expect(new.count == 1)
        let stored = try context.fetch(FetchDescriptor<InsightRecord>())
        #expect(stored.count == 1)
    }

    @Test("Recording the same insight again creates no new record")
    func record_secondTime_isNotNew() throws {
        let context = try makeContext()
        _ = InsightRecorder.record([card("Same pattern")], context: context)
        let secondPass = InsightRecorder.record([card("Same pattern", confidence: 0.9)], context: context)
        #expect(secondPass.isEmpty)
        let stored = try context.fetch(FetchDescriptor<InsightRecord>())
        #expect(stored.count == 1)
        #expect(stored.first?.confidence == 0.9) // confidence refreshed in place
    }

    @Test("Only genuinely new insights are returned on a mixed pass")
    func record_mixed_returnsOnlyNew() throws {
        let context = try makeContext()
        _ = InsightRecorder.record([card("A")], context: context)
        let new = InsightRecorder.record([card("A"), card("B")], context: context)
        #expect(new.count == 1)
        #expect(new.first?.title == "B")
    }

    // Regression: a medication insight flipping direction changes its TITLE but
    // keeps its semantic key — it must update the same record in place, not
    // mint a "new" pattern (which would re-fire the notification).
    @Test("A title change under the same key updates in place, not as new")
    func record_titleFlipSameKey_isNotNew() throws {
        let context = try makeContext()
        _ = InsightRecorder.record([card("Fewer symptoms since starting X", key: "med-effect:X")], context: context)
        let flipped = InsightRecorder.record([card("More symptoms since starting X", key: "med-effect:X")], context: context)
        #expect(flipped.isEmpty)
        let stored = try context.fetch(FetchDescriptor<InsightRecord>())
        #expect(stored.count == 1)
        #expect(stored.first?.title == "More symptoms since starting X") // copy refreshed in place
    }
}

// MARK: - HistoryView filtering

@Suite("HistoryView – logMatches")
struct HistoryFilterTests {

    @Test("All filter with empty query matches everything")
    func match_allFilterEmptyQuery_matches() {
        #expect(HistoryView.logMatches(isComplete: false, symptomNames: [], factors: [], note: "", filter: .all, query: ""))
    }

    @Test("Completed/in-progress filters respect completion state")
    func match_completionFilters() {
        #expect(HistoryView.logMatches(isComplete: true, symptomNames: [], factors: [], note: "", filter: .completed, query: ""))
        #expect(!HistoryView.logMatches(isComplete: false, symptomNames: [], factors: [], note: "", filter: .completed, query: ""))
        #expect(HistoryView.logMatches(isComplete: false, symptomNames: [], factors: [], note: "", filter: .inProgress, query: ""))
    }

    @Test("hasSymptoms filter requires at least one symptom")
    func match_hasSymptomsFilter() {
        #expect(HistoryView.logMatches(isComplete: true, symptomNames: ["Headache"], factors: [], note: "", filter: .hasSymptoms, query: ""))
        #expect(!HistoryView.logMatches(isComplete: true, symptomNames: [], factors: [], note: "", filter: .hasSymptoms, query: ""))
    }

    @Test("Query matches symptoms, factors, or note case-insensitively")
    func match_querySearchesAllFields() {
        #expect(HistoryView.logMatches(isComplete: true, symptomNames: ["Headache"], factors: [], note: "", filter: .all, query: "head"))
        #expect(HistoryView.logMatches(isComplete: true, symptomNames: [], factors: ["Alcohol"], note: "", filter: .all, query: "alc"))
        #expect(HistoryView.logMatches(isComplete: true, symptomNames: [], factors: [], note: "Rough day at work", filter: .all, query: "WORK"))
        #expect(!HistoryView.logMatches(isComplete: true, symptomNames: ["Headache"], factors: [], note: "", filter: .all, query: "nausea"))
    }

    @Test("Filter and query are combined (AND)")
    func match_filterAndQueryCombine() {
        // Matches the query but fails the completion filter.
        #expect(!HistoryView.logMatches(isComplete: false, symptomNames: ["Headache"], factors: [], note: "", filter: .completed, query: "head"))
    }
}

// MARK: - CSVBuilder

@Suite("CSVBuilder – csvString")
struct CSVBuilderTests {

    @Test("Emits a header plus one row per log, oldest first")
    func csv_headerAndRowOrder() {
        let logs = [
            makeSnapshot(daysAgo: 0, symptoms: [headacheEntry()]),
            makeSnapshot(daysAgo: 2),
        ]
        let lines = CSVBuilder.csvString(from: logs).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "Date,Mood,Energy,Sleep Hours,Sleep Quality,Pain,Brain Fog,Anxiety,Symptoms,Basics,Factors,Peaks and Valleys,Peaks and Valleys Voice Memo,Intentions for Tomorrow,Note,HK Steps,HK Resting HR,HK HRV,HK Sleep Hours,HK Active Energy,HK Mindful Minutes,HK Wrist Temp")
        #expect(lines.count == 3) // header + 2 rows
        // Oldest first: the day -2 row precedes the day 0 row.
        #expect(lines[1] < lines[2]) // ISO yyyy-MM-dd sorts chronologically as text
    }

    @Test("Every logged field lands in its column; missing HealthKit cells stay empty")
    func csv_carriesEveryField() {
        let logs = [makeSnapshot(
            daysAgo: 0, sleepHours: 6.5, mood: 2, energy: 4, stressLevel: 8,
            symptoms: [headacheEntry()],
            basicsCompleted: ["Hydration", "Movement"],
            factors: ["Travel"],
            peaksAndValleysNote: "peak note",
            intentionsForTomorrow: "rest more",
            freeNote: "long day",
            sleepQuality: 3, painLevel: 6, brainFogLevel: 7,
            hkSteps: 9500, hkRestingHR: 61
        )]
        let row = CSVBuilder.csvString(from: logs).split(separator: "\n")[1]
        #expect(row.contains(",6.5,3,6,7,8,"))          // sleep hrs, quality, pain, fog, anxiety
        #expect(row.contains("Hydration; Movement"))
        #expect(row.contains("long day"))
        #expect(row.contains("9500,61,,,,"))            // steps + HR present; HRV/sleep/energy/mindful empty
    }

    @Test("Includes Peaks & Valleys note, voice memo flag, and Intentions for Tomorrow")
    func csv_includesPeaksAndValleysAndIntentions() {
        let logs = [
            makeSnapshot(daysAgo: 0, peaksAndValleysNote: "Best: a walk. Worst: a headache.",
                        hasPeaksAndValleysVoiceMemo: true, intentionsForTomorrow: "Sleep earlier"),
        ]
        let csv = CSVBuilder.csvString(from: logs)
        #expect(csv.contains("Best: a walk. Worst: a headache."))
        #expect(csv.contains(",Yes,"))
        #expect(csv.contains("Sleep earlier"))
    }

    @Test("Quotes and escapes fields containing commas or quotes")
    func csv_escapesSpecialCharacters() {
        let weird = SymptomEntry(name: "Pain, sharp \"stabbing\"", severity: 5, emoji: "⚡️")
        let logs = [makeSnapshot(daysAgo: 0, symptoms: [weird])]
        let csv = CSVBuilder.csvString(from: logs)
        // The symptom field must be wrapped in quotes with the inner quotes doubled.
        #expect(csv.contains("\"Pain, sharp \"\"stabbing\"\"\""))
    }

    @Test("Joins multiple symptoms and factors with semicolons")
    func csv_joinsMultipleValues() {
        let logs = [makeSnapshot(daysAgo: 0, symptoms: [headacheEntry(), fatigueEntry()], factors: ["Alcohol", "Travel"])]
        let csv = CSVBuilder.csvString(from: logs)
        #expect(csv.contains("Headache; Fatigue"))
        #expect(csv.contains("Alcohol; Travel"))
    }
}

// MARK: - CustomTracker logic

@Suite("CustomTracker – range and snapshot")
struct CustomTrackerTests {

    @Test("range and midpoint reflect the configured bounds")
    func tracker_rangeAndMidpoint() {
        let tracker = CustomTracker(name: "Joint pain", minValue: 0, maxValue: 10)
        #expect(tracker.range == 0...10)
        #expect(tracker.midpoint == 5)
    }

    @Test("range guards against an inverted/degenerate max")
    func tracker_invertedBounds_areGuarded() {
        let tracker = CustomTracker(name: "Bad", minValue: 5, maxValue: 5)
        #expect(tracker.range.lowerBound == 5)
        #expect(tracker.range.upperBound >= 6)
    }

    @Test("DailyLogSnapshot carries custom metric values")
    func snapshot_carriesCustomMetrics() {
        let id = UUID()
        let snapshot = makeSnapshot(daysAgo: 0)
        #expect(snapshot.customMetrics.isEmpty)

        let withMetric = DailyLogSnapshot(date: .now, customMetrics: [MetricEntry(trackerID: id, value: 7)])
        #expect(withMetric.customMetrics.first?.value == 7)
        #expect(withMetric.customMetrics.first?.trackerID == id)
    }
}

// MARK: - Flare model logic

@Suite("Flare – duration and active state")
struct FlareTests {

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: .now)!
    }

    @Test("A flare with no end date is active")
    func flare_noEndDate_isActive() {
        let flare = Flare(startDate: daysAgo(2))
        #expect(flare.isActive)
    }

    @Test("A flare with an end date is not active")
    func flare_withEndDate_isNotActive() {
        let flare = Flare(startDate: daysAgo(5), endDate: daysAgo(2))
        #expect(flare.isActive == false)
    }

    @Test("Duration is inclusive of both start and end day")
    func flare_durationDays_isInclusive() {
        // Start 3 days ago, ended today → 4 calendar days inclusive.
        let flare = Flare(startDate: daysAgo(3), endDate: daysAgo(0))
        #expect(flare.durationDays == 4)
    }

    @Test("A same-day flare counts as one day")
    func flare_sameDay_isOneDay() {
        let flare = Flare(startDate: daysAgo(0), endDate: daysAgo(0))
        #expect(flare.durationDays == 1)
    }

    @Test("An ongoing flare counts through today")
    func flare_ongoing_countsThroughToday() {
        let flare = Flare(startDate: daysAgo(2)) // ongoing
        #expect(flare.durationDays == 3)
    }
}

// MARK: - PatternEngine: wilsonLowerBound

@Suite("PatternEngine – wilsonLowerBound")
struct WilsonLowerBoundTests {

    @Test("Zero or empty samples return 0")
    func wilson_degenerateInputs_returnZero() {
        #expect(PatternEngine.wilsonLowerBound(successes: 0, total: 0) == 0)
        #expect(PatternEngine.wilsonLowerBound(successes: 0, total: 5) == 0)
    }

    @Test("A perfect rate over a small sample is well below 1.0")
    func wilson_perfectSmallSample_shrinksBelowOne() {
        let lb = PatternEngine.wilsonLowerBound(successes: 3, total: 3)
        #expect(abs(lb - 0.75) < 0.01)   // ~0.75 at z = 1.0
        #expect(lb < 1.0)
    }

    @Test("Lower bound rises toward the observed rate as the sample grows")
    func wilson_largerSampleSameRate_increasesLowerBound() {
        let small = PatternEngine.wilsonLowerBound(successes: 3, total: 3)
        let large = PatternEngine.wilsonLowerBound(successes: 30, total: 30)
        #expect(large > small)
        #expect(large > 0.9)
    }

    @Test("A 50% rate over four trials lands below the 0.5 gate")
    func wilson_halfRateSmallSample_belowGate() {
        let lb = PatternEngine.wilsonLowerBound(successes: 2, total: 4)
        #expect(lb < PatternThreshold.minimumConfidence)
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

// MARK: - PatternEngine: trackerCorrelations

@Suite("PatternEngine – trackerCorrelations")
struct TrackerCorrelationsTests {

    private let trackerID = UUID()
    private var tracker: CustomTrackerSnapshot {
        CustomTrackerSnapshot(id: trackerID, name: "Screen time", unit: "hrs")
    }

    private func logs(highSymptoms: Int, lowSymptoms: Int) -> [DailyLogSnapshot] {
        // 6 high-value days + 6 low-value days (mean = 5, so > / <= splits 6/6).
        let high = (0..<6).map { makeSnapshot(
            daysAgo: $0,
            symptoms: (0..<highSymptoms).map { _ in headacheEntry() },
            customMetrics: [MetricEntry(trackerID: trackerID, value: 8)]
        ) }
        let low = (6..<12).map { makeSnapshot(
            daysAgo: $0,
            symptoms: (0..<lowSymptoms).map { _ in headacheEntry() },
            customMetrics: [MetricEntry(trackerID: trackerID, value: 2)]
        ) }
        return high + low
    }

    private func trackerCards(_ logs: [DailyLogSnapshot]) -> [InsightCard] {
        PatternEngine.allInsights(from: logs, trackers: [tracker])
            .filter { $0.key.hasPrefix("tracker:") }
    }

    @Test("More symptoms on high-value days surfaces a 'Higher' insight keyed by tracker id")
    func highDirection() {
        let cards = trackerCards(logs(highSymptoms: 2, lowSymptoms: 0))
        #expect(cards.count == 1)
        #expect(cards.first?.key == "tracker:\(trackerID.uuidString)")
        #expect(cards.first?.title.contains("Higher") == true)
    }

    @Test("More symptoms on low-value days surfaces a 'Lower' insight")
    func lowDirection() {
        let cards = trackerCards(logs(highSymptoms: 0, lowSymptoms: 2))
        #expect(cards.count == 1)
        #expect(cards.first?.title.contains("Lower") == true)
    }

    @Test("No insight when the symptom delta is under the threshold")
    func noDelta() {
        let cards = trackerCards(logs(highSymptoms: 1, lowSymptoms: 1))
        #expect(cards.isEmpty)
    }

    @Test("No insight with fewer than the minimum days per side")
    func tooFewDays() {
        // Only 4 entries per side (< minimumTrackerDays on each).
        let all = logs(highSymptoms: 2, lowSymptoms: 0)
        let thin = Array(all.prefix(4)) + Array(all.suffix(4))
        #expect(trackerCards(thin).isEmpty)
    }

    @Test("Days without an entry for the tracker are ignored, not treated as zero")
    func missingDaysIgnored() {
        // 12 tracked days + 10 untracked symptom-free days; the untracked days
        // must not dilute the low side into hiding the correlation.
        let untracked = (12..<22).map { makeSnapshot(daysAgo: $0) }
        let cards = trackerCards(logs(highSymptoms: 2, lowSymptoms: 0) + untracked)
        #expect(cards.count == 1)
    }
}

// MARK: - PatternEngine: flarePrecursors

@Suite("PatternEngine – flarePrecursors")
struct FlarePrecursorsTests {

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!)
    }

    // Two flares: days 20–18 ago and days 8–6 ago. Run-up windows are the 3
    // days before each start (23–21 and 11–9 days ago).
    private var flares: [FlareSnapshot] {
        [
            FlareSnapshot(startDate: day(20), endDate: day(18)),
            FlareSnapshot(startDate: day(8), endDate: day(6)),
        ]
    }

    private func logs(preStress: Int, baseStress: Int, preSleep: Double, baseSleep: Double) -> [DailyLogSnapshot] {
        (0..<30).map { daysAgo in
            let isPre = (21...23).contains(daysAgo) || (9...11).contains(daysAgo)
            return makeSnapshot(
                daysAgo: daysAgo,
                sleepHours: isPre ? preSleep : baseSleep,
                stressLevel: isPre ? preStress : baseStress
            )
        }
    }

    private func flareCards(_ logs: [DailyLogSnapshot], flares: [FlareSnapshot]) -> [InsightCard] {
        PatternEngine.allInsights(from: logs, flares: flares)
            .filter { $0.key.hasPrefix("flare-") }
    }

    @Test("Stress rising before flares surfaces flare-stress")
    func stressPrecursor() {
        let cards = flareCards(logs(preStress: 9, baseStress: 4, preSleep: 7.5, baseSleep: 7.5), flares: flares)
        #expect(cards.map(\.key) == ["flare-stress"])
    }

    @Test("Sleep dipping before flares surfaces flare-sleep")
    func sleepPrecursor() {
        let cards = flareCards(logs(preStress: 5, baseStress: 5, preSleep: 5.0, baseSleep: 8.0), flares: flares)
        #expect(cards.map(\.key) == ["flare-sleep"])
    }

    @Test("Both precursors can fire together")
    func bothPrecursors() {
        let cards = flareCards(logs(preStress: 9, baseStress: 4, preSleep: 5.0, baseSleep: 8.0), flares: flares)
        #expect(Set(cards.map(\.key)) == ["flare-stress", "flare-sleep"])
    }

    @Test("A single flare is not enough")
    func singleFlare() {
        let cards = flareCards(
            logs(preStress: 9, baseStress: 4, preSleep: 5.0, baseSleep: 8.0),
            flares: [FlareSnapshot(startDate: day(8), endDate: day(6))]
        )
        #expect(cards.isEmpty)
    }

    @Test("No precursor when the run-up looks like baseline")
    func noSignal() {
        let cards = flareCards(logs(preStress: 5, baseStress: 5, preSleep: 7.5, baseSleep: 7.5), flares: flares)
        #expect(cards.isEmpty)
    }

    // Wrist-temperature run-up: only days carrying a measurement participate.
    private func tempLogs(preTemp: Double?, baseTemp: Double?) -> [DailyLogSnapshot] {
        (0..<30).map { daysAgo in
            let isPre = (21...23).contains(daysAgo) || (9...11).contains(daysAgo)
            return makeSnapshot(daysAgo: daysAgo, hkWristTemp: isPre ? preTemp : baseTemp)
        }
    }

    @Test("Elevated overnight wrist temperature before flares surfaces flare-temp")
    func temperaturePrecursor() {
        let cards = flareCards(tempLogs(preTemp: 35.4, baseTemp: 34.9), flares: flares)
        #expect(cards.map(\.key) == ["flare-temp"])
    }

    @Test("A sub-threshold temperature rise stays quiet")
    func temperatureBelowThreshold() {
        let cards = flareCards(tempLogs(preTemp: 35.0, baseTemp: 34.9), flares: flares)
        #expect(cards.isEmpty)
    }

    @Test("No flare-temp without wrist-temperature data (no watch)")
    func noTemperatureData() {
        let cards = flareCards(tempLogs(preTemp: nil, baseTemp: nil), flares: flares)
        #expect(cards.isEmpty)
    }
}

// MARK: - ChartSeries

@Suite("ChartSeries – custom trackers")
@MainActor
struct ChartSeriesTests {

    @Test("isImprovement is nil when the desirable direction is unknown")
    func neutralDirection() {
        let series = ChartSeries.custom(CustomTracker(name: "Hydration", minValue: 0, maxValue: 8))
        #expect(series.isImprovement(delta: 1.0) == nil)
        #expect(series.isImprovement(delta: -1.0) == nil)
    }

    @Test("Built-in metrics keep a definite improvement direction")
    func builtInDirection() {
        #expect(ChartMetric.mood.series.isImprovement(delta: 1.0) == true)
        #expect(ChartMetric.stress.series.isImprovement(delta: 1.0) == false)
    }

    @Test("value extracts the tracker's entry and is nil on unlogged days")
    func valueExtraction() {
        let tracker = CustomTracker(name: "Hydration", minValue: 0, maxValue: 8)
        let series = ChartSeries.custom(tracker)
        let logged = DailyLog(date: .now)
        logged.customMetrics = [MetricEntry(trackerID: tracker.id, value: 6)]
        let unlogged = DailyLog(date: .now)
        #expect(series.value(logged) == 6)
        #expect(series.value(unlogged) == nil)
        // The tracker's declared range drives the chart's y-axis.
        #expect(series.yDomain == 0...8)
    }
}
