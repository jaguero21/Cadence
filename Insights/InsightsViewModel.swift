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
final class InsightsViewModel: ObservableObject {
    @Published var insights: [InsightCard] = []
    @Published var chartRange: ChartRange = .sevenDay

    enum ChartRange: String, CaseIterable {
        case sevenDay  = "7D"
        case thirtyDay = "30D"
        case ninetyDay = "90D"
    }

    private var refreshTask: Task<Void, Never>?

    func refresh(logs: [DailyLog]) {
        refreshTask?.cancel()
        let snapshot = logs
        refreshTask = Task {
            let result = await PatternEngine.shared.allInsights(from: snapshot)
            guard !Task.isCancelled else { return }
            self.insights = result
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
