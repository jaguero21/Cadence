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
                if vm.isComplete {
                    completionView
                } else {
                    VStack(spacing: 0) {
                        progressBar
                        ScrollView {
                            VStack(spacing: 20) {
                                if vm.currentStep == .prompt(0) {
                                    WeekSummaryView(review: review)
                                    WeekReflectionCard(logs: weekLogs)
                                }
                                stepContent
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
            .onDisappear {
                // Clean up a new review that was inserted but never successfully saved.
                if existingReview == nil, !vm.savedSuccessfully, review.modelContext != nil {
                    modelContext.delete(review)
                }
            }
        }
        // Paint the SHEET surface (see LogInputFlow): on iOS 26 sheet content
        // is inset, so a content background leaves side strips.
        .presentationBackground {
            if vm.isComplete {
                AmbientMeshBackground()
            } else {
                CadenceColor.background
            }
        }
    }

    // The review's week, snapshotted for the on-device reflection.
    private var weekLogs: [DailyLogSnapshot] {
        let cal = Calendar.current
        let weekStart = review.weekStartDate
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return logs
            .filter { $0.date >= weekStart && $0.date < weekEnd }
            .map { DailyLogSnapshot($0) }
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
    private var stepContent: some View {
        switch vm.currentStep {
        case .prompt(let i):
            promptCard(for: vm.prompts[i])
        case .intentions:
            intentionsCard
            StarRatingView(rating: $review.overallRating)
        }
    }

    private func promptCard(for prompt: Prompt) -> some View {
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
        return PromptCardView(prompt: prompt, response: binding, index: vm.currentFlatIndex, total: vm.totalSteps)
    }

    private var intentionsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(vm.currentFlatIndex + 1) of \(vm.totalSteps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Intentions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CadenceColor.sleepPurple)
            }

            Text("Write your intentions for tomorrow.")
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            TextField("What do you want to carry into tomorrow?", text: $review.intentionsForTomorrow, axis: .vertical)
                .font(.body)
                .lineLimit(5...12)
                .padding(14)
                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .cadenceCard()
    }

    private var navBar: some View {
        HStack(spacing: 16) {
            if vm.currentStep != .prompt(0) {
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
                if vm.isLastStep {
                    guard vm.save(review: review, context: modelContext) else { return }
                }
                vm.next()
            } label: {
                HStack {
                    // Its own key: here "Complete" is the verb that finishes the
                    // review, not the status adjective on ReviewRowView.
                    (vm.isLastStep
                        ? Text(String(localized: "review.button.complete",
                                      defaultValue: "Complete",
                                      comment: "Button that finishes the weekly review. A verb, unlike the identically-worded status label."))
                        : Text("Next"))
                        .font(.body.bold())
                    if !vm.isLastStep {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding(.horizontal, 28)
                .frame(height: 50)
                .background(CadenceColor.sleepPurple, in: Capsule())
                .foregroundStyle(.white)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: vm.currentFlatIndex)
        }
        .padding()
    }

    private var completionView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 72))
                .foregroundStyle(CadenceColor.sleepPurple)
                .cadenceSymbolBounce(value: 1)

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

// On-device weekly reflection (iOS 26 Apple Intelligence). Explicit button —
// nothing generates behind the user's back; the card only exists at all when
// the model is available, and it states plainly that nothing leaves the phone.
private struct WeekReflectionCard: View {
    let logs: [DailyLogSnapshot]

    private enum Phase: Equatable {
        case idle, generating, done(String), blocked, failed
    }
    @State private var phase: Phase = .idle

    // The week's own words, which is all the check looks at.
    private var writtenText: [String] {
        logs.flatMap { [$0.freeNote, $0.peaksAndValleysNote, $0.intentionsForTomorrow] }
    }

    var body: some View {
        if CrisisLanguage.matches(in: writtenText) {
            // Deliberately before any model call: summarizing "I thought about
            // hurting myself" back at someone is not what this feature is for.
            SupportResourcesCard()
        } else if WeekReflectionService.isSupported && !AppLaunch.isUITesting,
                  WeekReflectionService.promptText(from: logs) != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(CadenceColor.accent)
                    Text("Week Reflection")
                        .font(.headline)
                    Spacer()
                }

                switch phase {
                case .idle:
                    Button {
                        generate()
                    } label: {
                        Label("Summarize my week", systemImage: "text.badge.star")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(CadenceColor.accent)
                case .generating:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading your week…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .done(let text):
                    Text(text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Regenerate") { generate() }
                        .font(.caption)
                        .foregroundStyle(CadenceColor.accent)
                case .blocked:
                    // Apple's safety guidance: say plainly that the input is what
                    // the feature can't handle, rather than showing a generic error.
                    Text("This feature isn't designed to summarize some of what you wrote this week. You can still review as usual.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .failed:
                    Text("Couldn't summarize this week. You can still review as usual.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Written on this iPhone from your own entries — nothing leaves your device. An observation, not advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .cadenceCard()
        }
    }

    private func generate() {
        phase = .generating
        let snapshot = logs
        Task {
            switch await WeekReflectionService.generate(from: snapshot) {
            case .text(let text):       phase = .done(text)
            case .blocked:              phase = .blocked
            case .unavailable, .failed: phase = .failed
            }
        }
    }
}

// Shown instead of the reflection when the week's own words contain explicit
// self-harm language. Nothing is blocked — the weekly review continues — and no
// model call is made.
private struct SupportResourcesCard: View {
    private var resources: CrisisSupport.Resources {
        CrisisSupport.resources(region: Locale.current.region?.identifier,
                                isSpanish: Locale.current.language.languageCode?.identifier == "es")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(CadenceColor.accent)
                Text("Support is available")
                    .font(.headline)
                Spacer()
            }

            Text("Something you wrote this week mentions hurting yourself. If you're in crisis, or you just want someone to talk to, these lines are free and confidential.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            // URLs arrive as Strings so this layer can fail soft instead of
            // force-unwrapping; a malformed one hides its link rather than crashing.
            switch resources {
            case .lifeline988(let chatURL):
                if let call = URL(string: "tel:988") {
                    Link("Call 988", destination: call).font(.subheadline.weight(.medium))
                }
                if let text = URL(string: "sms:988") {
                    Link("Text 988", destination: text).font(.subheadline.weight(.medium))
                }
                if let chat = URL(string: chatURL) {
                    Link("Chat with the 988 Lifeline", destination: chat).font(.subheadline.weight(.medium))
                }
                Text("988 Suicide & Crisis Lifeline — free and confidential, 24/7.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .findAHelpline(let directoryURL):
                if let directory = URL(string: directoryURL) {
                    Link("Find a helpline in your country", destination: directory).font(.subheadline.weight(.medium))
                }
                Text("In an emergency, contact your local emergency services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Cadence checked this on your iPhone. Nothing was sent anywhere.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .tint(CadenceColor.accent)
        .cadenceCard()
    }
}
