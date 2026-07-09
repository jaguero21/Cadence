import Foundation
import SwiftData

@Model
final class WeeklyReview {
    // Uniqueness per week is enforced in code (ReviewFlowView fetches the
    // existing review before creating one); CloudKit forbids @Attribute(.unique).
    var weekStartDate: Date = Date.now.startOfWeek
    var promptResponses: [PromptResponse] = []
    var overallRating: Int = 0      // 1–5
    var peaksAndValleysNote: String = ""    // "What were the peaks and valleys of your week?"
    var peaksAndValleysVoiceMemo: Attachment?   // optional single voice memo; binary lives on disk (see AttachmentStore)
    var intentionsForTomorrow: String = ""  // "Write your intentions for tomorrow."

    // Auto-populated from daily logs
    var avgMood: Double = 0
    var avgEnergy: Double = 0
    var avgSleep: Double = 0
    var topSymptoms: [String] = []
    var isComplete: Bool = false

    init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate.startOfWeek
        self.promptResponses = []
        self.overallRating = 0
        self.peaksAndValleysNote = ""
        self.intentionsForTomorrow = ""
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
        let cal = Calendar.current
        let fullFmt = Date.FormatStyle().month(.abbreviated).day().year()
        let shortFmt = Date.FormatStyle().month(.abbreviated).day()
        let startYear = cal.component(.year, from: weekStartDate)
        let endYear   = cal.component(.year, from: weekEndDate)
        let startFmt  = startYear != endYear ? fullFmt : shortFmt
        return "\(weekStartDate.formatted(startFmt)) – \(weekEndDate.formatted(fullFmt))"
    }
}

struct PromptResponse: Codable {
    var section: String
    var prompt: String
    var response: String
}

// Sendable projection of WeeklyReview for off-main-actor PDF export.
struct WeeklyReviewSnapshot: Sendable {
    let weekLabel: String
    let promptResponses: [PromptResponse]
    let peaksAndValleysNote: String
    let hasPeaksAndValleysVoiceMemo: Bool
    let intentionsForTomorrow: String

    init(_ review: WeeklyReview) {
        weekLabel       = review.weekLabel
        promptResponses = review.promptResponses
        peaksAndValleysNote = review.peaksAndValleysNote
        hasPeaksAndValleysVoiceMemo = review.peaksAndValleysVoiceMemo != nil
        intentionsForTomorrow = review.intentionsForTomorrow
    }
}
