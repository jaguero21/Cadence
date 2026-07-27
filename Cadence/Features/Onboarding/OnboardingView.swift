import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    @State private var isRequestingPermission = false

    var body: some View {
        ZStack {
            CadenceColor.background.ignoresSafeArea()
            Group {
                switch step {
                case .welcome:       welcomePage
                case .notifications: notificationsPage
                case .healthKit:     healthKitPage
                case .ready:         readyPage
                }
            }
            .transition(.cadenceStepSlide(reduceMotion: reduceMotion))
            .id(step)
            .readableColumn()

            VStack {
                Spacer()
                pageDots
                    .padding(.bottom, 12)
            }
        }
    }

    // Four dots so the length of onboarding is never a mystery.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.offset) { index, page in
                Capsule()
                    .fill(page == step ? CadenceColor.accent : Color(.systemFill))
                    .frame(width: page == step ? 22 : 8, height: 8)
                    .animation(CadenceAnimation.spring, value: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((OnboardingStep.allCases.firstIndex(of: step) ?? 0) + 1) of \(OnboardingStep.allCases.count)")
    }

    private func advance() {
        withAnimation(CadenceAnimation.spring) { step = step.next }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPage(
            icon: "waveform.path.ecg.rectangle.fill",
            iconColor: CadenceColor.accent,
            title: "Welcome to Cadence",
            message: "Track how you feel, sleep, and move — in under two minutes a day. Over time, Cadence finds patterns you wouldn't notice on your own.",
            primaryLabel: "Get Started",
            primaryAction: advance,
            mascotPose: .welcoming
        )
    }

    private var notificationsPage: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: CadenceColor.moodBlue,
            title: "Stay consistent",
            message: "A gentle reminder at the right time keeps your streak alive. You choose when — and you can always change it in Settings.",
            isBusy: isRequestingPermission,
            primaryLabel: "Enable Reminders",
            primaryAction: {
                isRequestingPermission = true
                Task {
                    appState.notificationsAuthorized = await notificationService.requestAuthorization()
                    if appState.notificationsAuthorized {
                        let ud = UserDefaults.standard
                        notificationService.scheduleDailyReminder(
                            at:     ud.object(forKey: UserDefaultsKey.dailyReminderHour)   as? Int ?? 20,
                            minute: ud.object(forKey: UserDefaultsKey.dailyReminderMinute) as? Int ?? 0
                        )
                        let weeklyOn = ud.object(forKey: UserDefaultsKey.weeklyReminderEnabled) as? Bool ?? true
                        if weeklyOn { notificationService.scheduleWeeklyReviewReminder() }
                    }
                    isRequestingPermission = false
                    advance()
                }
            },
            skipAction: advance
        )
        .disabled(isRequestingPermission)
    }

    private var healthKitPage: some View {
        OnboardingPage(
            icon: "heart.text.square.fill",
            iconColor: CadenceColor.stressRed,
            title: "Less typing, more insight",
            message: "Connect Apple Health to auto-fill sleep, activity, cycle data and more — and keep your logged symptoms and mood in your health record. You'll choose exactly what to share, and everything still works without it.",
            isBusy: isRequestingPermission,
            primaryLabel: "Connect Apple Health",
            primaryAction: {
                isRequestingPermission = true
                Task {
                    appState.healthKitAuthorized = (try? await healthKitService.requestAuthorization()) ?? healthKitService.isAuthorized
                    isRequestingPermission = false
                    advance()
                }
            },
            skipAction: advance
        )
        .disabled(isRequestingPermission)
    }

    private var readyPage: some View {
        OnboardingPage(
            icon: "checkmark.seal.fill",
            iconColor: CadenceColor.successGreen,
            title: "You're all set!",
            message: "Your first log is waiting. It takes about 90 seconds — and every entry helps Cadence understand your patterns.",
            primaryLabel: "Open Cadence",
            primaryAction: { appState.completeOnboarding() }
        )
    }
}

// MARK: - Step machine

private enum OnboardingStep: CaseIterable {
    case welcome, notifications, healthKit, ready

    var next: OnboardingStep {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return i + 1 < all.count ? all[i + 1] : self
    }
}

// MARK: - Page layout

private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    var isBusy: Bool = false
    let primaryLabel: String
    let primaryAction: () -> Void
    var skipAction: (() -> Void)? = nil
    // Set only by the welcome page. Replaces the SF Symbol rather than
    // sitting alongside it — decorative, so it's accessibilityHidden; the
    // title/message text below already carries the page's meaning.
    var mascotPose: WidgetData.MascotPose? = nil

    @State private var iconAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                if let mascotPose {
                    Image(mascotPose.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(iconColor)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 80))
                        .foregroundStyle(iconColor)
                        .cadenceSymbolBounce(value: iconAppeared)
                        .onAppear { iconAppeared = true }
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    primaryAction()
                } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(primaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CadenceColor.accent)
                .controlSize(.large)

                if let skipAction {
                    Button("Skip", action: skipAction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }
}
