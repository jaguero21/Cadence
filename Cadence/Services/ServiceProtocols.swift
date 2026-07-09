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
}

@MainActor
protocol NotificationServiceProtocol: AnyObject {
    func requestAuthorization() async -> Bool
    func checkAuthorizationStatus() async -> Bool
    func scheduleDailyReminder(at hour: Int, minute: Int)
    func scheduleWeeklyReviewReminder(weekday: Int, hour: Int)
    func scheduleStreakAtRisk()
    func sendInsightNotification(title: String)
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
}
