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
    // - Steps, active energy, and mindful minutes from today (daytime activity
    //   logged so far)
    // - Resting HR, HRV, and sleep from yesterday (overnight metrics)
    // Every type in readTypes is fetched here — requesting permission for a
    // type this snapshot never reads would be a broken promise to the user.
    func fetchLogSnapshot() async -> HealthKitSnapshot {
        guard isAuthorized else { return HealthKitSnapshot() }
        let cal = Calendar.current
        let todayStart    = cal.startOfDay(for: .now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let todayPredicate     = HKQuery.predicateForSamples(withStart: todayStart, end: .now)
        let yesterdayPredicate = HKQuery.predicateForSamples(withStart: yesterdayStart, end: todayStart)

        async let steps   = fetchSum(.stepCount, unit: .count(), predicate: todayPredicate)
        async let energy  = fetchSum(.activeEnergyBurned, unit: .kilocalorie(), predicate: todayPredicate)
        async let mindful = fetchDurationMinutes(.mindfulSession, predicate: todayPredicate)
        async let hr    = fetchLatest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: yesterdayPredicate)
        async let hrv   = fetchLatest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: yesterdayPredicate)
        async let sleep = fetchSleepDetail(start: yesterdayStart, end: todayStart)

        let sleepDetail = await sleep
        return await HealthKitSnapshot(
            steps: steps.map(Int.init),
            restingHR: hr,
            hrv: hrv,
            sleepHours: sleepDetail.hours,
            activeEnergy: energy,
            mindfulMinutes: mindful,
            sleepQuality: sleepDetail.quality
        )
    }

    // Derives a 0–10 sleep-quality score from stage totals. Returns nil unless
    // the night has real stage data (core/REM/deep) — duration-only sources
    // (manual entry, basic trackers) can't support a quality claim, and the
    // slider should stay at its default rather than show a made-up number.
    // Score = 60% sleep efficiency (asleep vs awake within the night) + 40%
    // restorative share (deep+REM as a fraction of sleep, normalised against
    // a typical ~45%).
    nonisolated static func sleepQualityScore(
        asleepSeconds: Double,
        awakeSeconds: Double,
        deepSeconds: Double,
        remSeconds: Double,
        stagedSeconds: Double
    ) -> Int? {
        guard asleepSeconds > 0, stagedSeconds > 0 else { return nil }
        let efficiency = asleepSeconds / (asleepSeconds + awakeSeconds)
        let restorative = min(((deepSeconds + remSeconds) / asleepSeconds) / 0.45, 1.0)
        let score = (10 * (0.6 * efficiency + 0.4 * restorative)).rounded()
        return Int(score).clamped(to: 0...10)
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

    // Sums the duration of category samples (e.g. mindful sessions) in minutes.
    // Returns nil rather than 0 when there are no samples, so callers can
    // distinguish "no data" from a genuine zero.
    nonisolated private func fetchDurationMinutes(_ id: HKCategoryTypeIdentifier, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { Self.log.error("fetchDurationMinutes(\(id.rawValue, privacy: .public)) failed: \(error, privacy: .public)") }
                guard error == nil, let samples else { cont.resume(returning: nil); return }
                let seconds = samples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: seconds > 0 ? seconds / 60 : nil)
            }
            store.execute(query)
        }
    }

    // One query for the night's sleep: total asleep hours plus a derived 0–10
    // quality score (nil for either when the data can't support it — see
    // sleepQualityScore).
    nonisolated private func fetchSleepDetail(start: Date, end: Date) async -> (hours: Double?, quality: Int?) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return (nil, nil) }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { Self.log.error("fetchSleepDetail failed: \(error, privacy: .public)") }
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: (nil, nil)); return
                }
                func seconds(of value: HKCategoryValueSleepAnalysis) -> Double {
                    samples.filter { $0.value == value.rawValue }
                        .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                }
                // .asleepUnspecified covers legacy .asleep (same raw value, renamed iOS 16).
                let unspecified = seconds(of: .asleepUnspecified)
                let core  = seconds(of: .asleepCore)
                let rem   = seconds(of: .asleepREM)
                let deep  = seconds(of: .asleepDeep)
                let awake = seconds(of: .awake)
                let asleep = unspecified + core + rem + deep
                // Return nil rather than 0 when no qualifying sleep stages were recorded,
                // so callers can distinguish "no data" from a genuine zero.
                let hours: Double? = asleep > 0 ? asleep / 3600 : nil
                let quality = HealthKitService.sleepQualityScore(
                    asleepSeconds: asleep,
                    awakeSeconds: awake,
                    deepSeconds: deep,
                    remSeconds: rem,
                    stagedSeconds: core + rem + deep
                )
                cont.resume(returning: (hours, quality))
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
    var activeEnergy: Double?     // kcal, today's sum
    var mindfulMinutes: Double?   // minutes, today's sessions
    var sleepQuality: Int?        // 0–10, derived from sleep stages; nil without stage data
}
