import SwiftUI

@MainActor
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool = false
    var showingProPaywall: Bool = false
    var notificationsAuthorized: Bool = false
    var healthKitAuthorized: Bool = false
    // Set by child views that want the tab bar to switch (e.g. the Dashboard's
    // Top Pattern card); ContentView consumes it. Avoids pushing a tab's root
    // view, which carries its own NavigationStack, into another stack.
    var requestedTab: Tab?

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
