import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Schema versions

enum CadenceSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [DailyLog.self, WeeklyReview.self, SymptomTag.self] }
}

enum CadenceSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [DailyLog.self, WeeklyReview.self, SymptomTag.self] }
}

enum CadenceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CadenceSchemaV1.self, CadenceSchemaV2.self] }
    static var stages: [MigrationStage] { [v1ToV2] }
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: CadenceSchemaV1.self,
        toVersion:   CadenceSchemaV2.self
    )
}

@main
struct CadenceApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var store = StoreService.shared

    // True when the on-disk store failed to open (e.g. migration error) and
    // we fell back to an in-memory container for this session.
    static private(set) var usingFallbackStorage = false

    var sharedModelContainer: ModelContainer = {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // Pass the migration plan so SwiftData can automatically add new columns
        // (painLevel, brainFogLevel, basicsCompleted) without destroying existing data.
        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [persistentConfig]
        ) {
            return container
        }
        CadenceApp.usingFallbackStorage = true
        let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [fallbackConfig])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(store)
                .modelContainer(sharedModelContainer)
                .task {
                    appState.notificationsAuthorized = await NotificationService.shared.requestAuthorization()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .dashboard
    @State private var showStorageWarning = CadenceApp.usingFallbackStorage

    var body: some View {
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
        .alert("Storage Unavailable", isPresented: $showStorageWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cadence couldn't open its database (a migration may be needed). Your data is safe, but changes made this session won't be saved. Try deleting and reinstalling the app if this persists.")
        }
    }
}

enum Tab: Hashable {
    case dashboard, dailyLog, weeklyReview, insights, history
}
