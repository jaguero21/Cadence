import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
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
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .id(step)
        }
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
            primaryAction: advance
        )
    }

    private var notificationsPage: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: CadenceColor.moodBlue,
            title: "Stay consistent",
            message: "A gentle reminder at the right time keeps your streak alive. You choose when — and you can always change it in Settings.",
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
            message: "Connect Apple Health to auto-fill your sleep, heart rate, and step count — so logging is faster and patterns emerge sooner.",
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
    let primaryLabel: String
    let primaryAction: () -> Void
    var skipAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundStyle(iconColor)

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
                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(CadenceColor.accent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

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
