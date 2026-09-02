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
    // Mirrors the static so a successful retry from StorageFatalErrorView
    // re-renders the scene into the real app.
    @State private var container: ModelContainer? = CadenceApp.sharedModelContainer

    // Set when the persistent store failed and we fell back to in-memory storage.
    static private(set) var usingFallbackStorage = false
    // Set when even the in-memory fallback failed; app runs without SwiftData.
    static private(set) var containerFailed = false
    // Set when the CloudKit-mirrored store initialised (vs the local-only
    // fallback). CloudSyncMonitor uses this to show a truthful sync status.
    static private(set) var usingCloudKitStore = false
    // Whether a PERSISTENT store has ever opened on this device. Recorded the
    // first time one does, and read only when we've fallen back to in-memory:
    // it's the difference between "you have nothing saved yet, reinstalling is
    // harmless" and "your entries are on disk, deleting the app destroys them".
    // Getting that advice backwards is how a recoverable failure becomes
    // permanent data loss, so it is worth one UserDefaults flag.
    static var hadPersistentStore: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKey.persistentStoreOpened)
    }

    private static let log = Logger(subsystem: "com.carpecadence", category: "Storage")

    // Static so App Intents (which run outside the SwiftUI scene) reach the
    // same container the UI uses; `static let` keeps it single-init even if
    // the App struct is re-created.
    static private(set) var sharedModelContainer: ModelContainer? = makeContainer()

    // Retry hook for StorageFatalErrorView. Every tier below can fail for a
    // reason that is gone a moment later — a device that just booted has not
    // made protected files readable yet — and before this the only recovery a
    // user could reach was force-quitting the app themselves. @MainActor so the
    // one reassignment only ever happens from the scene showing the failure.
    @MainActor
    static func retryMakingContainer() -> ModelContainer? {
        guard sharedModelContainer == nil else { return sharedModelContainer }
        containerFailed = false
        usingFallbackStorage = false
        sharedModelContainer = makeContainer()
        return sharedModelContainer
    }

    private static func makeContainer() -> ModelContainer? {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        // TWO stores, on purpose.
        //
        // `syncedModels` carry what the USER entered and are mirrored to
        // CloudKit. `localModels` hold the objective HealthKit measurements and
        // are NEVER mirrored: App Review Guideline 5.1.3(ii) says an app "may
        // not store personal health information in iCloud", and HealthKit-
        // sourced values are the least defensible thing to put there. Splitting
        // keeps cross-device sync for the diary while HealthKit data stays on
        // the device that read it.
        //
        // SwiftData cannot relate models across stores, so DailyLog and
        // HealthSnapshot are joined by date — see DailyLogSnapshot.build(from:in:).
        let syncedModels: [any PersistentModel.Type] = [
            DailyLog.self, WeeklyReview.self, SymptomTag.self,
            Medication.self, Flare.self, CustomTracker.self, InsightRecord.self,
        ]
        let localModels: [any PersistentModel.Type] = [HealthSnapshot.self]
        let syncedSchema = Schema(syncedModels)
        let localSchema  = Schema(localModels)
        let fullSchema   = Schema(syncedModels + localModels)

        // UI tests get an isolated in-memory store so runs are deterministic.
        if AppLaunch.isUITesting {
            let testConfig = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
            return try? ModelContainer(for: fullSchema, configurations: [testConfig])
        }

        // Named, so it lands in its own file alongside the main store. The
        // synced configuration below stays UNNAMED on purpose: that keeps it on
        // "default.store", where every existing install's data already lives —
        // naming it would point the app at an empty new file and read as total
        // data loss on upgrade.
        let healthConfig = ModelConfiguration(
            "LocalHealth", schema: localSchema,
            isStoredInMemoryOnly: false, cloudKitDatabase: .none
        )

        // CloudKit mirroring: syncs across the user's devices once the iCloud +
        // CloudKit capability is enabled on the target. If the entitlement is
        // absent (e.g. a build without iCloud), this init fails and we fall back
        // to a local-only store below, so the app still works offline.
        //
        // Each tier is do/catch rather than `try?` ON PURPOSE. The store either
        // opening or not is the single highest-stakes thing that happens at
        // launch, and the thrown error is the ONLY description of why it didn't
        // — there is no second chance to ask. Discarding it (as `try?` did) left
        // a failed schema migration and a corrupt file looking identical, and
        // both looking like an ordinary first run.
        let cloudConfig = ModelConfiguration(schema: syncedSchema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        do {
            let container = try ModelContainer(for: fullSchema, configurations: [cloudConfig, healthConfig])
            CadenceApp.usingCloudKitStore = true
            CadenceApp.recordPersistentStoreOpened()
            return container
        } catch {
            // Routine: no iCloud entitlement, or no account signed in. The tier
            // below opens the SAME file, so this costs sync, not data.
            log.notice("CloudKit store unavailable, trying local-only: \(error.localizedDescription, privacy: .public)")
        }
        // Local-only persistent store (no CloudKit) — used when the iCloud
        // entitlement isn't present or CloudKit setup fails. Health data is
        // already local; only the synced half changes behaviour here.
        let localOnlyConfig = ModelConfiguration(schema: syncedSchema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: fullSchema, configurations: [localOnlyConfig, healthConfig])
            CadenceApp.recordPersistentStoreOpened()
            return container
        } catch {
            // NOT routine. Both persistent tiers point at the same file, so
            // reaching here means the store itself would not open — a failed
            // schema migration or a damaged file — and the user is about to be
            // dropped onto volatile storage. Log it at error level; it is the
            // only diagnostic that will exist.
            log.error("Persistent store failed to open, falling back to in-memory: \(error.localizedDescription, privacy: .public)")
        }
        CadenceApp.usingFallbackStorage = true
        let fallbackConfig = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: fullSchema, configurations: [fallbackConfig])
        } catch {
            log.error("In-memory fallback container failed: \(error.localizedDescription, privacy: .public)")
        }
        CadenceApp.containerFailed = true
        return nil
    }

    // Latches the flag `hadPersistentStore` reads. Never cleared: once real
    // entries have been written to disk, "reinstalling is safe" stops being
    // true for this device even if a later launch opens the store fine.
    private static func recordPersistentStoreOpened() {
        guard !AppLaunch.isUITesting else { return }
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.persistentStoreOpened)
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                Group {
                    if appState.hasCompletedOnboarding {
                        ContentView()
                            .task {
                                // READS permission state; never requests it.
                                // Onboarding is the only place that prompts, so
                                // that "Skip" actually skips — this task used to
                                // call requestAuthorization() unconditionally,
                                // which fired both system prompts moments after
                                // the user declined them, stripped of the screens
                                // that explained why. Settings re-offers Health,
                                // and iOS's own Settings re-offers notifications.
                                guard !AppLaunch.isUITesting else { return }
                                appState.notificationsAuthorized = await NotificationService.shared.checkAuthorizationStatus()
                                appState.healthKitAuthorized = HealthKitService.shared.isAuthorized
                                // Re-arm the recurring reminders on every launch
                                // when permission is in place — including when it
                                // was granted later in iOS Settings rather than
                                // during onboarding.
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
                    // Load the Pro entitlement before any gated surface reads
                    // `store.isPro`. Its own `.task` (not folded into the one
                    // below) so a slow StoreKit round-trip can't delay starting
                    // the HealthKit observers.
                    guard !AppLaunch.isUITesting else { return }
                    await store.refreshEntitlements()
                }
                .task {
                    // Clear generated reports/CSV/backups left in scratch by
                    // earlier sessions — a full health history in plain text
                    // should not outlive the share that produced it. Done at
                    // launch rather than after each share, because the share
                    // sheet hands the URL to another process.
                    ExportScratch.purge()
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
                StorageFatalErrorView {
                    container = CadenceApp.retryMakingContainer()
                }
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
            syncMedicationReminders()
        }
        .task { seedSymptomTagsIfNeeded() }
        .task { syncMedicationReminders() }
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
            // Two messages, not one with a ternary: `Text(cond ? "a" : "b")`
            // resolves to the non-localizing StringProtocol initializer and
            // would drop both strings out of the catalog.
            //
            // The old single message said "your data is safe" and then advised
            // deleting and reinstalling the app — the one action that turns a
            // recoverable failure (a store that wouldn't migrate) into
            // permanent loss. Which advice is safe depends entirely on whether
            // anything was ever written to disk here.
            if CadenceApp.hadPersistentStore {
                Text("Cadence is running on temporary storage, so anything you log right now won't be kept. Your saved entries are still on this device — don't delete Cadence, that would erase them. Force-quit and reopen, and update to the latest version if this keeps happening.")
            } else {
                Text("Cadence couldn't open its database and is running on temporary storage, so anything you log right now won't be kept. Force-quit and reopen. Nothing has been saved on this device yet, so reinstalling is safe if this keeps happening.")
            }
        }
    }

    // On foreground, reconcile scheduled medication reminders with the store —
    // this is what silences reminders for a course whose end date has passed
    // (or one deleted on another device via CloudKit) without the user
    // touching the medication screen.
    private func syncMedicationReminders() {
        notificationService.reconcileMedicationReminders(context: modelContext)
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
        var appliedDays: Set<Date> = []
        var failed: [WidgetData.PendingQuickLog] = []
        for entry in pending {
            if PhoneConnectivityManager.applyQuickLog(entry.payload, context: modelContext) {
                appliedDays.insert(Calendar.current.startOfDay(for: entry.date))
            } else {
                failed.append(entry)
            }
        }
        if !failed.isEmpty {
            // A save failure (disk full, store error) must not drop the tap —
            // re-stash it so the next foreground retries instead of stranding
            // the widget's "mood saved" state on data that never landed.
            WidgetData.restorePendingQuickLogs(failed)
        }
        if !appliedDays.isEmpty {
            let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
            DashboardViewModel.publishWidgetSummary(logs: logs, activeFlare: DashboardViewModel.activeFlare(in: modelContext))
            // publishWidgetSummary skips its reload when the summary is
            // unchanged — and a quick log doesn't complete the day, so it
            // usually is. Reload explicitly so the widget's interim
            // "mood saved" state clears now that the tap is store-backed.
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetData.widgetKind)
            // Mirror the applied days' moods into Health's State of Mind —
            // a widget tap is still a check-in. Best-effort, fire-and-forget.
            let snapshots = logs.filter { appliedDays.contains($0.date) }.map { DailyLogSnapshot($0) }
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
    // Without this the screen is a dead end: no focusable element for VoiceOver
    // or Switch Control, and no way to recover from a failure that is often
    // transient. Defaulted so previews still construct the view bare.
    var onRetry: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Cadence can't start")
                    .font(.title2.bold())
                // Never advise reinstalling here: this screen appears when the
                // store could not be opened, which is usually recoverable, and
                // deleting the app is what makes it permanent.
                Text("Cadence's data storage wouldn't start. Please force-quit and reopen. If you've logged entries before, they're still on this device — don't delete Cadence, that would erase them. Update to the latest version if this keeps happening.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Text("Try Again")
                    .font(.body.bold())
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(CadenceColor.accent)
        }
        .padding(32)
    }
}

enum Tab: Hashable {
    case dashboard, dailyLog, weeklyReview, insights, history
}
