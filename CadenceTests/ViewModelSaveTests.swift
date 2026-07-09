import Testing
import Foundation
import SwiftData
@testable import Cadence

// MARK: - Test helpers
//
// These tests exercise the view-model save / rollback / lifecycle logic that the
// recent code-review fixes touched (orphan cleanup, retry-safe saves, the
// savedSuccessfully cleanup contract). Success paths run against a fresh
// in-memory ModelContext; failure paths run against ThrowingPersistence, a
// ModelPersisting stub whose save() throws, so the rollback branches that a
// real ModelContext can't be made to fail are covered directly.

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

/// Records the notification side effects DailyLogViewModel.save triggers, so we
/// can assert the streak-risk notification is cleared on a successful log.
@MainActor
private final class FakeNotificationService: NotificationServiceProtocol {
    private(set) var removedIDs: [String] = []

    func requestAuthorization() async -> Bool { true }
    func checkAuthorizationStatus() async -> Bool { true }
    func scheduleDailyReminder(at hour: Int, minute: Int) {}
    func scheduleWeeklyReviewReminder(weekday: Int, hour: Int) {}
    func scheduleStreakAtRisk() {}
    func sendInsightNotification(title: String) {}
    func removeNotification(id: String) { removedIDs.append(id) }
    func removeAll() {}
}

/// A ModelPersisting stub whose save() always throws, so we can drive the
/// view-model rollback branches that an in-memory ModelContext can't fail.
private final class ThrowingPersistence: ModelPersisting {
    struct StubError: Error {}
    private(set) var insertCount = 0
    private(set) var deleteCount = 0
    func insert<T: PersistentModel>(_ model: T) { insertCount += 1 }
    func delete<T: PersistentModel>(_ model: T) { deleteCount += 1 }
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] { [] }
    func save() throws { throw StubError() }
}

// MARK: - DailyLogViewModel.save

@Suite("DailyLogViewModel – save")
@MainActor
struct DailyLogViewModelSaveTests {

    @Test("Successful save marks the log complete and persists it")
    func save_success_marksCompleteAndPersists() throws {
        let context = try makeContext()
        let vm = DailyLogViewModel()
        let log = DailyLog()
        context.insert(log)

        let ok = vm.save(log: log, context: context, notifications: FakeNotificationService())

        #expect(ok)
        #expect(log.isComplete)
        #expect(vm.saveError == nil)
        let fetched = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isComplete == true)
    }

    @Test("Successful save clears the streak-at-risk notification")
    func save_success_clearsStreakNotification() throws {
        let context = try makeContext()
        let vm = DailyLogViewModel()
        let log = DailyLog()
        context.insert(log)
        let notifications = FakeNotificationService()

        _ = vm.save(log: log, context: context, notifications: notifications)

        #expect(notifications.removedIDs.contains(NotificationID.streakRisk))
    }

    @Test("Failed save reverts isComplete and reports an error")
    func save_failure_revertsCompleteAndReportsError() {
        let vm = DailyLogViewModel()
        let log = DailyLog()
        #expect(log.isComplete == false)
        let notifications = FakeNotificationService()

        let ok = vm.save(log: log, context: ThrowingPersistence(), notifications: notifications)

        #expect(ok == false)
        #expect(log.isComplete == false)           // reverted to its prior value
        #expect(vm.saveError != nil)
        #expect(notifications.removedIDs.isEmpty)   // success-only side effect did not run
    }

    @Test("Saving an already-complete log is idempotent")
    func save_alreadyComplete_remainsComplete() throws {
        let context = try makeContext()
        let vm = DailyLogViewModel()
        let log = DailyLog()
        log.isComplete = true
        context.insert(log)

        let ok = vm.save(log: log, context: context, notifications: FakeNotificationService())

        #expect(ok)
        #expect(log.isComplete)
        let fetched = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(fetched.count == 1)
    }
}

// MARK: - DailyLogViewModel step navigation

@Suite("DailyLogViewModel – step navigation")
@MainActor
struct DailyLogViewModelStepTests {

    @Test("nextStep advances through every step then sets isDone")
    func nextStep_advancesThenCompletes() {
        let vm = DailyLogViewModel()
        #expect(vm.currentStep == .mood)

        vm.nextStep(); #expect(vm.currentStep == .bodyMetrics)
        vm.nextStep(); #expect(vm.currentStep == .basics)
        vm.nextStep(); #expect(vm.currentStep == .symptoms)
        vm.nextStep(); #expect(vm.currentStep == .factors)
        vm.nextStep(); #expect(vm.currentStep == .peaksAndValleys)
        vm.nextStep(); #expect(vm.currentStep == .intentions)
        vm.nextStep(); #expect(vm.currentStep == .note)
        vm.nextStep(); #expect(vm.currentStep == .done)
        #expect(vm.isDone == false)

        // Advancing past the final step flips isDone and stays on .done.
        vm.nextStep()
        #expect(vm.isDone)
        #expect(vm.currentStep == .done)
    }

    @Test("previousStep floors at the first step")
    func previousStep_floorsAtMood() {
        let vm = DailyLogViewModel()
        vm.nextStep() // .bodyMetrics
        vm.previousStep()
        #expect(vm.currentStep == .mood)
        // Already at the first step — should not underflow.
        vm.previousStep()
        #expect(vm.currentStep == .mood)
    }
}

// MARK: - WeeklyReviewViewModel.save

@Suite("WeeklyReviewViewModel – save")
@MainActor
struct WeeklyReviewViewModelSaveTests {

    @Test("savedSuccessfully starts false (cleanup contract for unsaved reviews)")
    func savedSuccessfully_defaultsFalse() {
        let vm = WeeklyReviewViewModel()
        #expect(vm.savedSuccessfully == false)
    }

    @Test("Successful save sets flags, completes, and persists the review")
    func save_success_setsFlagsAndPersists() throws {
        let context = try makeContext()
        let vm = WeeklyReviewViewModel()
        let review = WeeklyReview(weekStartDate: .now)

        let ok = vm.save(review: review, context: context)

        #expect(ok)
        #expect(vm.savedSuccessfully)
        #expect(review.isComplete)
        #expect(vm.saveError == nil)
        let fetched = try context.fetch(FetchDescriptor<WeeklyReview>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isComplete == true)
    }

    @Test("Failed save reverts isComplete, reports an error, and leaves savedSuccessfully false")
    func save_failure_revertsAndKeepsRetryable() {
        let vm = WeeklyReviewViewModel()
        let review = WeeklyReview(weekStartDate: .now)
        #expect(review.isComplete == false)

        let ok = vm.save(review: review, context: ThrowingPersistence())

        #expect(ok == false)
        #expect(review.isComplete == false)      // reverted, so a retry can re-attempt
        #expect(vm.saveError != nil)
        #expect(vm.savedSuccessfully == false)   // cleanup guard still treats it as unsaved
    }

    @Test("Saving the same review twice does not duplicate it")
    func save_calledTwice_insertsOnce() throws {
        let context = try makeContext()
        let vm = WeeklyReviewViewModel()
        let review = WeeklyReview(weekStartDate: .now)

        #expect(vm.save(review: review, context: context))
        #expect(vm.save(review: review, context: context))

        let fetched = try context.fetch(FetchDescriptor<WeeklyReview>())
        #expect(fetched.count == 1)
    }

    // Regression: with the unique constraint gone (CloudKit), a review for this
    // week can already exist even though the sheet was presented with nil
    // (stale snapshot / CloudKit sync). save() must merge into it, not insert
    // a same-week duplicate.
    @Test("Saving a fresh review for an already-reviewed week merges instead of duplicating")
    func save_duplicateWeek_mergesIntoPersisted() throws {
        let context = try makeContext()
        let vm = WeeklyReviewViewModel()
        let persisted = WeeklyReview(weekStartDate: .now)
        context.insert(persisted)
        try context.save()

        let fresh = WeeklyReview(weekStartDate: .now)
        fresh.overallRating = 4
        #expect(vm.save(review: fresh, context: context))

        let stored = try context.fetch(FetchDescriptor<WeeklyReview>())
        #expect(stored.count == 1)
        #expect(stored.first?.overallRating == 4)   // fresh data merged in
        #expect(stored.first?.isComplete == true)
    }

    // Mirrors ReviewFlowView.onDisappear: a new review that was inserted but
    // never successfully saved is removed from the store. The guard relies on
    // savedSuccessfully staying false, which we assert separately above.
    @Test("Deleting an inserted-but-unsaved review leaves the store empty")
    func unsavedReview_deletedOnDisappear_leavesStoreEmpty() throws {
        let context = try makeContext()
        let review = WeeklyReview(weekStartDate: .now)
        context.insert(review)

        // The view checks review.modelContext != nil before deleting.
        #expect(review.modelContext != nil)
        context.delete(review)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WeeklyReview>())
        #expect(fetched.isEmpty)
    }
}

// MARK: - WeeklyReviewViewModel navigation

@Suite("WeeklyReviewViewModel – navigation")
@MainActor
struct WeeklyReviewViewModelNavigationTests {

    @Test("isLastStep is true only once Intentions is reached")
    func isLastStep_trueOnlyOnIntentions() {
        let vm = WeeklyReviewViewModel()
        #expect(vm.isLastStep == false)
        // Walk to the last prompt: reaching it isn't the end anymore — the two
        // dedicated closing steps (Peaks & Valleys, Intentions) still follow.
        for _ in 0..<(vm.prompts.count - 1) { vm.next() }
        #expect(vm.currentStep == .prompt(vm.prompts.count - 1))
        #expect(vm.isLastStep == false)
        #expect(vm.isComplete == false)
        vm.next()
        #expect(vm.currentStep == .peaksAndValleys)
        #expect(vm.isLastStep == false)
        vm.next()
        #expect(vm.currentStep == .intentions)
        #expect(vm.isLastStep)
        #expect(vm.isComplete == false)
        // next() on Intentions completes rather than overflowing the step sequence.
        vm.next()
        #expect(vm.isComplete)
    }

    @Test("previous never goes below the first prompt")
    func previous_floorsAtFirstPrompt() {
        let vm = WeeklyReviewViewModel()
        vm.next()
        vm.previous()
        #expect(vm.currentStep == .prompt(0))
        vm.previous()
        #expect(vm.currentStep == .prompt(0))
    }

    @Test("progress advances from 0 toward 1 across prompts")
    func progress_advancesAcrossPrompts() {
        let vm = WeeklyReviewViewModel()
        #expect(vm.progress == 0)
        vm.next()
        #expect(vm.progress > 0)
        #expect(vm.progress < 1)
    }
}

// MARK: - WeeklyReviewViewModel.populateSummary

@Suite("WeeklyReviewViewModel – populateSummary")
@MainActor
struct WeeklyReviewPopulateSummaryTests {

    private func log(on date: Date, mood: Int, energy: Int, sleep: Double, symptoms: [SymptomEntry] = []) -> DailyLog {
        let l = DailyLog(date: date)
        l.mood = mood
        l.energy = energy
        l.sleepHours = sleep
        l.symptoms = symptoms
        return l
    }

    @Test("Computes averages and top symptoms for logs within the review week")
    func populateSummary_inWeekLogs_computesAveragesAndTopSymptoms() {
        let vm = WeeklyReviewViewModel()
        let review = WeeklyReview(weekStartDate: .now)
        let start = review.weekStartDate
        let cal = Calendar.current
        let headache = SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")
        let fatigue  = SymptomEntry(name: "Fatigue",  severity: 5, emoji: "😴")

        let logs = [
            log(on: start,                                       mood: 4, energy: 6, sleep: 8, symptoms: [headache]),
            log(on: cal.date(byAdding: .day, value: 1, to: start)!, mood: 2, energy: 4, sleep: 6, symptoms: [headache, fatigue]),
            log(on: cal.date(byAdding: .day, value: 2, to: start)!, mood: 3, energy: 5, sleep: 7, symptoms: []),
        ]

        vm.populateSummary(review: review, from: logs)

        #expect(abs(review.avgMood - 3.0) < 0.001)   // (4+2+3)/3
        #expect(abs(review.avgEnergy - 5.0) < 0.001) // (6+4+5)/3
        #expect(abs(review.avgSleep - 7.0) < 0.001)  // (8+6+7)/3
        #expect(review.topSymptoms.first == "Headache") // 2 occurrences vs 1
        #expect(review.topSymptoms.contains("Fatigue"))
    }

    @Test("Leaves the review untouched when no logs fall in the week")
    func populateSummary_noInWeekLogs_isNoOp() {
        let vm = WeeklyReviewViewModel()
        let review = WeeklyReview(weekStartDate: .now)
        let cal = Calendar.current
        // A log well outside the review week (3 weeks earlier).
        let stale = cal.date(byAdding: .day, value: -21, to: review.weekStartDate)!
        let logs = [log(on: stale, mood: 5, energy: 9, sleep: 9)]

        vm.populateSummary(review: review, from: logs)

        #expect(review.avgMood == 0)
        #expect(review.avgEnergy == 0)
        #expect(review.avgSleep == 0)
        #expect(review.topSymptoms.isEmpty)
    }
}

// MARK: - WeeklyReviewViewModel: step machine

// Peaks & Valleys and Intentions are two dedicated closing steps appended
// after the 7 default prompts (not part of the generic PromptResponse text
// system, since Peaks & Valleys needs voice-memo support). These tests pin
// the flattened step sequence: prompt(0)...prompt(6), peaksAndValleys,
// intentions, then completion.
@MainActor
@Suite("WeeklyReviewViewModel – step machine")
struct WeeklyReviewStepMachineTests {

    @Test("next() walks all prompts, then Peaks & Valleys, then Intentions, then completes")
    func nextWalksFullSequence() {
        let vm = WeeklyReviewViewModel()
        #expect(vm.currentStep == .prompt(0))
        #expect(vm.totalSteps == vm.prompts.count + 2)

        for i in 1..<vm.prompts.count {
            vm.next()
            #expect(vm.currentStep == .prompt(i))
        }

        vm.next()
        #expect(vm.currentStep == .peaksAndValleys)
        #expect(vm.isLastStep == false)

        vm.next()
        #expect(vm.currentStep == .intentions)
        #expect(vm.isLastStep == true)

        vm.next()
        #expect(vm.isComplete == true)
    }

    @Test("previous() reverses through Intentions, Peaks & Valleys, and back into the prompts")
    func previousReversesFullSequence() {
        let vm = WeeklyReviewViewModel()
        vm.currentStep = .intentions

        vm.previous()
        #expect(vm.currentStep == .peaksAndValleys)

        vm.previous()
        #expect(vm.currentStep == .prompt(vm.prompts.count - 1))

        vm.previous()
        #expect(vm.currentStep == .prompt(vm.prompts.count - 2))
    }

    @Test("previous() at the first prompt is a no-op")
    func previousAtStartIsNoOp() {
        let vm = WeeklyReviewViewModel()
        vm.previous()
        #expect(vm.currentStep == .prompt(0))
    }

    @Test("flatIndex and progress span the full step count including the two new steps")
    func flatIndexAndProgress() {
        let vm = WeeklyReviewViewModel()
        #expect(vm.flatIndex(.prompt(0)) == 0)
        #expect(vm.flatIndex(.peaksAndValleys) == vm.prompts.count)
        #expect(vm.flatIndex(.intentions) == vm.prompts.count + 1)

        vm.currentStep = .intentions
        #expect(vm.currentFlatIndex == vm.totalSteps - 1)
        #expect(vm.progress == Double(vm.totalSteps - 1) / Double(vm.totalSteps))
    }
}
