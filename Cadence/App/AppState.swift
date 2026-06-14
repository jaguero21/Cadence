import SwiftUI

@MainActor
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool = false
    var showingProPaywall: Bool = false
    var notificationsAuthorized: Bool = false
    var healthKitAuthorized: Bool = false

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKey.onboarded)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.onboarded)
    }
}
