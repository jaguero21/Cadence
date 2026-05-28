import UserNotifications

enum NotificationID {
    static let dailyLog     = "daily-log"
    static let weeklyReview = "weekly-review"
    static let streakRisk   = "streak-risk"
    static let insight      = "insight-notification"
}

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    func checkAuthorizationStatus() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    func scheduleDailyReminder(at hour: Int, minute: Int) {
        removeNotification(id: NotificationID.dailyLog)
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Time to check in"
        content.body = "Your daily log takes under 90 seconds."
        content.sound = .default

        let request = UNNotificationRequest(identifier: NotificationID.dailyLog, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleWeeklyReviewReminder(weekday: Int = 1, hour: Int = 19) {
        removeNotification(id: NotificationID.weeklyReview)
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Your week is ready for review"
        content.body = "Take 5 minutes to reflect and set intentions."
        content.sound = .default

        let request = UNNotificationRequest(identifier: NotificationID.weeklyReview, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleStreakAtRisk() {
        guard Calendar.current.component(.hour, from: .now) < 21 else { return }
        removeNotification(id: NotificationID.streakRisk)
        var components = DateComponents()
        components.hour = 21
        components.minute = 0

        // Non-repeating: fires once at 9 pm today. DashboardViewModel reschedules each
        // session if the streak is still active and today's log is still incomplete.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak"
        content.body = "You haven't logged today yet — it only takes a minute."
        content.sound = .default

        let request = UNNotificationRequest(identifier: NotificationID.streakRisk, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func sendInsightNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "New insight ready"
        content.body = title
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.insight, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func removeNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
