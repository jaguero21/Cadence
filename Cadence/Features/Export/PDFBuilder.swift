import SwiftUI
import PDFKit

enum ReportType: String, CaseIterable {
    case doctor   = "Cadence Trend"
    case personal = "Personal Summary"
}

struct DailyLogSnapshot: Sendable {
    let date: Date
    let mood: Int
    let energy: Int
    let sleepHours: Double
    let stressLevel: Int
    let symptoms: [SymptomEntry]
    let didEditMetrics: Bool

    init(_ log: DailyLog) {
        date           = log.date
        mood           = log.mood
        energy         = log.energy
        sleepHours     = log.sleepHours
        stressLevel    = log.stressLevel
        symptoms       = log.symptoms
        didEditMetrics = log.didEditMetrics
    }

    init(
        date: Date,
        mood: Int = 3,
        energy: Int = 5,
        sleepHours: Double = 7.0,
        stressLevel: Int = 5,
        symptoms: [SymptomEntry] = [],
        didEditMetrics: Bool = false
    ) {
        self.date = date
        self.mood = mood
        self.energy = energy
        self.sleepHours = sleepHours
        self.stressLevel = stressLevel
        self.symptoms = symptoms
        self.didEditMetrics = didEditMetrics
    }
}

struct WeeklyReviewSnapshot: Sendable {
    let weekLabel: String
    let promptResponses: [PromptResponse]

    init(_ review: WeeklyReview) {
        weekLabel       = review.weekLabel
        promptResponses = review.promptResponses
    }
}

enum PDFBuilder {
    static func build(type: ReportType, logs: [DailyLogSnapshot], reviews: [WeeklyReviewSnapshot], headerTitle: String? = nil) async -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let uid = UUID().uuidString
        let filename = type == .doctor ? "cadence-doctor-report-\(uid).pdf" : "cadence-personal-summary-\(uid).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        // Insights run once here so the renderer doesn't need to know about
        // PatternEngine — and personal-summary builds don't pay the cost.
        let insights = type == .doctor ? PatternEngine.allInsights(from: logs) : []

        do {
            try renderer.writePDF(to: url) { ctx in
                switch type {
                case .doctor:   renderDoctorReport(ctx: ctx, logs: logs, insights: insights, headerTitle: headerTitle)
                case .personal: renderPersonalSummary(ctx: ctx, reviews: reviews)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static let pageBottom: CGFloat = 802  // 842pt page minus 40pt bottom margin

    private static func textHeight(_ text: String, attrs: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height)
    }

    private static func breakIfNeeded(y: inout CGFloat, needing height: CGFloat, ctx: UIGraphicsPDFRendererContext) {
        if y + height > pageBottom {
            ctx.beginPage()
            y = 40
        }
    }

    // MARK: - Renderers

    private static func renderDoctorReport(ctx: UIGraphicsPDFRendererContext, logs: [DailyLogSnapshot], insights: [InsightCard], headerTitle: String?) {
        ctx.beginPage()
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22, weight: .bold)]
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
        let insightTitleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]

        let header = headerTitle ?? "Cadence Trend"
        header.draw(in: CGRect(x: 40, y: 40, width: 515, height: 40), withAttributes: titleAttrs)

        let dateRange: String
        if let first = logs.first, let last = logs.last {
            dateRange = "\(last.date.formatted(date: .abbreviated, time: .omitted)) – \(first.date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            dateRange = "No data"
        }
        dateRange.draw(in: CGRect(x: 40, y: 80, width: 515, height: 20), withAttributes: bodyAttrs)

        var y: CGFloat = 120
        let symptomCounts = logs.flatMap(\.symptoms).reduce(into: [:]) { $0[$1.name, default: 0] += 1 }

        breakIfNeeded(y: &y, needing: 44, ctx: ctx)
        "Symptom Frequency".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
        y += 24
        for (symptom, count) in symptomCounts.sorted(by: { $0.value > $1.value }) {
            let line = "\(symptom): \(count) days"
            let h = textHeight(line, attrs: bodyAttrs, width: 505)
            breakIfNeeded(y: &y, needing: h, ctx: ctx)
            line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
            y += h + 2
        }

        y += 16
        breakIfNeeded(y: &y, needing: 44, ctx: ctx)
        "Average Metrics".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
        y += 24
        if !logs.isEmpty {
            let avgMood   = Double(logs.map(\.mood).reduce(0,+)) / Double(logs.count)
            let avgEnergy = Double(logs.map(\.energy).reduce(0,+)) / Double(logs.count)
            let avgSleep  = logs.map(\.sleepHours).reduce(0,+) / Double(logs.count)
            let metricLines = [
                "Mood: \(String(format: "%.1f", avgMood))/5",
                "Energy: \(String(format: "%.1f", avgEnergy))/10",
                "Avg sleep: \(String(format: "%.1f", avgSleep)) hrs",
            ]
            for line in metricLines {
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        y += 16
        breakIfNeeded(y: &y, needing: 44, ctx: ctx)
        "Pattern Insights".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
        y += 24
        if insights.isEmpty {
            let line = "No patterns detected from the current log set."
            let h = textHeight(line, attrs: bodyAttrs, width: 505)
            breakIfNeeded(y: &y, needing: h, ctx: ctx)
            line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
            y += h + 2
        } else {
            for insight in insights {
                let header = "\(insight.title) — \(Int(insight.confidence * 100))% confidence"
                let headerH = textHeight(header, attrs: insightTitleAttrs, width: 505)
                let detailH = textHeight(insight.detail, attrs: bodyAttrs, width: 495)
                let blockH  = headerH + 2 + detailH + 10
                breakIfNeeded(y: &y, needing: blockH, ctx: ctx)
                header.draw(in: CGRect(x: 50, y: y, width: 505, height: headerH), withAttributes: insightTitleAttrs)
                y += headerH + 2
                insight.detail.draw(in: CGRect(x: 60, y: y, width: 495, height: detailH), withAttributes: bodyAttrs)
                y += detailH + 10
            }
        }
    }

    private static func renderPersonalSummary(ctx: UIGraphicsPDFRendererContext, reviews: [WeeklyReviewSnapshot]) {
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18, weight: .bold)]
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]

        for review in reviews {
            ctx.beginPage()
            review.weekLabel.draw(in: CGRect(x: 40, y: 40, width: 515, height: 30), withAttributes: headerAttrs)
            var y: CGFloat = 80

            for response in review.promptResponses {
                let sectionH = textHeight(response.section, attrs: sectionAttrs, width: 515)
                let text = response.response.isEmpty ? "—" : response.response
                let bodyH = textHeight(text, attrs: bodyAttrs, width: 505)
                let blockH = sectionH + 4 + bodyH + 16

                breakIfNeeded(y: &y, needing: blockH, ctx: ctx)
                response.section.draw(in: CGRect(x: 40, y: y, width: 515, height: sectionH), withAttributes: sectionAttrs)
                y += sectionH + 4
                text.draw(in: CGRect(x: 50, y: y, width: 505, height: bodyH), withAttributes: bodyAttrs)
                y += bodyH + 16
            }
        }
    }
}
