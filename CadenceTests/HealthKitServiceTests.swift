import Testing
import HealthKit
import Foundation
import SwiftData
@testable import Cadence

// MARK: - HealthKitService – pure logic tests
//
// Full HealthKit integration requires a physical device with health data.
// These tests cover only the pure-logic surface:
//   • isAvailable: does not crash; returns false on the simulator
//   • requestAuthorization: returns without throwing when isAvailable is false (early return guard)
//   • HealthKitSnapshot: struct initialisation — default is all-nil (no data), not zero

@Suite("HealthKitService – isAvailable")
@MainActor
struct HealthKitServiceIsAvailableTests {

    @Test("isAvailable does not crash and returns a Bool")
    func isAvailable_doesNotCrash() {
        let service = HealthKitService.shared
        // On the iOS Simulator HKHealthStore.isHealthDataAvailable() returns false.
        // We only assert it doesn't crash and returns a Bool (not that it's any specific value).
        let available = service.isAvailable
        #expect(available == true || available == false) // exhaustive Bool check — just confirms no crash
    }

    @Test("isAvailable returns a consistent Bool across multiple accesses")
    func isAvailable_isConsistentAcrossAccesses() {
        // isAvailable must be stable — two reads must return the same value.
        let first  = HealthKitService.shared.isAvailable
        let second = HealthKitService.shared.isAvailable
        #expect(first == second)
    }
}

@Suite("HealthKitService – requestAuthorization guard")
@MainActor
struct HealthKitServiceAuthorizationTests {

    @Test("requestAuthorization guard: when isAvailable is false, returns without throwing")
    func requestAuthorization_whenNotAvailable_doesNotThrow() async throws {
        // When isAvailable is false the guard at the top of requestAuthorization fires
        // an immediate early return — the function must complete without throwing.
        // When isAvailable is true (real device or simulator with HealthKit entitlement)
        // we skip this test because the underlying HKHealthStore call requires user interaction.
        guard !HealthKitService.shared.isAvailable else { return }
        try await HealthKitService.shared.requestAuthorization()
        // Reaching here without throwing is the assertion.
    }
}

// MARK: - HealthKitSnapshot – struct tests
//
// steps and sleepHours are Int? / Double? — nil means "no HealthKit data",
// which is distinct from a genuine zero value.

@Suite("HealthKitSnapshot – default initialisation")
struct HealthKitSnapshotDefaultInitTests {

    @Test("Default snapshot has steps = nil (no data)")
    func snapshot_steps_defaultsToNil() {
        let snapshot = HealthKitSnapshot()
        #expect(snapshot.steps == nil)
    }

    @Test("Default snapshot has sleepHours = nil (no data)")
    func snapshot_sleepHours_defaultsToNil() {
        let snapshot = HealthKitSnapshot()
        #expect(snapshot.sleepHours == nil)
    }

    @Test("Default snapshot has restingHR = nil")
    func snapshot_restingHR_defaultsToNil() {
        #expect(HealthKitSnapshot().restingHR == nil)
    }

    @Test("Default snapshot has hrv = nil")
    func snapshot_hrv_defaultsToNil() {
        #expect(HealthKitSnapshot().hrv == nil)
    }

    @Test("Default snapshot has activeEnergy and mindfulMinutes = nil")
    func snapshot_energyAndMindful_defaultToNil() {
        #expect(HealthKitSnapshot().activeEnergy == nil)
        #expect(HealthKitSnapshot().mindfulMinutes == nil)
    }
}

@Suite("HealthKitSnapshot – explicit values")
struct HealthKitSnapshotValueTests {

    @Test("Snapshot stores all non-nil values correctly")
    func snapshot_storesNonNilValues() {
        let snapshot = HealthKitSnapshot(steps: 8432, restingHR: 62.5, hrv: 45.3, sleepHours: 7.25,
                                         activeEnergy: 420, mindfulMinutes: 12)
        #expect(snapshot.steps == 8432)
        #expect(snapshot.restingHR == 62.5)
        #expect(snapshot.hrv == 45.3)
        #expect(snapshot.sleepHours == 7.25)
        #expect(snapshot.activeEnergy == 420)
        #expect(snapshot.mindfulMinutes == 12)
    }

    @Test("Snapshot with only steps populated leaves other fields nil")
    func snapshot_onlySteps_otherFieldsNil() {
        let snapshot = HealthKitSnapshot(steps: 10000)
        #expect(snapshot.steps == 10000)
        #expect(snapshot.restingHR == nil)
        #expect(snapshot.hrv == nil)
        #expect(snapshot.sleepHours == nil)
    }

    @Test("Snapshot is a value type — mutation does not affect original")
    func snapshot_isValueType_mutationDoesNotAffectOriginal() {
        let original = HealthKitSnapshot(steps: 100, restingHR: 65.0, hrv: 40.0, sleepHours: 6.5)
        var copy = original
        copy.steps = 9999
        copy.sleepHours = nil
        #expect(original.steps == 100)
        #expect(original.sleepHours == 6.5)
    }
}

// MARK: - Sleep quality score

// The 0–10 score that pre-fills the Body Metrics "Sleep quality" slider.
// Derived only from real stage data: 60% efficiency (asleep vs awake) +
// 40% restorative share (deep+REM / asleep, normalised against ~45%).
@Suite("HealthKitService – sleepQualityScore")
struct SleepQualityScoreTests {

    @Test("No stage data (duration-only source) yields nil, not a fake score")
    func durationOnly_returnsNil() {
        // 7h logged as unspecified sleep — no core/REM/deep stages.
        let score = HealthKitService.sleepQualityScore(
            asleepSeconds: 7 * 3600, awakeSeconds: 0,
            deepSeconds: 0, remSeconds: 0, stagedSeconds: 0
        )
        #expect(score == nil)
    }

    @Test("No sleep at all yields nil")
    func noSleep_returnsNil() {
        let score = HealthKitService.sleepQualityScore(
            asleepSeconds: 0, awakeSeconds: 3600,
            deepSeconds: 0, remSeconds: 0, stagedSeconds: 0
        )
        #expect(score == nil)
    }

    @Test("An efficient, restorative night scores at the top of the scale")
    func greatNight_scoresHigh() {
        // 8h asleep, 10 min awake, 45% deep+REM — efficiency ≈ 0.98, restorative = 1.
        let asleep = 8.0 * 3600
        let score = HealthKitService.sleepQualityScore(
            asleepSeconds: asleep, awakeSeconds: 600,
            deepSeconds: asleep * 0.25, remSeconds: asleep * 0.20, stagedSeconds: asleep
        )
        #expect(score == 10)
    }

    @Test("A fragmented night with little deep/REM scores low")
    func fragmentedNight_scoresLow() throws {
        // 4h asleep vs 2h awake (efficiency 0.67), only 10% deep+REM.
        let asleep = 4.0 * 3600
        let score = HealthKitService.sleepQualityScore(
            asleepSeconds: asleep, awakeSeconds: 2 * 3600,
            deepSeconds: asleep * 0.05, remSeconds: asleep * 0.05, stagedSeconds: asleep
        )
        let unwrapped = try #require(score)
        #expect(unwrapped <= 5)
    }

    @Test("Score is clamped to the 0...10 slider range")
    func score_staysInSliderRange() throws {
        let score = HealthKitService.sleepQualityScore(
            asleepSeconds: 10 * 3600, awakeSeconds: 0,
            deepSeconds: 5 * 3600, remSeconds: 5 * 3600, stagedSeconds: 10 * 3600
        )
        let unwrapped = try #require(score)
        #expect((0...10).contains(unwrapped))
    }
}

// MARK: - Symptom & mood mapping

// The pure maps behind two-way Health symptom sync and State of Mind mood.
@Suite("HealthKitService – symptom and mood mapping")
struct HealthMappingTests {

    @Test("Cadence names map to HK symptom types case-insensitively")
    func nameToType() {
        #expect(HealthKitService.symptomTypeIdentifier(for: "Headache") == .headache)
        #expect(HealthKitService.symptomTypeIdentifier(for: "FATIGUE") == .fatigue)
        #expect(HealthKitService.symptomTypeIdentifier(for: "Pain") == .generalizedBodyAche)
        // No honest HK counterpart → no sync, not a stretched mapping.
        #expect(HealthKitService.symptomTypeIdentifier(for: "Brain Fog") == nil)
    }

    @Test("Type→name round trip picks the canonical Cadence display name")
    func typeToName() {
        #expect(HealthKitService.symptomName(for: .headache) == "Headache")
        #expect(HealthKitService.symptomName(for: .coughing) == "Coughing")
        #expect(HealthKitService.symptomName(for: .generalizedBodyAche) == "Pain")
    }

    @Test("Every mapped name survives a name→type→name round trip")
    func roundTripAllMappings() {
        for identifier in Set(HealthKitService.symptomTypeByName.values) {
            let name = HealthKitService.symptomName(for: identifier)
            #expect(name != nil)
            #expect(HealthKitService.symptomTypeIdentifier(for: name ?? "") == identifier)
        }
    }

    @Test("Severity buckets: 1–3 mild, 4–7 moderate, 8–10 severe")
    func severityToHK() {
        #expect(HealthKitService.hkSeverityValue(forSeverity: 1) == HKCategoryValueSeverity.mild.rawValue)
        #expect(HealthKitService.hkSeverityValue(forSeverity: 3) == HKCategoryValueSeverity.mild.rawValue)
        #expect(HealthKitService.hkSeverityValue(forSeverity: 4) == HKCategoryValueSeverity.moderate.rawValue)
        #expect(HealthKitService.hkSeverityValue(forSeverity: 7) == HKCategoryValueSeverity.moderate.rawValue)
        #expect(HealthKitService.hkSeverityValue(forSeverity: 8) == HKCategoryValueSeverity.severe.rawValue)
        #expect(HealthKitService.hkSeverityValue(forSeverity: 10) == HKCategoryValueSeverity.severe.rawValue)
    }

    @Test("HK severity maps back to a representative Cadence severity")
    func severityFromHK() {
        #expect(HealthKitService.cadenceSeverity(fromHKSeverity: HKCategoryValueSeverity.mild.rawValue) == 2)
        #expect(HealthKitService.cadenceSeverity(fromHKSeverity: HKCategoryValueSeverity.moderate.rawValue) == 5)
        #expect(HealthKitService.cadenceSeverity(fromHKSeverity: HKCategoryValueSeverity.severe.rawValue) == 9)
        #expect(HealthKitService.cadenceSeverity(fromHKSeverity: HKCategoryValueSeverity.unspecified.rawValue) == 5)
    }

    @Test("Mood ↔ valence round trips across the whole 1–5 scale")
    func moodValenceRoundTrip() {
        for mood in 1...5 {
            let valence = HealthKitService.valence(forMood: mood)
            #expect((-1.0...1.0).contains(valence))
            #expect(HealthKitService.mood(forValence: valence) == mood)
        }
        // Out-of-range inputs clamp instead of wrapping.
        #expect(HealthKitService.valence(forMood: 99) == 1.0)
        #expect(HealthKitService.mood(forValence: 3.0) == 5)
        #expect(HealthKitService.mood(forValence: -3.0) == 1)
    }
}

// MARK: - Intense exercise gate

// Pure gate behind the "Intense exercise" auto-factor: enough time OR enough
// energy — a long easy hike and a short hard run both count.
@Suite("HealthKitService – isIntenseExercise")
struct IntenseExerciseGateTests {

    // Zones are whatever the person configured in Health Settings — 3 zones or
    // 5 — so "hard" is the top two by index, not a fixed zone number.
    @Test("Top-zone minutes sum the highest two zones, whatever the zone count")
    func topZoneMinutes_sumsTopTwo() {
        let five: [(index: Int, minutes: Double)] = [(1, 20), (2, 15), (3, 10), (4, 6), (5, 4)]
        #expect(HealthKitService.topZoneMinutes(durations: five, zoneCount: 5) == 10)

        let three: [(index: Int, minutes: Double)] = [(1, 30), (2, 8), (3, 5)]
        #expect(HealthKitService.topZoneMinutes(durations: three, zoneCount: 3) == 13)

        let one: [(index: Int, minutes: Double)] = [(1, 12)]
        #expect(HealthKitService.topZoneMinutes(durations: one, zoneCount: 1) == 12)

        #expect(HealthKitService.topZoneMinutes(durations: [], zoneCount: 5) == 0)
    }

    @Test("Ten minutes in the top zones is the line")
    func zoneThreshold_isTenMinutes() {
        #expect(!HealthKitService.isIntenseExercise(topZoneMinutes: 9.9, totalMinutes: 30, totalKilocalories: 200))
        #expect(HealthKitService.isIntenseExercise(topZoneMinutes: 10, totalMinutes: 30, totalKilocalories: 200))
    }

    // The whole point: effort, not time on feet.
    @Test("Zones override the duration and calorie rule in both directions")
    func zones_overrideTotals() {
        // Two-hour easy hike: clears 45 minutes, no time up high.
        #expect(!HealthKitService.isIntenseExercise(topZoneMinutes: 0, totalMinutes: 120, totalKilocalories: 600))
        // Short intervals: clears neither old threshold.
        #expect(HealthKitService.isIntenseExercise(topZoneMinutes: 12, totalMinutes: 25, totalKilocalories: 150))
    }

    @Test("Without zone data the original rule still decides")
    func noZoneData_fallsBackToTotals() {
        #expect(HealthKitService.isIntenseExercise(topZoneMinutes: nil, totalMinutes: 50, totalKilocalories: 100))
        #expect(HealthKitService.isIntenseExercise(topZoneMinutes: nil, totalMinutes: 20, totalKilocalories: 500))
        #expect(!HealthKitService.isIntenseExercise(topZoneMinutes: nil, totalMinutes: 20, totalKilocalories: 100))
    }

    @Test("Below both thresholds is not intense")
    func belowBoth() {
        #expect(HealthKitService.isIntenseExercise(totalMinutes: 30, totalKilocalories: 250) == false)
    }

    @Test("Enough time alone qualifies (long easy hike)")
    func timeAlone() {
        #expect(HealthKitService.isIntenseExercise(totalMinutes: HealthThreshold.intenseWorkoutMinutes, totalKilocalories: 0))
    }

    @Test("Enough energy alone qualifies (short hard run)")
    func energyAlone() {
        #expect(HealthKitService.isIntenseExercise(totalMinutes: 20, totalKilocalories: HealthThreshold.intenseWorkoutKilocalories))
    }
}

// MARK: - HealthDataRefresher

// Background/foreground top-up of today's log: hk* fields only, and NEVER
// creates a log — a day the user didn't start must not grow a phantom entry.
@MainActor
@Suite("HealthDataRefresher – refreshToday")
struct HealthDataRefresherTests {

    // Both models, since the refresher now gates on DailyLog but writes to
    // HealthSnapshot. One in-memory configuration is enough here — the
    // CloudKit/local split is a storage concern, not a behavioural one, and is
    // covered directly in SchemaMigrationTests.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self, HealthSnapshot.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func health(on date: Date = .now, in context: ModelContext) -> HealthSnapshot? {
        HealthSnapshot.row(for: date, in: context)
    }

    @Test("Updates only objective fields, leaving the user's log untouched")
    func updatesExistingLog() throws {
        let context = try makeContext()
        let log = DailyLog(date: .now)
        log.mood = 4
        context.insert(log)
        let morning = HealthSnapshot(date: .now)
        morning.hkSteps = 1200   // morning value
        context.insert(morning)
        try context.save()

        let updated = HealthDataRefresher.refreshToday(
            context: context,
            snapshot: HealthKitSnapshot(steps: 9800, activeEnergy: 300, workoutMinutes: 52)
        )

        #expect(updated)
        let row = try #require(health(in: context))
        #expect(row.hkSteps == 9800)          // topped up
        #expect(row.hkActiveEnergy == 300)
        #expect(row.hkWorkoutMinutes == 52)   // evening workout lands on the morning row
        #expect(log.mood == 4)                // user data untouched
    }

    @Test("Never creates a log — or a health row — for a day the user didn't start")
    func neverCreatesLog() throws {
        let context = try makeContext()

        let updated = HealthDataRefresher.refreshToday(
            context: context,
            snapshot: HealthKitSnapshot(steps: 9800)
        )

        #expect(updated == false)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).isEmpty)
        // An untouched day leaves no trace in either store.
        #expect(try context.fetch(FetchDescriptor<HealthSnapshot>()).isEmpty)
    }

    @Test("A nil snapshot value never blanks an earlier measurement")
    func nilNeverBlanks() throws {
        let context = try makeContext()
        context.insert(DailyLog(date: .now))
        let row = HealthSnapshot(date: .now)
        row.hkWristTemp = 35.1
        context.insert(row)
        try context.save()

        HealthDataRefresher.refreshToday(context: context, snapshot: HealthKitSnapshot(steps: 500))

        let fetched = try #require(health(in: context))
        #expect(fetched.hkWristTemp == 35.1)
        #expect(fetched.hkSteps == 500)
    }

    @Test("Refreshing twice in a day updates one row rather than adding a second")
    func upsertDoesNotDuplicate() throws {
        let context = try makeContext()
        context.insert(DailyLog(date: .now))
        try context.save()

        HealthDataRefresher.refreshToday(context: context, snapshot: HealthKitSnapshot(steps: 100))
        HealthDataRefresher.refreshToday(context: context, snapshot: HealthKitSnapshot(steps: 4200))

        let rows = try context.fetch(FetchDescriptor<HealthSnapshot>())
        #expect(rows.count == 1)
        #expect(rows.first?.hkSteps == 4200)
    }
}

// MARK: - External mood resolution

// The prefill rule for State of Mind reads: an explicit daily-mood entry is
// the person's own summary and always wins; without one, the day's momentary
// emotions (what the watch's built-in tracker usually logs) average into an
// estimate.
@Suite("HealthKitService – resolveExternalMood")
struct ExternalMoodResolutionTests {

    @Test("A daily mood wins even when momentary emotions disagree")
    func dailyWins() {
        let mood = HealthKitService.resolveExternalMood(
            latestDailyValence: 1.0,           // "great day"
            momentaryValences: [-1.0, -1.0]    // two rough moments
        )
        #expect(mood == 5)
    }

    @Test("Without a daily mood, momentary emotions average")
    func momentaryAverage() {
        // 1.0 and 0.0 average to 0.5 → mood 4.
        let mood = HealthKitService.resolveExternalMood(latestDailyValence: nil, momentaryValences: [1.0, 0.0])
        #expect(mood == 4)
    }

    @Test("No entries at all → nil, so the mood step stays untouched")
    func noEntries() {
        #expect(HealthKitService.resolveExternalMood(latestDailyValence: nil, momentaryValences: []) == nil)
    }
}

// MARK: - Symptom library

// The Settings toggle list. Every library name must resolve to a HealthKit
// symptom type (that's the promise the footer makes about Health sync), and
// no entry may collide with a seeded default.
@Suite("SymptomTag – optional catalog")
struct SymptomCatalogTests {

    @Test("Every catalog entry maps to a HealthKit symptom type")
    func catalogNamesAllMapToHealth() {
        for entry in SymptomTag.optionalCatalog {
            #expect(HealthKitService.symptomTypeIdentifier(for: entry.name) != nil, "\(entry.name) has no HK mapping")
        }
    }

    @Test("No duplicates within the catalog or against the defaults")
    func catalogHasNoDuplicates() {
        let names = SymptomTag.optionalCatalog.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
        let defaultNames = Set(SymptomTag.defaultSeeds.map { $0.name.lowercased() })
        #expect(defaultNames.isDisjoint(with: names))
    }
}

// The seeded defaults used to be a `static let` array of @Model INSTANCES: one
// process-wide set of objects that seeding inserted into a context, and that
// HealthKitService then read off the main actor. Seeds are plain values now, and
// every seeding call must get its own models.
@Suite("SymptomTag – default seeds")
struct SymptomDefaultSeedTests {

    @Test("makeDefaults builds new instances on every call")
    func makeDefaults_returnsFreshInstances() {
        let first = SymptomTag.makeDefaults()
        let second = SymptomTag.makeDefaults()
        #expect(first.count == second.count)
        #expect(zip(first, second).allSatisfy { $0 !== $1 })
    }

    @Test("makeDefaults mirrors defaultSeeds in order, flagged as defaults")
    func makeDefaults_mirrorsSeeds() {
        let tags = SymptomTag.makeDefaults()
        #expect(tags.map(\.name) == SymptomTag.defaultSeeds.map(\.name))
        #expect(tags.map(\.emoji) == SymptomTag.defaultSeeds.map(\.emoji))
        #expect(tags.map(\.sortOrder) == Array(tags.indices))
        // Bound first: #expect decomposes a direct `allSatisfy(\.isDefault)` call
        // and types the key-path argument as a throwing function.
        let allFlaggedDefault = tags.allSatisfy { $0.isDefault }
        #expect(allFlaggedDefault)
    }
}

// MARK: - Week reflection prompt

// The pure prompt builder behind the on-device weekly summary. The model call
// itself needs Apple Intelligence hardware; these pin what we feed it and the
// guardrails in the instructions.
@Suite("WeekReflectionService – prompt building")
struct WeekReflectionPromptTests {

    @Test("A thin week (fewer than 2 logged days) yields no prompt")
    func thinWeekYieldsNil() {
        let logs = [DailyLogSnapshot(date: .now, mood: 4)]
        #expect(WeekReflectionService.promptText(from: logs) == nil)
    }

    @Test("The prompt carries metrics, symptoms, and the user's own words")
    func promptCarriesEntries() throws {
        let cal = Calendar.current
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -2, to: .now)!, mood: 2, energy: 3,
                             symptoms: [SymptomEntry(name: "Headache", severity: 7, emoji: "🤕")],
                             factors: ["Travel"],
                             didEditMetrics: true, didEditMood: true,
                             peaksAndValleysNote: "rough flight home"),
            DailyLogSnapshot(date: .now, mood: 4, energy: 7,
                             didEditMetrics: true, didEditMood: true, freeNote: "felt like myself again"),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs))
        #expect(prompt.contains("mood 2/5"))
        #expect(prompt.contains("Headache 7/10"))
        #expect(prompt.contains("Travel"))
        #expect(prompt.contains("rough flight home"))
        #expect(prompt.contains("felt like myself again"))
    }

    @Test("Long notes are truncated to keep the prompt bounded")
    func longNotesTruncate() throws {
        let cal = Calendar.current
        let longNote = String(repeating: "a", count: 1000)
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -1, to: .now)!, freeNote: longNote),
            DailyLogSnapshot(date: .now, mood: 4, didEditMood: true),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs))
        #expect(!prompt.contains(longNote))
        #expect(prompt.contains(String(repeating: "a", count: WeekReflectionService.noteCharacterLimit) + "…"))
    }

    // The instructions are built per week now, so this replaces the old test that
    // read them as a constant.
    @Test("The instructions pin the no-advice, no-diagnosis guardrails")
    func instructions_keepGuardrails() {
        let text = WeekReflectionService.instructions(hasMood: true, dayCount: 4, strings: .current)
        #expect(text.contains("never give advice"))
        #expect(text.contains("never diagnose"))
        #expect(text.contains("never invent facts"))
        #expect(text.contains("don't call energy or sleep low or high"))
    }

    @Test("A thin week asks for fewer sentences than a full one")
    func sentenceRange_followsDayCount() {
        let thin = WeekReflectionService.instructions(hasMood: true, dayCount: 2, strings: .current)
        let full = WeekReflectionService.instructions(hasMood: true, dayCount: 5, strings: .current)
        #expect(thin.contains("2 to 3 sentences"))
        #expect(full.contains("3 to 5 sentences"))
    }

    // Without a mood to describe, the mood rule makes the model invent one —
    // "the mood was headache" appeared in 2 of 3 runs during evaluation.
    @Test("The mood rule appears only when the week has a mood")
    func moodRule_onlyWhenMoodLogged() {
        let withMood = WeekReflectionService.instructions(hasMood: true, dayCount: 3, strings: .current)
        let without = WeekReflectionService.instructions(hasMood: false, dayCount: 3, strings: .current)
        #expect(withMood.contains("mood word"))
        #expect(!without.contains("mood word"))
    }

    @Test("hasMood reflects whether any day recorded a mood")
    func hasMood_readsEditFlags() {
        let logged = [DailyLogSnapshot(date: .now, mood: 4, didEditMood: true)]
        let notLogged = [DailyLogSnapshot(date: .now, mood: 3, didEditMood: false)]
        #expect(WeekReflectionService.hasMood(in: logged))
        #expect(!WeekReflectionService.hasMood(in: notLogged))
    }

    // DailyLog defaults mood to 3, energy to 5 and sleep to 7h. The old builder
    // passed those defaults on as if the user had entered them: a week whose note
    // said "forgot to fill most of this in" came back as "a mood of 3/5, energy
    // at 5/10, sleep at 7.0h" in 3 of 3 runs.
    @Test("Ratings the user never entered stay out of the prompt")
    func uneditedMetrics_areOmitted() throws {
        let cal = Calendar.current
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -2, to: .now)!, mood: 3, energy: 5, sleepHours: 7,
                             symptoms: [SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")],
                             didEditMetrics: false, didEditMood: false),
            DailyLogSnapshot(date: .now, mood: 3, energy: 5, sleepHours: 7,
                             didEditMetrics: false, didEditMood: false, freeNote: "busy day"),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs))
        #expect(!prompt.contains("mood"))
        #expect(!prompt.contains("energy"))
        #expect(!prompt.contains("sleep"))
        #expect(prompt.contains("Headache 6/10"))
        #expect(prompt.contains("busy day"))
    }

    // Without the word, the model called a 3/5 mood "low".
    @Test("A logged mood carries the app's own word")
    func mood_carriesWord() throws {
        let cal = Calendar.current
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -1, to: .now)!, mood: 3, energy: 5, sleepHours: 7,
                             didEditMetrics: true, didEditMood: true),
            DailyLogSnapshot(date: .now, mood: 5, energy: 6, sleepHours: 7, didEditMetrics: true, didEditMood: true),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs))
        #expect(prompt.contains("mood 3/5 (neutral)"))
        #expect(prompt.contains("mood 5/5 (very happy)"))
    }

    // The model read a 6 → 5 → 3 week as "joint pain increasing slightly" in 2 of
    // 3 runs, so direction is computed here and stated in words.
    @Test("The prompt states each trend's direction in words")
    func prompt_carriesTrendLines() throws {
        let cal = Calendar.current
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -2, to: .now)!, mood: 3, energy: 4, sleepHours: 6.5,
                             symptoms: [SymptomEntry(name: "Joint pain", severity: 6, emoji: "🦴")],
                             didEditMetrics: true, didEditMood: true),
            DailyLogSnapshot(date: .now, mood: 4, energy: 6, sleepHours: 7.5,
                             symptoms: [SymptomEntry(name: "Joint pain", severity: 3, emoji: "🦴")],
                             didEditMetrics: true, didEditMood: true),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs))
        #expect(prompt.contains("Over the week:"))
        #expect(prompt.contains("Mood rose."))
        #expect(prompt.contains("Energy rose."))
        #expect(prompt.contains("Joint pain eased."))
    }

    @Test("Spanish wording produces a Spanish prompt")
    func spanishStrings_produceSpanishPrompt() throws {
        let spanish = ReflectionStrings(
            instructionsBody: "Resume mi semana en %@.", sentenceRange: "de %1$lld a %2$lld frases",
            moodRule: "Describe el ánimo con la palabra dada.",
            header: "Estas son mis entradas del diario de esta semana:", closing: "Por favor, resume mi semana.",
            trendHeader: "A lo largo de la semana:", moodLabel: "ánimo", energyLabel: "energía", sleepLabel: "sueño",
            symptomsLabel: "síntomas", factorsLabel: "factores", peaksLabel: "altibajos", noteLabel: "nota",
            intentionsLabel: "intenciones",
            moodWords: [1: "muy triste", 2: "triste", 3: "neutral", 4: "feliz", 5: "muy feliz"],
            moodName: "El ánimo", energyName: "La energía", rose: "subió", dipped: "bajó",
            eased: "se alivió", gotStronger: "se intensificó", heldSteady: "se mantuvo estable")
        let cal = Calendar.current
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -1, to: .now)!, mood: 2, energy: 3, sleepHours: 6,
                             didEditMetrics: true, didEditMood: true),
            DailyLogSnapshot(date: .now, mood: 4, energy: 6, sleepHours: 7, didEditMetrics: true, didEditMood: true),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs, strings: spanish,
                                                                  locale: Locale(identifier: "es_ES")))
        #expect(prompt.contains("ánimo 2/5 (triste)"))
        #expect(prompt.contains("El ánimo subió."))
        #expect(prompt.hasSuffix("Por favor, resume mi semana."))
    }

    @Test("A week of empty logs yields no prompt")
    func emptyDays_yieldNoPrompt() {
        let cal = Calendar.current
        let logs = [
            DailyLogSnapshot(date: cal.date(byAdding: .day, value: -1, to: .now)!, didEditMetrics: false, didEditMood: false),
            DailyLogSnapshot(date: .now, didEditMetrics: false, didEditMood: false),
        ]
        #expect(WeekReflectionService.promptText(from: logs) == nil)
    }
}

// The direction of every change is decided in Swift, never by the model.
@Suite("WeekReflectionService – trend verbs")
struct ReflectionTrendTests {

    @Test("Ratings use rose, dipped, or held steady")
    func ratingVerbs() {
        let s = ReflectionStrings.current
        #expect(WeekReflectionService.trendVerb([2, 4], higherIsWorse: false, strings: s) == "rose")
        #expect(WeekReflectionService.trendVerb([4, 2], higherIsWorse: false, strings: s) == "dipped")
        #expect(WeekReflectionService.trendVerb([3, 5, 3], higherIsWorse: false, strings: s) == "held steady")
    }

    @Test("Symptoms use eased or got stronger, with severity inverted")
    func symptomVerbs() {
        let s = ReflectionStrings.current
        #expect(WeekReflectionService.trendVerb([6, 3], higherIsWorse: true, strings: s) == "eased")
        #expect(WeekReflectionService.trendVerb([3, 6], higherIsWorse: true, strings: s) == "got stronger")
    }

    @Test("A single reading has no direction")
    func singleValue_hasNoVerb() {
        let s = ReflectionStrings.current
        #expect(WeekReflectionService.trendVerb([4], higherIsWorse: false, strings: s) == nil)
        #expect(WeekReflectionService.trendVerb([], higherIsWorse: true, strings: s) == nil)
    }
}

// The card renders the model's text verbatim, so anything it formats must come
// off: markdown appeared in 3 of 27 runs during evaluation and would have shown
// as literal asterisks.
@Suite("WeekReflectionService – sanitize")
struct ReflectionSanitizeTests {

    @Test("Markdown emphasis and code marks are removed")
    func stripsMarkdown() {
        #expect(WeekReflectionService.sanitize("You felt **sad** on Monday.") == "You felt sad on Monday.")
        #expect(WeekReflectionService.sanitize("__Tuesday__ was `quiet`.") == "Tuesday was quiet.")
    }

    @Test("Headings lose their hashes")
    func stripsHeadings() {
        #expect(WeekReflectionService.sanitize("## Your week\nYou rested.") == "Your week You rested.")
    }

    @Test("Whitespace collapses and edges are trimmed")
    func collapsesWhitespace() {
        #expect(WeekReflectionService.sanitize("  You slept\n\n   more.  ") == "You slept more.")
    }

    @Test("Ordinary prose is untouched")
    func leavesPlainTextAlone() {
        let text = "You felt happy on Monday. Your energy rose."
        #expect(WeekReflectionService.sanitize(text) == text)
    }
}

// MARK: - Crisis language

// The on-device model summarized "had thoughts of hurting myself last night"
// back like any other entry on iOS 27 — no guardrail error, no refusal. This
// check is the app's own layer, and it is deliberately a fixed phrase list:
// explainable, offline, and stable across OS versions.
@Suite("CrisisLanguage – phrase matching")
struct CrisisLanguageTests {

    @Test("Explicit English self-harm language matches")
    func englishPhrases_match() {
        #expect(CrisisLanguage.matches(in: ["had thoughts of hurting myself last night"]))
        #expect(CrisisLanguage.matches(in: ["I want to die"]))
        #expect(CrisisLanguage.matches(in: ["", "everyone would be better off dead"]))
    }

    @Test("Explicit Spanish self-harm language matches, accented or not")
    func spanishPhrases_match() {
        #expect(CrisisLanguage.matches(in: ["pensé en hacerme daño"]))
        #expect(CrisisLanguage.matches(in: ["pense en hacerme dano"]))
        #expect(CrisisLanguage.matches(in: ["no quiero vivir así"]))
    }

    @Test("A curly apostrophe still matches")
    func curlyApostrophe_matches() {
        #expect(CrisisLanguage.matches(in: ["I don\u{2019}t want to be here"]))
    }

    @Test("Ordinary hard weeks do not match")
    func generalDistress_doesNotMatch() {
        #expect(!CrisisLanguage.matches(in: ["felt hopeless most of the day"]))
        #expect(!CrisisLanguage.matches(in: ["couldn't get out of bed, cried a lot"]))
        #expect(!CrisisLanguage.matches(in: ["hurt my back lifting boxes"]))
        #expect(!CrisisLanguage.matches(in: []))
    }

    // Accepted by design: over-matching shows support, which is the safer error.
    @Test("An innocent phrasing that still matches is accepted")
    func acceptedFalsePositive() {
        #expect(CrisisLanguage.matches(in: ["hurt myself at the gym"]))
    }
}

@Suite("CrisisSupport – resources by region")
struct CrisisSupportTests {

    @Test("US gets the 988 Lifeline, with the Spanish chat in Spanish")
    func unitedStates_gets988() {
        #expect(CrisisSupport.resources(region: "US", isSpanish: false) == .lifeline988(chatURL: "https://chat.988lifeline.org/"))
        #expect(CrisisSupport.resources(region: "US", isSpanish: true) == .lifeline988(chatURL: "https://chat.988lifeline.org/?lang=es"))
    }

    @Test("Other regions get their Find A Helpline country page")
    func otherRegion_getsCountryDirectory() {
        #expect(CrisisSupport.resources(region: "ES", isSpanish: true) == .findAHelpline(directoryURL: "https://findahelpline.com/countries/es"))
        #expect(CrisisSupport.resources(region: "GB", isSpanish: false) == .findAHelpline(directoryURL: "https://findahelpline.com/countries/gb"))
    }

    @Test("An unknown or malformed region falls back to the directory root")
    func unknownRegion_fallsBackToRoot() {
        #expect(CrisisSupport.resources(region: nil, isSpanish: false) == .findAHelpline(directoryURL: "https://findahelpline.com"))
        #expect(CrisisSupport.resources(region: "419", isSpanish: false) == .findAHelpline(directoryURL: "https://findahelpline.com"))
    }
}
