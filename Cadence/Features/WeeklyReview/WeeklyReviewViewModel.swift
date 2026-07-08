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
        // With no DB-level unique constraint (CloudKit), a review for this week
        // may exist in the store even though the sheet was presented with a nil
        // existingReview (stale @Query snapshot, CloudKit sync mid-flow). Merge
        // into the persisted one instead of inserting a same-week duplicate.
        let target: WeeklyReview
        let weekStart = review.weekStartDate
        if review.modelContext == nil,
           let persisted = try? context.fetch(
               FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartDate == weekStart })
           ).first {
            persisted.promptResponses = review.promptResponses
            persisted.overallRating = review.overallRating
            persisted.avgMood = review.avgMood
            persisted.avgEnergy = review.avgEnergy
            persisted.avgSleep = review.avgSleep
            persisted.topSymptoms = review.topSymptoms
            target = persisted
        } else {
            target = review
        }
        context.insert(target)
        let wasComplete = target.isComplete
        target.isComplete = true
        do {
            try context.save()
        } catch {
            target.isComplete = wasComplete
            Self.log.error("Failed to save weekly review: \(error.localizedDescription)")
            saveError = String(localized: "Your review couldn't be saved. Please try again.")
            return false
        }
        savedSuccessfully = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }
}
