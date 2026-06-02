// Minimal protocols covering only the methods and properties called across the
// codebase. Views and view models depend on these, not the concrete classes,
// so tests can inject lightweight fakes without touching HealthKit or UNUserNotificationCenter.

protocol HealthKitServiceProtocol: AnyObject {
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws -> Bool
    func fetchLogSnapshot() async -> HealthKitSnapshot
}

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

// Default-argument convenience: protocols cannot carry default values, so
// the protocol extension provides them so callers can write
// `notifications.scheduleWeeklyReviewReminder()` through the existential.
extension NotificationServiceProtocol {
    func scheduleWeeklyReviewReminder(weekday: Int = 1, hour: Int = 19) {
        scheduleWeeklyReviewReminder(weekday: weekday, hour: hour)
    }
}
