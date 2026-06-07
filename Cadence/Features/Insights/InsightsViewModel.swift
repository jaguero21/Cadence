import SwiftUI
import SwiftData

struct InsightCard: Identifiable {
    let id = UUID()
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

        var voiceLabel: String {
            switch self {
            case .sevenDay:  return "7 days"
            case .thirtyDay: return "30 days"
            case .ninetyDay: return "90 days"
            }
        }
    }

    func refresh(logs: [DailyLog]) {
        // Snapshot @Model values on the main actor before handing them to PatternEngine,
        // which is otherwise isolation-agnostic.
        insights = PatternEngine.allInsights(from: logs.map(DailyLogSnapshot.init))
    }
}
