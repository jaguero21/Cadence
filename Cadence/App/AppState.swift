import SwiftUI

@MainActor
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool = false
    var showingProPaywall: Bool = false
    var notificationsAuthorized: Bool = false
    var healthKitAuthorized: Bool = false

    init() {
        // UI tests always start at onboarding and never persist the flag.
        guard !AppLaunch.isUITesting else { return }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKey.onboarded)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        guard !AppLaunch.isUITesting else { return }
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.onboarded)
    }
}
