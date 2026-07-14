import UserNotifications

enum NotificationID {
    static let dailyLog     = "daily-log"
    static let weeklyReview = "weekly-review"
    static let streakRisk   = "streak-risk"
    static let insight      = "insight-notification"
    // Per-medication reminders: prefix + name + minute, so the sync sweep can
    // find every medication request without tracking ids anywhere.
    static let medicationPrefix = "med-reminder-"
}

@MainActor
final class NotificationService: NotificationServiceProtocol {
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
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
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
        guard (1...7).contains(weekday), (0...23).contains(hour) else { return }
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

    // Fires once at this hour (24 h). Guard and trigger components both derive from it
    // so they can't silently diverge if the time is ever changed.
    private static let streakRiskHour = 21

    func scheduleStreakAtRisk() {
        let calendar = Calendar.current
        let now = Date.now
        // Bail out if the firing time has already passed today; a non-repeating
        // UNCalendarNotificationTrigger whose time is in the past fires tomorrow instead.
        guard calendar.component(.hour, from: now) < Self.streakRiskHour else { return }
        removeNotification(id: NotificationID.streakRisk)
        var components = DateComponents()
        components.hour = Self.streakRiskHour
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

    // Reconciles pending medication reminders with the store: sweep away every
    // request carrying the medication prefix, then reschedule the active
    // medications' times. Delete-then-write keeps edits, deletions, renames,
    // and ended courses all handled by the same idempotent pass — no per-change
    // bookkeeping to get wrong.
    func syncMedicationReminders(_ medications: [MedicationSnapshot]) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(NotificationID.medicationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for med in medications where med.isActive {
            for minute in Set(med.reminderMinutes) where (0..<1440).contains(minute) {
                var components = DateComponents()
                components.hour = minute / 60
                components.minute = minute % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let content = UNMutableNotificationContent()
                content.title = "Medication reminder"
                content.body = "Time for \(med.displayLabel)."
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: Self.medicationReminderID(name: med.name, minute: minute),
                    content: content,
                    trigger: trigger
                )
                // In an async context add() resolves to the throwing overload;
                // a failed add (e.g. permission revoked) is fine to drop —
                // the next sync pass rebuilds everything anyway.
                try? await center.add(request)
            }
        }
    }

    // Pure and unit-tested. Two active medications with the SAME name collapse
    // to one request per time — matching the app's name-keyed dedup rule.
    nonisolated static func medicationReminderID(name: String, minute: Int) -> String {
        "\(NotificationID.medicationPrefix)\(name)-\(minute)"
    }

    func removeNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
