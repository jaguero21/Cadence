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

    private func makeContext() throws -> ModelContext {
        let schema = Schema([DailyLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test("Updates only objective fields on an existing today log")
    func updatesExistingLog() throws {
        let context = try makeContext()
        let log = DailyLog(date: .now)
        log.mood = 4
        log.hkSteps = 1200   // morning value
        context.insert(log)
        try context.save()

        let updated = HealthDataRefresher.refreshToday(
            context: context,
            snapshot: HealthKitSnapshot(steps: 9800, activeEnergy: 300, workoutMinutes: 52)
        )

        #expect(updated)
        #expect(log.hkSteps == 9800)          // topped up
        #expect(log.hkActiveEnergy == 300)
        #expect(log.hkWorkoutMinutes == 52)   // evening workout lands on the morning log
        #expect(log.mood == 4)                // user data untouched
    }

    @Test("Never creates a log for a day the user didn't start")
    func neverCreatesLog() throws {
        let context = try makeContext()

        let updated = HealthDataRefresher.refreshToday(
            context: context,
            snapshot: HealthKitSnapshot(steps: 9800)
        )

        #expect(updated == false)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).isEmpty)
    }

    @Test("A nil snapshot value never blanks an earlier measurement")
    func nilNeverBlanks() throws {
        let context = try makeContext()
        let log = DailyLog(date: .now)
        log.hkWristTemp = 35.1
        context.insert(log)
        try context.save()

        HealthDataRefresher.refreshToday(context: context, snapshot: HealthKitSnapshot(steps: 500))

        #expect(log.hkWristTemp == 35.1)
        #expect(log.hkSteps == 500)
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
        let defaultNames = Set(SymptomTag.defaults.map { $0.name.lowercased() })
        #expect(defaultNames.isDisjoint(with: names))
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
                             peaksAndValleysNote: "rough flight home"),
            DailyLogSnapshot(date: .now, mood: 4, energy: 7, freeNote: "felt like myself again"),
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
            DailyLogSnapshot(date: .now),
        ]
        let prompt = try #require(WeekReflectionService.promptText(from: logs))
        #expect(!prompt.contains(longNote))
        #expect(prompt.contains(String(repeating: "a", count: WeekReflectionService.noteCharacterLimit) + "…"))
    }

    @Test("The instructions pin the no-advice, no-diagnosis guardrails")
    func instructionsCarryGuardrails() {
        let instructions = WeekReflectionService.instructions
        #expect(instructions.contains("never give advice"))
        #expect(instructions.contains("never diagnose"))
        #expect(instructions.contains("never invent facts"))
    }
}
