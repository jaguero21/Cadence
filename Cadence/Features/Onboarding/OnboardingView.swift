import SwiftUI
import SwiftData
import OSLog

// Five pages, ordered so the person reaches value fast and is asked for
// permissions only after seeing why:
//   welcome (+ privacy) → what you track → reminder time → Apple Health → first log.
// The last page launches the first log directly (AppState.pendingFirstLog):
// finishing a first entry is the strongest predictor of sticking with a
// tracker, and an empty dashboard left people to find it themselves.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep = .welcome
    @State private var isRequestingPermission = false
    // The person tapped "Enable Reminders" and then declined the system
    // prompt. Stay on the page and say how to turn them on later, instead of
    // advancing as if it had worked.
    @State private var notificationsDeclined = false

    // Symptom names chosen on the "What do you track?" page, in tap order.
    @State private var selectedSymptoms: [String] = []
    @State private var didLoadSymptoms = false
    // Tags this onboarding inserted, so going Back and deselecting one can
    // remove it again. Tags that existed before onboarding are never deleted.
    @State private var insertedSymptoms: Set<String> = []

    @AppStorage(UserDefaultsKey.dailyReminderHour)   private var reminderHour: Int = 20
    @AppStorage(UserDefaultsKey.dailyReminderMinute) private var reminderMinute: Int = 0

    private static let log = Logger(subsystem: "com.carpecadence", category: "Onboarding")

    var body: some View {
        ZStack {
            // The same backdrop as the dashboard it leads into.
            AmbientMeshBackground().ignoresSafeArea()
            page
                .transition(.cadenceStepSlide(reduceMotion: reduceMotion))
                .id(step)
        }
        .onAppear(perform: loadSymptomSelection)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:   welcomePage
        case .symptoms:  symptomsPage
        case .reminders: remindersPage
        case .health:    healthPage
        case .ready:     readyPage
        }
    }

    private func go(to next: OnboardingStep) {
        withAnimation(CadenceAnimation.spring) { step = next }
    }

    private var back: (() -> Void)? {
        guard let previous = step.previous else { return nil }
        return { go(to: previous) }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPage(
            step: step,
            pose: .welcoming,
            title: "Welcome to Cadence",
            message: "Track how you feel, sleep, and move in about 2 minutes a day. Over time, Cadence finds patterns you wouldn't notice on your own.",
            primaryLabel: "Get Started",
            primaryAction: { go(to: .symptoms) }
        ) {
            // The strongest trust signal the app has, said before anyone types
            // a word of health information — and true: no account, no ads,
            // CloudKit private database + a local-only Health store.
            Label {
                Text("Private by design. Your entries stay on your iPhone and in your own iCloud. No account, no ads.")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(CadenceColor.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var symptomsPage: some View {
        OnboardingPage(
            step: step,
            pose: .cozy,
            title: "What do you want to track?",
            message: "Pick the symptoms you'd like to log. You can change these anytime in Settings.",
            primaryLabel: "Continue",
            primaryAction: {
                saveSymptomSelection()
                go(to: .reminders)
            },
            onBack: back
        ) {
            SymptomChoiceGrid(selection: $selectedSymptoms)
        }
    }

    // App Review Guideline 5.1.1(iv): a screen that explains a permission must
    // always lead to the system request. Version 1.0 (9) was rejected because
    // the Health page had a Skip button; this page had the same pattern for
    // notifications, and Back on either page also let someone leave without
    // ever seeing the system sheet. So permission pages have one button,
    // "Continue", which always shows iOS's own prompt (where the person can
    // still say no), and no Skip or Back.
    private var remindersPage: some View {
        OnboardingPage(
            step: step,
            pose: .sleepy,
            title: "Stay consistent",
            message: "Choose a time for a gentle daily reminder. It skips any day you've already logged. Next, iOS will ask whether Cadence can send notifications.",
            isBusy: isRequestingPermission,
            primaryLabel: "Continue",
            primaryAction: notificationsDeclined ? { go(to: .health) } : enableReminders
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // "You choose when" used to be a promise the page didn't keep:
                // everyone got 8 PM. The same keys Settings edits.
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .font(.body.weight(.medium))
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                if notificationsDeclined {
                    Label("Reminders are off for now. You can turn them on anytime in the Settings app under Cadence → Notifications.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isRequestingPermission)
    }

    private var healthPage: some View {
        OnboardingPage(
            step: step,
            pose: .soaking,
            title: "Less typing, more insight",
            message: "Apple Health can auto-fill sleep, activity, cycle data and more, and keep your logged symptoms and mood in your health record. Next, iOS will ask what to share. You can turn on any of it, or none, and everything in Cadence still works.",
            isBusy: isRequestingPermission,
            primaryLabel: "Continue",
            primaryAction: {
                // UI tests promise no system dialogs (AppLaunch.isUITesting).
                guard !AppLaunch.isUITesting else { go(to: .ready); return }
                isRequestingPermission = true
                Task {
                    appState.healthKitAuthorized = (try? await healthKitService.requestAuthorization()) ?? healthKitService.isAuthorized
                    isRequestingPermission = false
                    go(to: .ready)
                }
            }
        )
        .disabled(isRequestingPermission)
    }

    private var readyPage: some View {
        OnboardingPage(
            step: step,
            pose: .resting,
            title: "You're all set!",
            message: "Your first check-in takes about 2 minutes. Start now and Cadence begins learning your rhythm today.",
            primaryLabel: "Log how today feels",
            primaryAction: {
                appState.pendingFirstLog = true
                appState.completeOnboarding()
            },
            secondaryLabel: "Explore first",
            secondaryAction: { appState.completeOnboarding() },
            onBack: back
        )
    }

    // MARK: - Reminders

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now) ?? .now
            },
            set: {
                reminderHour = Calendar.current.component(.hour, from: $0)
                reminderMinute = Calendar.current.component(.minute, from: $0)
            }
        )
    }

    private func enableReminders() {
        // UI tests promise no system dialogs (AppLaunch.isUITesting).
        guard !AppLaunch.isUITesting else { go(to: .health); return }
        isRequestingPermission = true
        Task {
            let granted = await notificationService.requestAuthorization()
            appState.notificationsAuthorized = granted
            isRequestingPermission = false
            guard granted else {
                notificationsDeclined = true
                return
            }
            notificationService.scheduleDailyReminder(at: reminderHour, minute: reminderMinute)
            let weeklyOn = UserDefaults.standard.object(forKey: UserDefaultsKey.weeklyReminderEnabled) as? Bool ?? true
            if weeklyOn { notificationService.scheduleWeeklyReviewReminder() }
            go(to: .health)
        }
    }

    // MARK: - Symptoms

    // Starts from whatever the store already holds (a reinstall over an
    // existing iCloud database), otherwise the five seeded defaults.
    private func loadSymptomSelection() {
        guard !didLoadSymptoms else { return }
        didLoadSymptoms = true
        let existing = ((try? modelContext.fetch(FetchDescriptor<SymptomTag>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []).map(\.name)
        selectedSymptoms = existing.isEmpty ? SymptomTag.defaultSeeds.map(\.name) : existing
    }

    // Inserts the chosen tags the store lacks and marks seeding done, so
    // ContentView's first-launch seeding doesn't re-add defaults the person
    // just deselected. Never deletes a tag that existed before onboarding.
    private func saveSymptomSelection() {
        let existing = (try? modelContext.fetch(FetchDescriptor<SymptomTag>())) ?? []
        let existingNames = Set(existing.map(\.name))
        let defaults = Set(SymptomTag.defaultSeeds.map(\.name))
        let emojiByName = Dictionary(
            (SymptomTag.defaultSeeds + SymptomTag.optionalCatalog).map { ($0.name, $0.emoji) },
            uniquingKeysWith: { first, _ in first }
        )
        var added: [SymptomTag] = []
        var removed: [SymptomTag] = []
        for (index, name) in selectedSymptoms.enumerated() where !existingNames.contains(name) {
            let tag = SymptomTag(name: name, emoji: emojiByName[name] ?? "🔵", isDefault: defaults.contains(name), sortOrder: index)
            modelContext.insert(tag)
            added.append(tag)
        }
        for tag in existing where insertedSymptoms.contains(tag.name) && !selectedSymptoms.contains(tag.name) {
            modelContext.delete(tag)
            removed.append(tag)
        }
        do {
            try modelContext.save()
            insertedSymptoms.formUnion(added.map(\.name))
            insertedSymptoms.subtract(removed.map(\.name))
            if !AppLaunch.isUITesting {
                UserDefaults.standard.set(true, forKey: UserDefaultsKey.symptomTagsSeeded)
            }
        } catch {
            // Not fatal: first-launch seeding still runs, and Settings → Symptoms
            // can change the list later.
            added.forEach(modelContext.delete)
            Self.log.error("Failed to save onboarding symptoms: \(error, privacy: .public)")
        }
    }
}

// MARK: - Step machine

enum OnboardingStep: Int, CaseIterable {
    case welcome, symptoms, reminders, health, ready

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

// MARK: - Symptom chips

private struct SymptomChoiceGrid: View {
    @Binding var selection: [String]

    private var choices: [(name: String, emoji: String)] {
        SymptomTag.defaultSeeds + SymptomTag.optionalCatalog.filter { item in
            !SymptomTag.defaultSeeds.contains { $0.name == item.name }
        }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(choices, id: \.name) { choice in
                let isOn = selection.contains(choice.name)
                Button {
                    if isOn {
                        selection.removeAll { $0 == choice.name }
                    } else {
                        selection.append(choice.name)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(choice.emoji)
                        Text(choice.name)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CadenceColor.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(isOn ? CadenceColor.accent.opacity(0.14) : Color(.secondarySystemGroupedBackground).opacity(0.8),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(isOn ? CadenceColor.accent : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: choice.name))
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                .accessibilityHint(isOn ? Text("Double-tap to stop tracking") : Text("Double-tap to track"))
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Page layout

// Scrolling content over a fixed bottom bar: at the largest accessibility
// text sizes the old fixed layout truncated the welcome text mid-sentence,
// and the buttons are what must never be pushed off screen.
private struct OnboardingPage<Content: View>: View {
    let step: OnboardingStep
    let pose: WidgetData.MascotPose
    // LocalizedStringKey, not String: Strings reach Text through its
    // non-localizing overload, which is how onboarding once shipped English-only.
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var isBusy: Bool = false
    let primaryLabel: LocalizedStringKey
    let primaryAction: () -> Void
    var secondaryLabel: LocalizedStringKey? = nil
    var secondaryAction: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: Content

    @ScaledMetric(relativeTo: .largeTitle) private var mascotSize: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                    .tint(CadenceColor.accent)
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, 8)

            ScrollView {
                VStack(spacing: 20) {
                    // One illustration family: the mascot on every page,
                    // instead of the mascot once and three unrelated filled
                    // SF Symbols in three unrelated colours.
                    Image(pose.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(mascotSize, 220), height: min(mascotSize, 220))
                        .foregroundStyle(CadenceColor.accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableColumn()
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    HStack(spacing: 8) {
                        if isBusy { ProgressView().tint(.white) }
                        Text(primaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CadenceColor.accent)
                .controlSize(.large)

                if let secondaryLabel, let secondaryAction {
                    Button(secondaryLabel, action: secondaryAction)
                        .font(.body.weight(.medium))
                        .tint(CadenceColor.accent)
                        .frame(minHeight: 44)
                }

                pageDots
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .readableColumn()
        }
    }

    // Five dots so the length of onboarding is never a mystery.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { page in
                Capsule()
                    .fill(page == step ? CadenceColor.accent : Color(.systemFill))
                    .frame(width: page == step ? 22 : 8, height: 8)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}

extension OnboardingPage where Content == EmptyView {
    init(step: OnboardingStep, pose: WidgetData.MascotPose, title: LocalizedStringKey, message: LocalizedStringKey,
         isBusy: Bool = false, primaryLabel: LocalizedStringKey, primaryAction: @escaping () -> Void,
         secondaryLabel: LocalizedStringKey? = nil, secondaryAction: (() -> Void)? = nil, onBack: (() -> Void)? = nil) {
        self.init(step: step, pose: pose, title: title, message: message, isBusy: isBusy,
                  primaryLabel: primaryLabel, primaryAction: primaryAction,
                  secondaryLabel: secondaryLabel, secondaryAction: secondaryAction,
                  onBack: onBack, content: { EmptyView() })
    }
}
