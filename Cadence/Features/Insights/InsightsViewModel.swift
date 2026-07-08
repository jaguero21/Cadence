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

    func refresh(logs: [DailyLog], medications: [Medication] = []) {
        // Snapshot @Model values on the main actor before handing them to PatternEngine,
        // which is otherwise isolation-agnostic.
        insights = PatternEngine.allInsights(
            from: logs.map(DailyLogSnapshot.init),
            medications: medications.map(MedicationSnapshot.init)
        )
    }
}
