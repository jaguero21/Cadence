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
    // Set by onboarding's "Log how today feels": ContentView opens today's
    // log as soon as it appears, so the first entry is one tap away.
    var pendingFirstLog = false

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
