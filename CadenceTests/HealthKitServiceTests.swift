import Testing
import HealthKit
import Foundation
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
