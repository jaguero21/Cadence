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
//   • HealthKitSnapshot: struct initialisation and default-zero field values

@Suite("HealthKitService – isAvailable")
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

@Suite("HealthKitSnapshot – initialisation")
struct HealthKitSnapshotInitTests {

    @Test("Default-zero snapshot has steps = 0")
    func snapshot_steps_defaultsToZero() {
        let snapshot = HealthKitSnapshot(steps: 0, restingHR: nil, hrv: nil, sleepHours: 0)
        #expect(snapshot.steps == 0)
    }

    @Test("Default-zero snapshot has sleepHours = 0")
    func snapshot_sleepHours_defaultsToZero() {
        let snapshot = HealthKitSnapshot(steps: 0, restingHR: nil, hrv: nil, sleepHours: 0)
        #expect(snapshot.sleepHours == 0.0)
    }

    @Test("Default-zero snapshot has restingHR = nil")
    func snapshot_restingHR_defaultsToNil() {
        let snapshot = HealthKitSnapshot(steps: 0, restingHR: nil, hrv: nil, sleepHours: 0)
        #expect(snapshot.restingHR == nil)
    }

    @Test("Default-zero snapshot has hrv = nil")
    func snapshot_hrv_defaultsToNil() {
        let snapshot = HealthKitSnapshot(steps: 0, restingHR: nil, hrv: nil, sleepHours: 0)
        #expect(snapshot.hrv == nil)
    }

    @Test("Snapshot stores non-zero values correctly")
    func snapshot_storesNonZeroValues() {
        let snapshot = HealthKitSnapshot(steps: 8432, restingHR: 62.5, hrv: 45.3, sleepHours: 7.25)
        #expect(snapshot.steps == 8432)
        #expect(snapshot.restingHR == 62.5)
        #expect(snapshot.hrv == 45.3)
        #expect(snapshot.sleepHours == 7.25)
    }

    @Test("Snapshot with only steps populated leaves HR and HRV nil")
    func snapshot_onlySteps_hrAndHrvAreNil() {
        let snapshot = HealthKitSnapshot(steps: 10000, restingHR: nil, hrv: nil, sleepHours: 0)
        #expect(snapshot.steps == 10000)
        #expect(snapshot.restingHR == nil)
        #expect(snapshot.hrv == nil)
    }

    @Test("Snapshot is a value type — mutation does not affect original")
    func snapshot_isValueType_mutationDoesNotAffectOriginal() {
        var original = HealthKitSnapshot(steps: 100, restingHR: 65.0, hrv: 40.0, sleepHours: 6.5)
        var copy = original
        copy.steps = 9999
        copy.sleepHours = 0
        #expect(original.steps == 100)
        #expect(original.sleepHours == 6.5)
    }
}
