import AppIntents
import SwiftData
import Foundation

// Siri / Shortcuts quick check-in ("Log my mood in Cadence"). App-target
// intents run in the app's process, so this writes straight to the shared
// container through the same upsert seam the watch quick-log uses
// (PhoneConnectivityManager.applyQuickLog), then republishes the widget
// summary — one tested path for every quick-log surface.

enum MoodOption: Int, AppEnum {
    case awful = 1, down, okay, good, great

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    // Emoji follow MoodScale's canonical 1–5 order.
    static let caseDisplayRepresentations: [MoodOption: DisplayRepresentation] = [
        .awful: "😢 Awful",
        .down:  "😕 Down",
        .okay:  "😐 Okay",
        .good:  "🙂 Good",
        .great: "😊 Great",
    ]
}

struct LogCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Check-In"
    static let description = IntentDescription("Records your mood — and optionally energy — for today without opening the app.")

    @Parameter(title: "Mood")
    var mood: MoodOption

    @Parameter(title: "Energy (0–10)", inclusiveRange: (0, 10))
    var energy: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = CadenceApp.sharedModelContainer else {
            return .result(dialog: "Cadence couldn't open its data store. Try again from the app.")
        }
        var payload: [String: Any] = [
            "mood": mood.rawValue,
            "date": Date.now.timeIntervalSinceReferenceDate,
        ]
        if let energy { payload["energy"] = energy }

        let context = container.mainContext
        guard PhoneConnectivityManager.applyQuickLog(payload, context: context) else {
            return .result(dialog: "The check-in couldn't be saved. Try again from the app.")
        }
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        DashboardViewModel.publishWidgetSummary(logs: logs)
        // Mirror the mood into Health's State of Mind — a Siri check-in is
        // still a check-in. Best-effort, fire-and-forget.
        let today = Calendar.current.startOfDay(for: .now)
        if let todayLog = logs.first(where: { $0.date == today }) {
            let snapshot = DailyLogSnapshot(todayLog)
            Task { await HealthKitService.shared.publish(log: snapshot) }
        }
        return .result(dialog: "Logged \(MoodScale.emoji(for: mood.rawValue)) for today.")
    }
}

struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogCheckInIntent(),
            phrases: [
                "Log my mood in \(.applicationName)",
                "Log a check-in in \(.applicationName)",
                "Add a \(.applicationName) check-in",
            ],
            shortTitle: "Log Check-In",
            systemImageName: "pencil.and.list.clipboard"
        )
    }
}
