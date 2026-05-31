import HealthKit
import SwiftData

final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()
    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // HealthKit does not reveal granted read status (.notDetermined covers both "not asked" and
    // "granted"). We return false only when the user has explicitly denied at least one type
    // (.sharingDenied), which is the strongest signal HealthKit exposes for read-only requests.
    var isAuthorized: Bool {
        guard isAvailable else { return false }
        return !readTypes.contains { store.authorizationStatus(for: $0) == .sharingDenied }
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

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchYesterdayData() async -> HealthKitSnapshot {
        guard
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now),
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: yesterday))
        else { return HealthKitSnapshot(steps: 0, restingHR: nil, hrv: nil, sleepHours: 0) }
        let start = Calendar.current.startOfDay(for: yesterday)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        async let steps = fetchSum(.stepCount, unit: .count(), predicate: predicate)
        async let hr    = fetchLatest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: predicate)
        async let hrv   = fetchLatest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: predicate)
        async let sleep = fetchSleepHours(start: start, end: end)

        return await HealthKitSnapshot(steps: Int(steps ?? 0), restingHR: hr, hrv: hrv, sleepHours: sleep)
    }

    @MainActor
    func populate(log: DailyLog) async {
        let snapshot = await fetchYesterdayData()
        if snapshot.steps > 0          { log.hkSteps      = snapshot.steps }
        if let hr  = snapshot.restingHR { log.hkRestingHR  = hr }
        if let hrv = snapshot.hrv       { log.hkHRV        = hrv }
        if snapshot.sleepHours > 0 {
            log.hkSleepHours = snapshot.sleepHours
            log.sleepHours   = snapshot.sleepHours
        }
    }

    // MARK: - Private helpers

    private func fetchSum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchLatest(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let qty = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: qty)
            }
            store.execute(query)
        }
    }

    private func fetchSleepHours(start: Date, end: Date) async -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let hours = (samples as? [HKCategorySample])?.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
                cont.resume(returning: hours / 3600)
            }
            store.execute(query)
        }
    }
}

struct HealthKitSnapshot {
    var steps: Int
    var restingHR: Double?
    var hrv: Double?
    var sleepHours: Double
}
