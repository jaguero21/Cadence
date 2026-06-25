import SwiftUI
import SwiftData
import UserNotifications
import OSLog


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
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self])
        // CloudKit mirroring: syncs across the user's devices once the iCloud +
        // CloudKit capability is enabled on the target. If the entitlement is
        // absent (e.g. a build without iCloud), this init fails and we fall back
        // to a local-only store below, so the app still works offline.
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }
        // Local-only persistent store (no CloudKit) — used when the iCloud
        // entitlement isn't present or CloudKit setup fails.
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
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
                                    let hour   = ud.object(forKey: UserDefaultsKey.dailyReminderHour)   as? Int  ?? 20
                                    let minute = ud.object(forKey: UserDefaultsKey.dailyReminderMinute) as? Int  ?? 0
                                    NotificationService.shared.scheduleDailyReminder(at: hour, minute: minute)
                                    let weeklyOn = ud.object(forKey: UserDefaultsKey.weeklyReminderEnabled) as? Bool ?? true
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
                .task { PhoneConnectivityManager.shared.start(container: container) }
            } else {
                StorageFatalErrorView()
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(StoreService.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationService) private var notificationService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .dashboard
    @State private var showStorageWarning = CadenceApp.usingFallbackStorage
    // The current day, refreshed when the app returns to foreground. Passed into
    // each date-windowed tab so a midnight rollover updates their @Query in place
    // rather than rebuilding the subtree (which dropped open sheets / scroll
    // state). HistoryView isn't date-windowed, so it doesn't take it.
    @State private var today = Calendar.current.startOfDay(for: .now)

    private let symptomSeedKey = UserDefaultsKey.symptomTagsSeeded
    private static let log = Logger(subsystem: "com.carpecadence", category: "ContentView")

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $selectedTab) {
            DashboardView(referenceDate: today)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(Tab.dashboard)

            DailyLogView(referenceDate: today)
                .tabItem { Label("Log", systemImage: "pencil.and.list.clipboard") }
                .tag(Tab.dailyLog)

            WeeklyReviewView(referenceDate: today)
                .tabItem { Label("Review", systemImage: "calendar.badge.checkmark") }
                .tag(Tab.weeklyReview)

            InsightsView(referenceDate: today)
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.insights)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .tint(CadenceColor.accent)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let startOfToday = Calendar.current.startOfDay(for: .now)
            if startOfToday != today { today = startOfToday }
            checkForNewInsights()
        }
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

    // On foreground, recompute insights, persist any newly-emerged patterns, and
    // notify the user about the most confident new one (Pro only — insights are a
    // Pro feature). Recording is idempotent, so this notifies once per pattern.
    private func checkForNewInsights() {
        guard store.isPro else { return }
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        guard logs.count >= PatternThreshold.minimumLogs else { return }
        let medications = (try? modelContext.fetch(FetchDescriptor<Medication>())) ?? []
        let insights = PatternEngine.allInsights(
            from: logs.map(DailyLogSnapshot.init),
            medications: medications.map(MedicationSnapshot.init)
        )
        let new = InsightRecorder.record(insights, context: modelContext)
        if let top = new.filter({ $0.confidence >= PatternThreshold.minimumConfidence })
            .max(by: { $0.confidence < $1.confidence }) {
            notificationService.sendInsightNotification(title: top.title)
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
            Self.log.error("Failed to seed SymptomTag defaults: \(error, privacy: .public)")
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
