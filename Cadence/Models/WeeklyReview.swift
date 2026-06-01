import Foundation
import SwiftData

@Model
final class WeeklyReview {
    @Attribute(.unique) var weekStartDate: Date
    var promptResponses: [PromptResponse]
    var overallRating: Int      // 1–5

    // Auto-populated from daily logs
    var avgMood: Double
    var avgEnergy: Double
    var avgSleep: Double
    var topSymptoms: [String]
    var isComplete: Bool

    init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate.startOfWeek
        self.promptResponses = []
        self.overallRating = 0
        self.avgMood = 0
        self.avgEnergy = 0
        self.avgSleep = 0
        self.topSymptoms = []
        self.isComplete = false
    }

    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }

    var weekLabel: String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "\(weekStartDate.formatted(fmt)) – \(weekEndDate.formatted(fmt))"
    }
}

struct PromptResponse: Codable {
    var section: String
    var prompt: String
    var response: String
}
