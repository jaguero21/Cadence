import HealthKit
import SwiftData
import UIKit
import OSLog

@MainActor
final class HealthKitService: HealthKitServiceProtocol {
    static let shared = HealthKitService()
    private let store = HKHealthStore()
    private var foregroundObserver: NSObjectProtocol?
    nonisolated private static let log = Logger(subsystem: "com.carpecadence", category: "HealthKit")

    private init() {
        // .main queue ensures the callback fires on the main thread; the
        // assumeIsolated hop tells the compiler this @MainActor instance
        // is safe to mutate here without an async hop.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cachedIsAuthorized = nil
            }
        }
    }

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // HealthKit does not reveal granted read status (.notDetermined covers both "not asked" and
    // "granted"). We return false only when the user has explicitly denied at least one type
    // (.sharingDenied), which is the strongest signal HealthKit exposes for read-only requests.
    // Cached because this iterates all readTypes on every call; invalidated after requestAuthorization
    // and on app foreground (the user may have toggled permissions in Settings).
    private var cachedIsAuthorized: Bool?
    var isAuthorized: Bool {
        if let cached = cachedIsAuthorized { return cached }
        guard isAvailable else { cachedIsAuthorized = false; return false }
        let result = !readTypes.contains { store.authorizationStatus(for: $0) == .sharingDenied }
        cachedIsAuthorized = result
        return result
    }

    private let readTypes: Set<HKObjectType> = {
        let quantity: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .stepCount, .activeEnergyBurned,
        ]
        let category: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis, .mindfulSession,
        ]
        let quantityTypes = quantity.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        let categoryTypes = category.compactMap { HKObjectType.categoryType(forIdentifier: $0) }
        return Set(quantityTypes + categoryTypes)
    }()

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        guard isAvailable else { return false }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        cachedIsAuthorized = nil   // authorization status may have changed; re-evaluate
        return isAuthorized
    }

    // Fetches the right HealthKit data for today's daily log:
    // - Steps from today (daytime activity logged so far)
    // - Resting HR, HRV, and sleep from yesterday (overnight metrics)
    func fetchLogSnapshot() async -> HealthKitSnapshot {
        guard isAuthorized else { return HealthKitSnapshot() }
        let cal = Calendar.current
        let todayStart    = cal.startOfDay(for: .now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let todayPredicate     = HKQuery.predicateForSamples(withStart: todayStart, end: .now)
        let yesterdayPredicate = HKQuery.predicateForSamples(withStart: yesterdayStart, end: todayStart)

        async let steps = fetchSum(.stepCount, unit: .count(), predicate: todayPredicate)
        async let hr    = fetchLatest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: yesterdayPredicate)
        async let hrv   = fetchLatest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: yesterdayPredicate)
        async let sleep = fetchSleepHours(start: yesterdayStart, end: todayStart)

        return await HealthKitSnapshot(steps: steps.map(Int.init), restingHR: hr, hrv: hrv, sleepHours: sleep)
    }

    // MARK: - Private helpers
    //
    // These are nonisolated because they execute HKQuery callbacks on HealthKit's
    // internal queue and don't touch any @MainActor state. Marking them
    // nonisolated avoids unnecessary main-thread hops while results are pending.

    nonisolated private func fetchSum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { Self.log.error("fetchSum(\(id.rawValue, privacy: .public)) failed: \(error, privacy: .public)") }
                guard error == nil else { cont.resume(returning: nil); return }
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    nonisolated private func fetchLatest(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { Self.log.error("fetchLatest(\(id.rawValue, privacy: .public)) failed: \(error, privacy: .public)") }
                guard error == nil else { cont.resume(returning: nil); return }
                let qty = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: qty)
            }
            store.execute(query)
        }
    }

    nonisolated private func fetchSleepHours(start: Date, end: Date) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { Self.log.error("fetchSleepHours failed: \(error, privacy: .public)") }
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil); return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,  // covers legacy .asleep (same raw value, renamed iOS 16)
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                ]
                let seconds = samples.filter { asleepValues.contains($0.value) }
                    .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                // Return nil rather than 0 when no qualifying sleep stages were recorded,
                // so callers can distinguish "no data" from a genuine zero.
                cont.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
}

struct HealthKitSnapshot {
    var steps: Int?
    var restingHR: Double?
    var hrv: Double?
    var sleepHours: Double?
}
