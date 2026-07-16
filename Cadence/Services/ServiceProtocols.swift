import SwiftData

// Minimal protocols covering only the methods and properties called across the
// codebase. Views and view models depend on these, not the concrete classes,
// so tests can inject lightweight fakes without touching HealthKit or UNUserNotificationCenter.

// Seam over ModelContext's persistence surface so view models can be tested
// against a stub whose save() throws — exercising the rollback / cleanup
// branches that a real in-memory ModelContext can't be made to fail. The
// requirements match ModelContext's existing signatures, so it conforms with
// an empty extension. Left non-isolated to mirror ModelContext (the @MainActor
// view models call it without friction).
protocol ModelPersisting {
    func insert<T: PersistentModel>(_ model: T)
    func delete<T: PersistentModel>(_ model: T)
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T]
    func save() throws
}

extension ModelContext: ModelPersisting {}

@MainActor
protocol HealthKitServiceProtocol: AnyObject {
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws -> Bool
    func fetchLogSnapshot() async -> HealthKitSnapshot
    // Mirrors a saved day into Health (mapped symptoms + State of Mind mood).
    // Best-effort; implementations must never let this block or fail a save.
    func publish(log: DailyLogSnapshot) async
}

@MainActor
protocol NotificationServiceProtocol: AnyObject {
    func requestAuthorization() async -> Bool
    func checkAuthorizationStatus() async -> Bool
    func scheduleDailyReminder(at hour: Int, minute: Int)
    func scheduleWeeklyReviewReminder(weekday: Int, hour: Int)
    func scheduleStreakAtRisk()
    func sendInsightNotification(title: String)
    func syncMedicationReminders(_ medications: [MedicationSnapshot]) async
    func removeNotification(id: String)
    func removeAll()
}

// Default-argument convenience for existential callers: protocol
// requirements can't carry defaults, so we expose a no-arg overload that
// dispatches to the requirement with sensible defaults (Sunday at 7 pm).
extension NotificationServiceProtocol {
    func scheduleWeeklyReviewReminder() {
        scheduleWeeklyReviewReminder(weekday: 1, hour: 19)
    }

    // Shared reconcile-sweep trigger for every foreground/restore call site:
    // fetch every medication fresh from the context and hand snapshots to
    // syncMedicationReminders. Skipped under UI tests, where firing a real
    // permission prompt mid-run would block the smoke test. The medication
    // editor's save and the medication list's delete build their own
    // snapshots directly (they already know the post-edit state) and don't
    // go through this.
    func reconcileMedicationReminders(context: ModelContext) {
        guard !AppLaunch.isUITesting else { return }
        let snapshots = ((try? context.fetch(FetchDescriptor<Medication>())) ?? []).map(MedicationSnapshot.init)
        Task {
            await syncMedicationReminders(snapshots)
        }
    }
}
