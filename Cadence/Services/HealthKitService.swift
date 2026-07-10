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
            .appleSleepingWristTemperature, .respiratoryRate, .oxygenSaturation,
            .timeInDaylight, .dietaryCaffeine, .dietaryWater,
        ]
        let category: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis, .mindfulSession, .menstrualFlow,
        ]
        let quantityTypes = quantity.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        let categoryTypes = category.compactMap { HKObjectType.categoryType(forIdentifier: $0) }
        // Symptoms are read AND written (see shareTypes); reading lets a
        // symptom logged in another Health-connected app prefill Cadence.
        let symptomTypes = Set(HealthKitService.symptomTypeByName.values).compactMap { HKObjectType.categoryType(forIdentifier: $0) }
        var types = Set(quantityTypes + categoryTypes + symptomTypes)
        types.insert(HKObjectType.workoutType())
        if #available(iOS 18.0, *) {
            types.insert(HKObjectType.stateOfMindType())
        }
        return types
    }()

    // What Cadence writes back to Health: the day's symptoms and (iOS 18+) the
    // daily mood as State of Mind. Writing is a courtesy to the user's health
    // record — a denied share permission never blocks logging in Cadence.
    private let shareTypes: Set<HKSampleType> = {
        var types = Set(Set(HealthKitService.symptomTypeByName.values).compactMap { HKObjectType.categoryType(forIdentifier: $0) as HKSampleType? })
        if #available(iOS 18.0, *) {
            types.insert(HKObjectType.stateOfMindType())
        }
        return types
    }()

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        guard isAvailable else { return false }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        cachedIsAuthorized = nil   // authorization status may have changed; re-evaluate
        return isAuthorized
    }

    // Fetches the right HealthKit data for today's daily log:
    // - Steps, active energy, mindful minutes, and menstrual flow from today
    // - Resting HR and HRV from yesterday (daily aggregates)
    // - Sleep and wrist temperature from LAST NIGHT: 6pm yesterday → now, so
    //   the post-midnight bulk of a normal night is included (a window that
    //   ends at midnight silently drops most of it)
    // Every type in readTypes is fetched here — requesting permission for a
    // type this snapshot never reads would be a broken promise to the user.
    func fetchLogSnapshot() async -> HealthKitSnapshot {
        guard isAuthorized else { return HealthKitSnapshot() }
        let cal = Calendar.current
        let todayStart    = cal.startOfDay(for: .now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let lastNightStart = cal.date(byAdding: .hour, value: 18, to: yesterdayStart) ?? yesterdayStart
        let todayPredicate     = HKQuery.predicateForSamples(withStart: todayStart, end: .now)
        let yesterdayPredicate = HKQuery.predicateForSamples(withStart: yesterdayStart, end: todayStart)
        let nightPredicate     = HKQuery.predicateForSamples(withStart: lastNightStart, end: .now)

        async let steps   = fetchSum(.stepCount, unit: .count(), predicate: todayPredicate)
        async let energy  = fetchSum(.activeEnergyBurned, unit: .kilocalorie(), predicate: todayPredicate)
        async let mindful = fetchDurationMinutes(.mindfulSession, predicate: todayPredicate)
        async let flow    = fetchHasMenstrualFlow(predicate: todayPredicate)
        async let hr    = fetchLatest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: yesterdayPredicate)
        async let hrv   = fetchLatest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: yesterdayPredicate)
        async let temp  = fetchAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), predicate: nightPredicate)
        async let sleep = fetchSleepDetail(start: lastNightStart, end: .now)
        async let symptoms = fetchExternalSymptoms(start: todayStart, end: .now)
        async let mood = fetchExternalDailyMood(start: todayStart, end: .now)
        async let workout = fetchHadIntenseWorkout(predicate: todayPredicate)
        async let respiratory = fetchAverage(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: nightPredicate)
        async let spo2 = fetchAverage(.oxygenSaturation, unit: .percent(), predicate: nightPredicate)
        async let daylight = fetchSum(.timeInDaylight, unit: .minute(), predicate: todayPredicate)
        async let caffeine = fetchSum(.dietaryCaffeine, unit: .gramUnit(with: .milli), predicate: todayPredicate)
        async let water = fetchSum(.dietaryWater, unit: .liter(), predicate: todayPredicate)

        let sleepDetail = await sleep
        return await HealthKitSnapshot(
            steps: steps.map(Int.init),
            restingHR: hr,
            hrv: hrv,
            sleepHours: sleepDetail.hours,
            activeEnergy: energy,
            mindfulMinutes: mindful,
            sleepQuality: sleepDetail.quality,
            wristTemperature: temp,
            menstrualFlow: flow,
            symptoms: symptoms,
            mood: mood,
            intenseWorkout: workout,
            respiratoryRate: respiratory,
            bloodOxygen: spo2.map { $0 * 100 },   // HK .percent() is 0–1; store 0–100
            daylightMinutes: daylight,
            caffeineMilligrams: caffeine,
            waterLiters: water
        )
    }

    // MARK: - Change observation (background delivery)

    private var observerQueries: [HKObserverQuery] = []
    private var refreshDebounce: Task<Void, Never>?

    // Observes the types whose values accumulate through the day (steps,
    // energy, daylight) or land after the log was created (sleep, wrist temp)
    // and calls `onChange` — debounced, since HealthKit fires observers in
    // bursts. Background delivery wakes the app when suspended (entitlement:
    // com.apple.developer.healthkit.background-delivery); while running, the
    // observers fire directly. Purely additive freshness — everything still
    // works without it.
    func startObservingChanges(onChange: @escaping @Sendable () async -> Void) {
        guard isAvailable, observerQueries.isEmpty else { return }
        let quantity: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .timeInDaylight, .appleSleepingWristTemperature,
        ]
        var types: [HKSampleType] = quantity.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.append(sleep)
        }
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    Self.log.error("Observer for \(type.identifier, privacy: .public) failed: \(error, privacy: .public)")
                } else {
                    Task { @MainActor in self?.scheduleRefresh(onChange) }
                }
                completionHandler()
            }
            store.execute(query)
            observerQueries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, error in
                if let error {
                    Self.log.error("enableBackgroundDelivery(\(type.identifier, privacy: .public)) failed: \(error, privacy: .public)")
                }
            }
        }
    }

    private func scheduleRefresh(_ onChange: @escaping @Sendable () async -> Void) {
        refreshDebounce?.cancel()
        refreshDebounce = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await onChange()
        }
    }

    // MARK: - Write-back (Health record sync)

    // Mirrors a saved day's log into Health: mapped symptoms as severity
    // samples, and (iOS 18+) the mood as a State of Mind daily-mood entry when
    // the user actually set one. Delete-then-write per type keeps re-saves
    // idempotent — HealthKit only ever deletes samples this app created, so
    // other apps' data is untouchable by construction. Best-effort: failures
    // are logged and swallowed; Health sync must never block or degrade
    // logging in Cadence.
    func publish(log: DailyLogSnapshot) async {
        guard isAvailable else { return }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: log.date)
        let dayEnd = min(cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart, .now)
        guard dayEnd > dayStart else { return }
        let dayPredicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)

        let entriesByType = Dictionary(
            grouping: log.symptoms.compactMap { entry in
                Self.symptomTypeIdentifier(for: entry.name).map { (id: $0, entry: entry) }
            },
            by: \.id
        )

        // Every mapped type gets the delete pass — a symptom removed in
        // Cadence must also leave the Health record.
        for identifier in Set(Self.symptomTypeByName.values) {
            guard let type = HKObjectType.categoryType(forIdentifier: identifier),
                  store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            do {
                _ = try? await store.deleteObjects(of: type, predicate: dayPredicate)
                if let worst = entriesByType[identifier]?.map(\.entry).max(by: { $0.severity < $1.severity }) {
                    let sample = HKCategorySample(
                        type: type,
                        value: Self.hkSeverityValue(forSeverity: worst.severity),
                        start: dayStart,
                        end: dayEnd
                    )
                    try await store.save(sample)
                }
            } catch {
                Self.log.error("Health symptom write-back (\(identifier.rawValue, privacy: .public)) failed: \(error, privacy: .public)")
            }
        }

        if #available(iOS 18.0, *) {
            let type = HKObjectType.stateOfMindType()
            if store.authorizationStatus(for: type) == .sharingAuthorized, log.didEditMood {
                do {
                    _ = try? await store.deleteObjects(of: type, predicate: dayPredicate)
                    let entry = HKStateOfMind(
                        date: dayEnd,
                        kind: .dailyMood,
                        valence: Self.valence(forMood: log.mood),
                        labels: [],
                        associations: []
                    )
                    try await store.save(entry)
                } catch {
                    Self.log.error("Health mood write-back failed: \(error, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Symptom & mood mapping (pure, unit-tested)

    // Cadence symptom names ↔ HealthKit symptom category types. Only honest
    // mappings — a Cadence symptom with no real HK counterpart (e.g. "Brain
    // Fog") simply doesn't sync. Keys are lowercased names. Covers every HK
    // symptom type that takes HKCategoryValueSeverity; .appetiteChanges and
    // .sleepChanges are deliberately absent — they use their own value enums,
    // and writing a severity raw value to them would be invalid data.
    nonisolated static let symptomTypeByName: [String: HKCategoryTypeIdentifier] = [
        "headache":            .headache,
        "fatigue":             .fatigue,
        "nausea":              .nausea,
        "dizziness":           .dizziness,
        "fever":               .fever,
        "coughing":            .coughing,
        "cough":               .coughing,
        "chills":              .chills,
        "bloating":            .bloating,
        "constipation":        .constipation,
        "diarrhea":            .diarrhea,
        "heartburn":           .heartburn,
        "sore throat":         .soreThroat,
        "runny nose":          .runnyNose,
        "shortness of breath": .shortnessOfBreath,
        "lower back pain":     .lowerBackPain,
        "pelvic pain":         .pelvicPain,
        "hot flashes":         .hotFlashes,
        "night sweats":        .nightSweats,
        "pain":                .generalizedBodyAche,
        "body ache":           .generalizedBodyAche,
        "abdominal cramps":    .abdominalCramps,
        "acne":                .acne,
        "bladder incontinence": .bladderIncontinence,
        "breast pain":         .breastPain,
        "chest tightness or pain": .chestTightnessOrPain,
        "dry skin":            .drySkin,
        "fainting":            .fainting,
        "hair loss":           .hairLoss,
        "loss of smell":       .lossOfSmell,
        "loss of taste":       .lossOfTaste,
        "memory lapse":        .memoryLapse,
        "mood changes":        .moodChanges,
        "racing heartbeat":    .rapidPoundingOrFlutteringHeartbeat,
        "sinus congestion":    .sinusCongestion,
        "skipped heartbeat":   .skippedHeartbeat,
        "vaginal dryness":     .vaginalDryness,
        "vomiting":            .vomiting,
        "wheezing":            .wheezing,
    ]

    nonisolated static func symptomTypeIdentifier(for name: String) -> HKCategoryTypeIdentifier? {
        symptomTypeByName[name.lowercased()]
    }

    // The reverse map for reading Health symptoms into Cadence. Where several
    // names share a type (cough/coughing, pain/body ache), the canonical
    // Cadence display name wins.
    nonisolated static func symptomName(for identifier: HKCategoryTypeIdentifier) -> String? {
        switch identifier {
        case .coughing:            return "Coughing"
        case .generalizedBodyAche: return "Pain"
        default:
            return symptomTypeByName.first { $0.value == identifier }?.key.capitalized
        }
    }

    // Cadence severity (1–10) → HKCategoryValueSeverity raw value.
    nonisolated static func hkSeverityValue(forSeverity severity: Int) -> Int {
        switch severity {
        case ..<4:  return HKCategoryValueSeverity.mild.rawValue
        case 4...7: return HKCategoryValueSeverity.moderate.rawValue
        default:    return HKCategoryValueSeverity.severe.rawValue
        }
    }

    // HKCategoryValueSeverity raw value → a representative Cadence severity.
    nonisolated static func cadenceSeverity(fromHKSeverity raw: Int) -> Int {
        switch HKCategoryValueSeverity(rawValue: raw) {
        case .mild:     return 2
        case .moderate: return 5
        case .severe:   return 9
        default:        return 5
        }
    }

    // Cadence mood (1–5) ↔ State of Mind valence (-1…1).
    nonisolated static func valence(forMood mood: Int) -> Double {
        Double(mood.clamped(to: 1...5) - 3) / 2
    }

    nonisolated static func mood(forValence valence: Double) -> Int {
        (Int((valence * 2).rounded()) + 3).clamped(to: 1...5)
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

    // Today's symptoms logged by OTHER apps/Health itself, mapped to Cadence
    // entries so the symptom picker can prefill. Our own written samples are
    // excluded — otherwise a symptom the user removed in Cadence would
    // resurrect from Health on the next open.
    nonisolated private func fetchExternalSymptoms(start: Date, end: Date) async -> [SymptomEntry] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let ownBundle = Bundle.main.bundleIdentifier
        var entries: [SymptomEntry] = []
        await withTaskGroup(of: SymptomEntry?.self) { group in
            for identifier in Set(Self.symptomTypeByName.values) {
                group.addTask { [store] in
                    guard let type = HKObjectType.categoryType(forIdentifier: identifier),
                          let name = Self.symptomName(for: identifier) else { return nil }
                    let sample: HKCategorySample? = await withCheckedContinuation { cont in
                        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                            if let error { Self.log.error("fetchExternalSymptoms(\(identifier.rawValue, privacy: .public)) failed: \(error, privacy: .public)") }
                            let external = (samples as? [HKCategorySample])?
                                .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle }
                            // Worst severity of the day wins.
                            cont.resume(returning: external?.max { $0.value < $1.value })
                        }
                        store.execute(query)
                    }
                    guard let sample else { return nil }
                    let emoji = SymptomTag.defaults.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.emoji ?? "🤒"
                    return SymptomEntry(name: name, severity: Self.cadenceSeverity(fromHKSeverity: sample.value), emoji: emoji)
                }
            }
            for await entry in group {
                if let entry { entries.append(entry) }
            }
        }
        return entries.sorted { $0.name < $1.name }
    }

    // Today's State of Mind daily mood from Health (iOS 18+), excluding our own
    // written entry, mapped back to the 1–5 scale.
    nonisolated private func fetchExternalDailyMood(start: Date, end: Date) async -> Int? {
        guard #available(iOS 18.0, *) else { return nil }
        let type = HKObjectType.stateOfMindType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let ownBundle = Bundle.main.bundleIdentifier
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { Self.log.error("fetchExternalDailyMood failed: \(error, privacy: .public)") }
                let latest = (samples as? [HKStateOfMind])?.first {
                    $0.kind == .dailyMood && $0.sourceRevision.source.bundleIdentifier != ownBundle
                }
                cont.resume(returning: latest.map { Self.mood(forValence: $0.valence) })
            }
            store.execute(query)
        }
    }

    // Average of a discrete quantity (e.g. overnight wrist temperature).
    nonisolated private func fetchAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error { Self.log.error("fetchAverage(\(id.rawValue, privacy: .public)) failed: \(error, privacy: .public)") }
                guard error == nil else { cont.resume(returning: nil); return }
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // Whether the day's workouts add up to "Intense exercise" (see
    // isIntenseExercise). nil = no workouts, so the factor chip stays untouched;
    // false is never reported for the same reason as menstrual flow below.
    nonisolated private func fetchHadIntenseWorkout(predicate: NSPredicate) async -> Bool? {
        await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { Self.log.error("fetchHadIntenseWorkout failed: \(error, privacy: .public)") }
                guard error == nil, let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let minutes = workouts.reduce(0) { $0 + $1.duration } / 60
                let kilocalories = workouts.reduce(0.0) { total, workout in
                    let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    return total + energy
                }
                cont.resume(returning: Self.isIntenseExercise(totalMinutes: minutes, totalKilocalories: kilocalories) ? true : nil)
            }
            store.execute(query)
        }
    }

    // Pure gate for the "Intense exercise" auto-factor: enough time OR enough
    // energy — a long easy hike and a short hard run both count.
    nonisolated static func isIntenseExercise(totalMinutes: Double, totalKilocalories: Double) -> Bool {
        totalMinutes >= HealthThreshold.intenseWorkoutMinutes
            || totalKilocalories >= HealthThreshold.intenseWorkoutKilocalories
    }

    // Whether any menstrual-flow sample (of any intensity) overlaps the window.
    // nil = no data (not asked / not tracked); false is never reported because
    // an absent sample can't distinguish "no flow" from "doesn't track cycles".
    nonisolated private func fetchHasMenstrualFlow(predicate: NSPredicate) async -> Bool? {
        guard let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return nil }
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { Self.log.error("fetchHasMenstrualFlow failed: \(error, privacy: .public)") }
                guard error == nil, let samples else { cont.resume(returning: nil); return }
                // Raw value 5 = "none" in both HKCategoryValueMenstrualFlow and
                // its iOS 18 rename HKCategoryValueVaginalBleeding — pinned
                // numerically because the old name is deprecated and the new
                // one needs iOS 18, while our target is iOS 17.
                let noneRawValue = 5
                let hasFlow = samples.contains {
                    ($0 as? HKCategorySample).map { $0.value != noneRawValue } ?? false
                }
                cont.resume(returning: hasFlow ? true : nil)
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

extension DailyLog {
    // Applies a snapshot's OBJECTIVE measurements to the log — hk* fields
    // only, each written only when present so a partial fetch can't blank an
    // earlier value. User-entered fields are never touched: this is safe to
    // run against an existing log long after the user finished editing it
    // (log-flow save, foreground refresh, background delivery all share it).
    func applyObjectiveHealthData(_ snapshot: HealthKitSnapshot) {
        if let steps   = snapshot.steps            { hkSteps          = steps }
        if let hr      = snapshot.restingHR        { hkRestingHR      = hr }
        if let hrv     = snapshot.hrv              { hkHRV            = hrv }
        if let sleep   = snapshot.sleepHours       { hkSleepHours     = sleep }
        if let energy  = snapshot.activeEnergy     { hkActiveEnergy   = energy }
        if let mindful = snapshot.mindfulMinutes   { hkMindfulMinutes = mindful }
        if let temp    = snapshot.wristTemperature { hkWristTemp      = temp }
        if let resp    = snapshot.respiratoryRate  { hkRespiratoryRate = resp }
        if let spo2    = snapshot.bloodOxygen      { hkBloodOxygen    = spo2 }
        if let daylight = snapshot.daylightMinutes { hkDaylightMinutes = daylight }
    }
}

// Tops up TODAY's already-created log with fresh HealthKit data. Never creates
// a log — a day the user didn't start must not grow a phantom entry from
// background data alone.
@MainActor
enum HealthDataRefresher {
    private static let log = Logger(subsystem: "com.carpecadence", category: "HealthRefresh")

    // Pure-ish core, snapshot-injected so tests don't need HealthKit.
    // Returns whether an existing log was updated.
    @discardableResult
    static func refreshToday(context: ModelContext, snapshot: HealthKitSnapshot) -> Bool {
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == today })
        guard let todayLog = try? context.fetch(descriptor).first else { return false }
        todayLog.applyObjectiveHealthData(snapshot)
        do {
            try context.save()
            return true
        } catch {
            Self.log.error("Failed to save refreshed health data: \(error, privacy: .public)")
            return false
        }
    }

    static func refreshToday(container: ModelContainer) async {
        guard !AppLaunch.isUITesting else { return }
        let snapshot = await HealthKitService.shared.fetchLogSnapshot()
        refreshToday(context: container.mainContext, snapshot: snapshot)
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
    var wristTemperature: Double? // °C, last night's average (Watch Series 8+)
    var menstrualFlow: Bool?      // true when Health has a flow entry today; nil = no data
    var symptoms: [SymptomEntry] = []   // today's symptoms from OTHER apps, mapped to Cadence names
    var mood: Int?                // 1–5, today's State of Mind daily mood from another app (iOS 18+)
    var intenseWorkout: Bool?     // true when today's workouts clear the intensity gate; nil = none
    var respiratoryRate: Double?  // breaths/min, overnight average
    var bloodOxygen: Double?      // %, overnight average SpO2 (0–100)
    var daylightMinutes: Double?  // minutes of daylight today
    var caffeineMilligrams: Double?   // mg logged in Health today (drives the "Caffeine" factor)
    var waterLiters: Double?      // litres logged in Health today (drives the "Hydration" basic)
}
