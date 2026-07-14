import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit
import TipKit
import OSLog


@main
struct CadenceApp: App {
    @State private var appState = AppState()
    @State private var store = StoreService.shared

    // Set when the persistent store failed and we fell back to in-memory storage.
    static private(set) var usingFallbackStorage = false
    // Set when even the in-memory fallback failed; app runs without SwiftData.
    static private(set) var containerFailed = false
    // Set when the CloudKit-mirrored store initialised (vs the local-only
    // fallback). CloudSyncMonitor uses this to show a truthful sync status.
    static private(set) var usingCloudKitStore = false

    // Static so App Intents (which run outside the SwiftUI scene) reach the
    // same container the UI uses; `static let` keeps it single-init even if
    // the App struct is re-created.
    static let sharedModelContainer: ModelContainer? = {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self, Flare.self, CustomTracker.self, InsightRecord.self])
        // UI tests get an isolated in-memory store so runs are deterministic.
        if AppLaunch.isUITesting {
            let testConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try? ModelContainer(for: schema, configurations: [testConfig])
        }
        // CloudKit mirroring: syncs across the user's devices once the iCloud +
        // CloudKit capability is enabled on the target. If the entitlement is
        // absent (e.g. a build without iCloud), this init fails and we fall back
        // to a local-only store below, so the app still works offline.
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            CadenceApp.usingCloudKitStore = true
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
            if let container = Self.sharedModelContainer {
                Group {
                    if appState.hasCompletedOnboarding {
                        ContentView()
                            .task {
                                // No system permission prompts during UI tests.
                                guard !AppLaunch.isUITesting else { return }
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
                .task {
                    PhoneConnectivityManager.shared.start(container: container)
                    guard !AppLaunch.isUITesting else { return }
                    // Discoverability tips (hold-to-rate, step jumping). Not
                    // configured under UI tests — an unexpected tip popover
                    // could block the smoke test's taps.
                    try? Tips.configure()
                    // Keep today's log's HealthKit numbers fresh (end-of-day
                    // steps, morning sleep) even when the log flow isn't
                    // opened again; wakes the app when suspended via HK
                    // background delivery.
                    HealthKitService.shared.startObservingChanges {
                        await HealthDataRefresher.refreshToday(container: container)
                    }
                }
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
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .dashboard
    @State private var showStorageWarning = CadenceApp.usingFallbackStorage
    // Control Center "Log Check-In" button: the control stashes an open
    // request (it runs in the widget extension); we consume it on foreground
    // and present today's log directly.
    @State private var showingControlCheckIn = false
    @State private var controlCheckInLog: DailyLog?
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
        // iPad: top tab bar with a switchable sidebar (iOS 18); iPhone unchanged.
        .adaptableTabBar()
        // iOS 26: the tab bar tucks away while scrolling charts/history.
        .minimizableTabBar()
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let startOfToday = Calendar.current.startOfDay(for: .now)
            if startOfToday != today { today = startOfToday }
            applyPendingQuickLogs()
            checkForNewInsights()
            refreshTodayHealthData()
            openCheckInIfRequested()
        }
        .task { seedSymptomTagsIfNeeded() }
        .task { applyPendingQuickLogs() }
        .task { openCheckInIfRequested() }
        .sheet(isPresented: $showingControlCheckIn) {
            LogInputFlow(existingLog: controlCheckInLog)
        }
        .sheet(isPresented: $appState.showingProPaywall) {
            ProPaywallView()
        }
        .alert("Storage Unavailable", isPresented: $showStorageWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cadence couldn't open its database (a migration may be needed). Your data is safe, but changes made this session won't be saved. Try deleting and reinstalling the app if this persists.")
        }
    }

    // On foreground, recompute insights via the shared pipeline (same 90-day
    // window and inputs as the Insights tab, so a notification can never
    // advertise a pattern the tab doesn't show), persist newly-emerged ones,
    // and notify about the most confident new pattern (Pro only). Throttled to
    // once per calendar day — patterns move on daily granularity, and running
    // the engine on every unlock/app-switch is wasted main-thread work.
    private func checkForNewInsights() {
        guard store.isPro else { return }
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let lastCheck = UserDefaults.standard.double(forKey: UserDefaultsKey.lastInsightCheckDay)
        guard lastCheck != startOfToday.timeIntervalSinceReferenceDate else { return }
        UserDefaults.standard.set(startOfToday.timeIntervalSinceReferenceDate, forKey: UserDefaultsKey.lastInsightCheckDay)

        let new = InsightRecorder.detectAndRecord(context: modelContext)
        if let top = new.filter({ $0.confidence >= PatternThreshold.minimumConfidence })
            .max(by: { $0.confidence < $1.confidence }) {
            notificationService.sendInsightNotification(title: top.title)
        }
    }

    // Consume a Control Center "Log Check-In" tap: fetch today's log (if any)
    // and present the flow, exactly as tapping the dashboard card would.
    private func openCheckInIfRequested() {
        guard !AppLaunch.isUITesting,
              WidgetData.consumeCheckInOpenRequest(),
              !showingControlCheckIn else { return }
        let today = Calendar.current.startOfDay(for: .now)
        controlCheckInLog = try? modelContext.fetch(
            FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == today })
        ).first
        selectedTab = .dashboard
        showingControlCheckIn = true
    }

    // Foreground fallback for the HK observer path: top up today's log's
    // objective HealthKit fields on every return to the app, so the numbers
    // stay current even if background delivery is unavailable.
    private func refreshTodayHealthData() {
        guard !AppLaunch.isUITesting else { return }
        let service = healthKitService
        let context = modelContext
        Task {
            let snapshot = await service.fetchLogSnapshot()
            HealthDataRefresher.refreshToday(context: context, snapshot: snapshot)
        }
    }

    // Persist mood taps made on the widget since the last foreground. Each tap
    // carries the day it was made, and the upsert seam attributes it there — a
    // tap from last night lands on yesterday's log, never clobbering today.
    // After applying, the summary is republished so the widget's "mood saved"
    // interim state resolves to real store-backed data.
    private func applyPendingQuickLogs() {
        guard !AppLaunch.isUITesting else { return }
        let pending = WidgetData.consumePendingQuickLogs()
        guard !pending.isEmpty else { return }
        var applied = false
        for entry in pending {
            if PhoneConnectivityManager.applyQuickLog(entry.payload, context: modelContext) {
                applied = true
            }
        }
        if applied {
            let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
            DashboardViewModel.publishWidgetSummary(logs: logs)
            // publishWidgetSummary skips its reload when the summary is
            // unchanged — and a quick log doesn't complete the day, so it
            // usually is. Reload explicitly so the widget's interim
            // "mood saved" state clears now that the tap is store-backed.
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetData.widgetKind)
            // Mirror the applied days' moods into Health's State of Mind —
            // a widget tap is still a check-in. Best-effort, fire-and-forget.
            let appliedDays = Set(pending.map { Calendar.current.startOfDay(for: $0.date) })
            let snapshots = logs.filter { appliedDays.contains($0.date) }.map(DailyLogSnapshot.init)
            let service = healthKitService
            Task {
                for snapshot in snapshots {
                    await service.publish(log: snapshot)
                }
            }
        }
    }

    private func seedSymptomTagsIfNeeded() {
        // UI tests: the in-memory store starts empty every run, but standard
        // UserDefaults persist on the simulator — honoring the seeded flag
        // would skip seeding forever after the first run and leave the picker
        // with no chips. Always seed under --uitest (name-dedup keeps it
        // idempotent) and never persist the flag there.
        guard AppLaunch.isUITesting || !UserDefaults.standard.bool(forKey: symptomSeedKey) else { return }
        // Dedup against tags already in the store (reinstall over an existing
        // CloudKit database, or a sync that landed before first launch). A
        // second device seeding before its first sync completes can still race;
        // name-based dedup here covers every case where the data is visible.
        let existingNames = Set(((try? modelContext.fetch(FetchDescriptor<SymptomTag>())) ?? []).map(\.name))
        for tag in SymptomTag.defaults where !existingNames.contains(tag.name) {
            modelContext.insert(tag)
        }
        do {
            try modelContext.save()
            if !AppLaunch.isUITesting {
                UserDefaults.standard.set(true, forKey: symptomSeedKey)
            }
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
