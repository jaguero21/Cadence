import Foundation
import SwiftData

// The objective HealthKit measurements for one day.
//
// These live in their OWN @Model on a LOCAL-ONLY store configuration, split out
// of DailyLog deliberately: App Review Guideline 5.1.3(ii) says an app "may not
// store personal health information in iCloud", and DailyLog is mirrored to
// CloudKit. Keeping HealthKit-sourced values here means they never leave the
// device, while the user's own entries (mood, symptoms, notes) keep syncing.
//
// SwiftData cannot form relationships ACROSS stores, so there is no link back
// to DailyLog — the two are joined by `date` (always midnight-normalized, same
// convention as DailyLog.date). `DailyLogSnapshot.build(from:in:)` is the one
// place that join is performed; don't hand-roll another.
//
// Uniqueness is enforced in code at write time (`upsert`), not with
// @Attribute(.unique) — that stays banned project-wide because DailyLog and the
// other CloudKit-mirrored models can't use it, and having one model diverge
// invites the wrong pattern to be copied.
@Model
final class HealthSnapshot {
    // Inline default, matching the CloudKit-model convention so the two stores
    // stay stylistically consistent even though this one isn't mirrored.
    var date: Date = Calendar.current.startOfDay(for: .now)

    var hkSteps: Int?
    var hkRestingHR: Double?
    var hkHRV: Double?
    var hkSleepHours: Double?
    var hkActiveEnergy: Double?
    var hkMindfulMinutes: Double?
    var hkWristTemp: Double?          // °C, overnight wrist temperature (Watch Series 8+)
    var hkRespiratoryRate: Double?    // breaths/min, overnight average
    var hkBloodOxygen: Double?        // %, overnight average SpO2
    var hkDaylightMinutes: Double?    // minutes of daylight today (iOS 17 / watchOS 10)
    var hkDaytimeHR: Double?          // bpm, today's average heart rate (all samples)
    var hkWorkoutMinutes: Double?     // total workout duration today; nil = no workouts

    init(date: Date = .now) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    // True when this row carries no measurement at all. Used to avoid
    // persisting empty rows for days HealthKit had nothing for.
    var isEmpty: Bool {
        hkSteps == nil && hkRestingHR == nil && hkHRV == nil && hkSleepHours == nil
            && hkActiveEnergy == nil && hkMindfulMinutes == nil && hkWristTemp == nil
            && hkRespiratoryRate == nil && hkBloodOxygen == nil && hkDaylightMinutes == nil
            && hkDaytimeHR == nil && hkWorkoutMinutes == nil
    }

    // Applies a HealthKit fetch to this row. Each value is written only when
    // PRESENT, so a partial fetch (Health access revoked for one type, a query
    // that timed out) can never blank a measurement recorded earlier.
    //
    // Moved here from `DailyLog` when the stores were split; the never-blank-on-
    // nil rule is the same one that made it safe to run against an existing log
    // long after the user finished editing.
    func apply(_ snapshot: HealthKitSnapshot) {
        if let steps    = snapshot.steps            { hkSteps           = steps }
        if let hr       = snapshot.restingHR        { hkRestingHR       = hr }
        if let hrv      = snapshot.hrv              { hkHRV             = hrv }
        if let sleep    = snapshot.sleepHours       { hkSleepHours      = sleep }
        if let energy   = snapshot.activeEnergy     { hkActiveEnergy    = energy }
        if let mindful  = snapshot.mindfulMinutes   { hkMindfulMinutes  = mindful }
        if let temp     = snapshot.wristTemperature { hkWristTemp       = temp }
        if let resp     = snapshot.respiratoryRate  { hkRespiratoryRate = resp }
        if let spo2     = snapshot.bloodOxygen      { hkBloodOxygen     = spo2 }
        if let daylight = snapshot.daylightMinutes  { hkDaylightMinutes = daylight }
        if let hr       = snapshot.daytimeHR        { hkDaytimeHR       = hr }
        if let workout  = snapshot.workoutMinutes   { hkWorkoutMinutes  = workout }
    }
}

// MARK: - Fetching & upsert

extension HealthSnapshot {

    // Every stored row keyed by its (midnight) date. One fetch, so callers
    // joining a whole window of logs don't issue a query per day.
    //
    // Duplicate rows for a day are possible in principle (no .unique), so the
    // FIRST row wins and later ones are ignored rather than silently merged —
    // `upsert` keeps duplicates from being created in the first place.
    static func byDate(in context: ModelContext) -> [Date: HealthSnapshot] {
        let rows = (try? context.fetch(FetchDescriptor<HealthSnapshot>())) ?? []
        return Dictionary(rows.map { (Calendar.current.startOfDay(for: $0.date), $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    static func row(for date: Date, in context: ModelContext) -> HealthSnapshot? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HealthSnapshot>(predicate: #Predicate { $0.date == day })
        return (try? context.fetch(descriptor))?.first
    }

    // Applies a HealthKit fetch to `date`'s row, creating it if needed, and
    // returns the row. Save-time dedup by date — the same rule DailyLog,
    // WeeklyReview and InsightRecorder already follow.
    //
    // Returns nil (inserting nothing) when the fetch carried no measurement AND
    // no row exists yet: a day HealthKit knows nothing about must not grow an
    // empty row, mirroring HealthDataRefresher's no-phantom-entries rule.
    @discardableResult
    static func upsert(_ snapshot: HealthKitSnapshot, on date: Date, in context: ModelContext) -> HealthSnapshot? {
        if let existing = row(for: date, in: context) {
            existing.apply(snapshot)
            return existing
        }
        let fresh = HealthSnapshot(date: date)
        fresh.apply(snapshot)
        guard !fresh.isEmpty else { return nil }
        context.insert(fresh)
        return fresh
    }
}
