import SwiftUI
import SwiftData

@MainActor
@Observable
final class WeeklyReviewViewModel {
    var currentPromptIndex: Int = 0
    var isComplete: Bool = false
    var saveError: String?

    let prompts = Prompt.weeklyDefaults

    var currentPrompt: Prompt { prompts[min(currentPromptIndex, prompts.count - 1)] }
    var progress: Double { Double(currentPromptIndex) / Double(prompts.count) }
    var isLastPrompt: Bool { currentPromptIndex >= prompts.count - 1 }

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
    func save(review: WeeklyReview, context: ModelContext) -> Bool {
        context.insert(review)   // no-op if already inserted; ensures new reviews are registered
        do {
            try context.save()
        } catch {
            saveError = "Your review couldn't be saved. Please try again."
            return false
        }
        review.isComplete = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }
}
