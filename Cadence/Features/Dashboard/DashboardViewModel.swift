import SwiftUI
import SwiftData

@MainActor
@Observable
final class DashboardViewModel {
    var todayLog: DailyLog?
    var thisWeekReview: WeeklyReview?
    var streak: Int = 0
    var latestInsight: InsightCard?

    func refresh(logs: [DailyLog], reviews: [WeeklyReview], notifications: any NotificationServiceProtocol = NotificationService.shared) {
        todayLog = logs.first { Calendar.current.isDateInToday($0.date) }
        thisWeekReview = reviews.first { $0.weekStartDate.isThisWeek }
        streak = computeStreak(from: logs)
        // Snapshot @Model values on the main actor before handing them to PatternEngine,
        // which is otherwise isolation-agnostic.
        latestInsight = PatternEngine.latestInsight(from: logs.map(DailyLogSnapshot.init))

        if streak > 0 && todayLog?.isComplete != true {
            notifications.scheduleStreakAtRisk()
        } else {
            notifications.removeNotification(id: NotificationID.streakRisk)
        }
    }

    private func computeStreak(from logs: [DailyLog]) -> Int {
        let sorted = logs.filter(\.isComplete).map(\.date).sorted(by: >)
        var streak = 0
        let todayComplete = logs.contains { Calendar.current.isDateInToday($0.date) && $0.isComplete }
        var check: Date
        if todayComplete {
            check = Calendar.current.startOfDay(for: .now)
        } else {
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) else { return 0 }
            check = Calendar.current.startOfDay(for: yesterday)
        }
        for date in sorted {
            let day = Calendar.current.startOfDay(for: date)
            if day == check {
                streak += 1
                guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: check) else { break }
                check = prev
            } else {
                break
            }
        }
        return streak
    }
}
