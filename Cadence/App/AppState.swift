import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    @Published var showingProPaywall: Bool = false
    @Published var notificationsAuthorized: Bool = false
    @Published var healthKitAuthorized: Bool = false

    private let onboardingKey = "cadence.onboarded"

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }
}
