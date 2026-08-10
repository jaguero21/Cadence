import SwiftUI
import SwiftData

struct InsightCard: Identifiable {
    let id = UUID()
    // Stable semantic identity for dedup/history (e.g. "med-effect:Sertraline").
    // Never derive it from title/detail: display copy changes (direction flips,
    // copyedits, localization) must update the same record, not mint a new one.
    var key: String
    var title: String
    var detail: String
    var icon: String
    var color: Color
    var confidence: Double      // 0–1
    var category: InsightCategory
}

enum InsightCategory: String {
    case sleep   = "Sleep"
    case mood    = "Mood"
    case energy  = "Energy"
    case symptom = "Symptom"
    case stress  = "Stress"
}

@MainActor
@Observable
final class InsightsViewModel {
    var insights: [InsightCard] = []
    var chartRange: ChartRange = .sevenDay

    enum ChartRange: String, CaseIterable {
        case sevenDay  = "7D"
        case thirtyDay = "30D"
        case ninetyDay = "90D"

        // Single source of truth for the range's window; voiceLabel and the
        // view's date math both derive from it so they can't drift.
        var days: Int {
            switch self {
            case .sevenDay:  return 7
            case .thirtyDay: return 30
            case .ninetyDay: return 90
            }
        }

        var voiceLabel: String { "\(days) days" }
    }

    // `health` are the HealthSnapshot rows from the view's @Query, joined to
    // each log by date — the hk*-reading detectors need them, and they live in
    // a separate local-only store since the CloudKit split.
    func refresh(logs: [DailyLog], health: [HealthSnapshot], medications: [Medication] = [], flares: [Flare] = [], trackers: [CustomTracker] = []) {
        // Snapshot @Model values on the main actor before handing them to PatternEngine,
        // which is otherwise isolation-agnostic.
        insights = PatternEngine.allInsights(
            from: DailyLogSnapshot.build(from: logs, health: health),
            medications: medications.map(MedicationSnapshot.init),
            flares: flares.map(FlareSnapshot.init),
            trackers: trackers.map(CustomTrackerSnapshot.init)
        )
    }
}
