import AppIntents
import WidgetKit
import Foundation

// Backs the widget's mood buttons. Stashes the tap in the App Group rather
// than writing to SwiftData directly — that works identically whether the
// system runs the intent in the app's process or the extension's, and keeps
// the app the store's only writer. The app applies pending taps on its next
// foregrounding (see ContentView.applyPendingQuickLogs); the widget shows a
// "mood saved" state for the day in the meantime.
struct WidgetQuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Mood"
    static let description = IntentDescription("Records today's mood from the widget.")

    @Parameter(title: "Mood")
    var mood: Int

    init() {}

    init(mood: Int) {
        self.mood = mood
    }

    func perform() async throws -> some IntentResult {
        WidgetData.stashPendingQuickLog(mood: min(max(mood, 1), 5))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetData.widgetKind)
        return .result()
    }
}
