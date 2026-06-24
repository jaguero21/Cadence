import SwiftUI
import SwiftData
import OSLog

@MainActor
@Observable
final class WeeklyReviewViewModel {
    private static let log = Logger(subsystem: "com.carpecadence", category: "WeeklyReview")
    var currentPromptIndex: Int = 0
    var isComplete: Bool = false
    var saveError: String?
    var savedSuccessfully = false

    let prompts = Prompt.weeklyDefaults

    var currentPrompt: Prompt { prompts[min(currentPromptIndex, max(prompts.count - 1, 0))] }
    var progress: Double { prompts.isEmpty ? 1 : Double(currentPromptIndex) / Double(prompts.count) }
    var isLastPrompt: Bool { prompts.isEmpty || currentPromptIndex >= prompts.count - 1 }

    func next() {
        withAnimation(CadenceAnimation.spring) {
            if isLastPrompt {
                isComplete = true
            } else {
                currentPromptIndex += 1
            }
        }
    }

    func previous() {
        withAnimation(CadenceAnimation.spring) {
            if currentPromptIndex > 0 { currentPromptIndex -= 1 }
        }
    }

    func populateSummary(review: WeeklyReview, from logs: [DailyLog]) {
        let weekLogs = logs.filter { log in
            log.date >= review.weekStartDate && log.date <= review.weekEndDate
        }
        guard !weekLogs.isEmpty else { return }
        review.avgMood   = Double(weekLogs.map(\.mood).reduce(0, +)) / Double(weekLogs.count)
        review.avgEnergy = Double(weekLogs.map(\.energy).reduce(0, +)) / Double(weekLogs.count)
        review.avgSleep  = weekLogs.map(\.sleepHours).reduce(0, +) / Double(weekLogs.count)

        let symptomCounts = weekLogs.flatMap(\.symptoms)
            .reduce(into: [:]) { $0[$1.name, default: 0] += 1 }
        review.topSymptoms = symptomCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    @discardableResult
    func save(review: WeeklyReview, context: any ModelPersisting) -> Bool {
        context.insert(review)
        let wasComplete = review.isComplete
        review.isComplete = true
        do {
            try context.save()
        } catch {
            review.isComplete = wasComplete
            Self.log.error("Failed to save weekly review: \(error.localizedDescription)")
            saveError = String(localized: "Your review couldn't be saved. Please try again.")
            return false
        }
        savedSuccessfully = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }
}
