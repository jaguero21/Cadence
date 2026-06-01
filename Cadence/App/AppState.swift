import SwiftUI
import Combine

@MainActor
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool = false
    var showingProPaywall: Bool = false
    var notificationsAuthorized: Bool = false
    var healthKitAuthorized: Bool = false

    private let onboardingKey = "cadence.onboarded"

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }
}
