import SwiftUI
import SwiftData
import UserNotifications


@main
struct CadenceApp: App {
    @State private var appState = AppState()
    @State private var store = StoreService.shared

    // Set when the persistent store failed and we fell back to in-memory storage.
    static private(set) var usingFallbackStorage = false
    // Set when even the in-memory fallback failed; app runs without SwiftData.
    static private(set) var containerFailed = false

    var sharedModelContainer: ModelContainer? = {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [persistentConfig]) {
            return container
        }
        CadenceApp.usingFallbackStorage = true
        let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let fallback = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
            return fallback
        }
        CadenceApp.containerFailed = true
        return nil
    }()

    var body: some Scene {
        WindowGroup {
            if let container = sharedModelContainer {
                Group {
                    if appState.hasCompletedOnboarding {
                        ContentView()
                            .task {
                                appState.notificationsAuthorized = await NotificationService.shared.requestAuthorization()
                                appState.healthKitAuthorized = (try? await HealthKitService.shared.requestAuthorization()) ?? HealthKitService.shared.isAuthorized
                                if appState.notificationsAuthorized {
                                    let ud     = UserDefaults.standard
                                    let hour   = ud.object(forKey: "dailyReminderHour")   as? Int  ?? 20
                                    let minute = ud.object(forKey: "dailyReminderMinute") as? Int  ?? 0
                                    NotificationService.shared.scheduleDailyReminder(at: hour, minute: minute)
                                    let weeklyOn = ud.object(forKey: "weeklyReminderEnabled") as? Bool ?? true
                                    if weeklyOn { NotificationService.shared.scheduleWeeklyReviewReminder() }
                                }
                            }
                    } else {
                        OnboardingView()
                    }
                }
                .environment(appState)
                .environment(store)
                .modelContainer(container)
            } else {
                StorageFatalErrorView()
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .dashboard
    @State private var showStorageWarning = CadenceApp.usingFallbackStorage

    private let symptomSeedKey = "cadence.symptomTagsSeeded"

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(Tab.dashboard)

            DailyLogView()
                .tabItem { Label("Log", systemImage: "pencil.and.list.clipboard") }
                .tag(Tab.dailyLog)

            WeeklyReviewView()
                .tabItem { Label("Review", systemImage: "calendar.badge.checkmark") }
                .tag(Tab.weeklyReview)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.insights)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .tint(CadenceColor.accent)
        .task { seedSymptomTagsIfNeeded() }
        .sheet(isPresented: $appState.showingProPaywall) {
            ProPaywallView()
        }
        .alert("Storage Unavailable", isPresented: $showStorageWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cadence couldn't open its database (a migration may be needed). Your data is safe, but changes made this session won't be saved. Try deleting and reinstalling the app if this persists.")
        }
    }

    private func seedSymptomTagsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: symptomSeedKey) else { return }
        for tag in SymptomTag.defaults { modelContext.insert(tag) }
        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: symptomSeedKey)
        } catch {
            // Leave the flag unset so the next launch retries seeding.
        }
    }
}

// Shown when both the persistent and in-memory ModelContainer fail to initialise.
struct StorageFatalErrorView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Cadence can't start")
                    .font(.title2.bold())
                Text("The app's data storage failed to initialise. Please force-quit and reopen. If the problem persists, reinstall the app — your health data in Apple Health is unaffected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Force Quit") {
                exit(1)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(32)
    }
}

enum Tab: Hashable {
    case dashboard, dailyLog, weeklyReview, insights, history
}
