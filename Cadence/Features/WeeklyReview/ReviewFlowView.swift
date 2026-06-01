import SwiftUI
import SwiftData

struct ReviewFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm = WeeklyReviewViewModel()
    @State private var review: WeeklyReview
    let existingReview: WeeklyReview?
    let logs: [DailyLog]

    init(existingReview: WeeklyReview?, logs: [DailyLog]) {
        self.existingReview = existingReview
        self.logs = logs
        _review = State(initialValue: existingReview ?? WeeklyReview(weekStartDate: Date().startOfWeek))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CadenceColor.background.ignoresSafeArea()

                if vm.isComplete {
                    completionView
                } else {
                    VStack(spacing: 0) {
                        progressBar
                        ScrollView {
                            VStack(spacing: 20) {
                                if vm.currentPromptIndex == 0 {
                                    WeekSummaryView(review: review)
                                }
                                promptCard
                            }
                            .padding()
                        }
                        navBar
                    }
                }
            }
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't Save", isPresented: .init(
                get: { vm.saveError != nil },
                set: { if !$0 { vm.saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save & Close") {
                        if vm.save(review: review, context: modelContext) {
                            Task { @MainActor in dismiss() }
                        }
                    }
                }
            }
            .onAppear {
                if !review.isComplete {
                    vm.populateSummary(review: review, from: logs)
                }
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(.systemFill)).frame(height: 3)
                Rectangle()
                    .fill(CadenceColor.sleepPurple)
                    .frame(width: geo.size.width * vm.progress, height: 3)
                    .animation(CadenceAnimation.smooth, value: vm.progress)
            }
        }
        .frame(height: 3)
    }

    @ViewBuilder
    private var promptCard: some View {
        let prompt = vm.currentPrompt
        let binding = Binding<String>(
            get: { review.promptResponses.first { $0.section == prompt.section }?.response ?? "" },
            set: { newVal in
                if let idx = review.promptResponses.firstIndex(where: { $0.section == prompt.section }) {
                    review.promptResponses[idx].response = newVal
                } else {
                    review.promptResponses.append(PromptResponse(section: prompt.section, prompt: prompt.question, response: newVal))
                }
            }
        )
        PromptCardView(prompt: prompt, response: binding, index: vm.currentPromptIndex, total: vm.prompts.count)

        if vm.isLastPrompt {
            StarRatingView(rating: $review.overallRating)
        }
    }

    private var navBar: some View {
        HStack(spacing: 16) {
            if vm.currentPromptIndex > 0 {
                Button {
                    vm.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                        .frame(width: 44, height: 44)
                        .background(CadenceColor.cardBG, in: Circle())
                }
            }
            Spacer()
            Button {
                if vm.isLastPrompt {
                    guard vm.save(review: review, context: modelContext) else { return }
                }
                vm.next()
            } label: {
                HStack {
                    Text(vm.isLastPrompt ? "Complete" : "Next").font(.body.bold())
                    if !vm.isLastPrompt {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding(.horizontal, 28)
                .frame(height: 50)
                .background(CadenceColor.sleepPurple, in: Capsule())
                .foregroundStyle(.white)
            }
            .hapticFeedback(.medium)
        }
        .padding()
        .background(.bar)
    }

    private var completionView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 72))
                .foregroundStyle(CadenceColor.sleepPurple)
                .symbolEffect(.bounce, value: 1)

            VStack(spacing: 8) {
                Text("Review Complete!")
                    .font(.title.bold())
                Text("Your reflections are saved. Insights are being updated.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if review.overallRating > 0 {
                StarRatingDisplayView(rating: review.overallRating)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(CadenceColor.sleepPurple)
            Spacer()
        }
        .padding()
    }
}
