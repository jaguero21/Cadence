import SwiftUI
import PDFKit

enum ReportType: String, CaseIterable {
    case doctor   = "Cadence Trend"
    case personal = "Personal Summary"
}

enum PDFBuilder {
    static func build(type: ReportType, logs: [DailyLogSnapshot], reviews: [WeeklyReviewSnapshot], medications: [MedicationSnapshot] = [], flares: [FlareSnapshot] = [], customTrackers: [CustomTrackerSnapshot] = [], headerTitle: String? = nil) async -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let uid = UUID().uuidString
        let filename = type == .doctor ? "cadence-doctor-report-\(uid).pdf" : "cadence-personal-summary-\(uid).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        // Insights run once here so the renderer doesn't need to know about
        // PatternEngine — and personal-summary builds don't pay the cost.
        let insights = type == .doctor ? PatternEngine.allInsights(from: logs, medications: medications) : []

        do {
            try renderer.writePDF(to: url) { ctx in
                switch type {
                case .doctor:   renderDoctorReport(ctx: ctx, logs: logs, insights: insights, medications: medications, flares: flares, customTrackers: customTrackers, headerTitle: headerTitle)
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

    private static func renderDoctorReport(ctx: UIGraphicsPDFRendererContext, logs: [DailyLogSnapshot], insights: [InsightCard], medications: [MedicationSnapshot], flares: [FlareSnapshot], customTrackers: [CustomTrackerSnapshot], headerTitle: String?) {
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

        let factorCounts = logs.flatMap(\.factors).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        if !factorCounts.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Common Factors".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            for (factor, count) in factorCounts.sorted(by: { $0.value > $1.value }) {
                let line = "\(factor): \(count) days"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        let basicsCounts = logs.flatMap(\.basicsCompleted).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        if !basicsCounts.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Daily Basics".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            for (basic, count) in basicsCounts.sorted(by: { $0.value > $1.value }) {
                let line = "\(basic): \(count) of \(logs.count) days"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        y += 16
        breakIfNeeded(y: &y, needing: 44, ctx: ctx)
        "Average Metrics".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
        y += 24
        if !logs.isEmpty {
            let count = Double(logs.count)
            let avgMood     = Double(logs.map(\.mood).reduce(0,+)) / count
            let avgEnergy   = Double(logs.map(\.energy).reduce(0,+)) / count
            let avgSleep    = logs.map(\.sleepHours).reduce(0,+) / count
            let avgQuality  = Double(logs.map(\.sleepQuality).reduce(0,+)) / count
            let avgPain     = Double(logs.map(\.painLevel).reduce(0,+)) / count
            let avgFog      = Double(logs.map(\.brainFogLevel).reduce(0,+)) / count
            let avgAnxiety  = Double(logs.map(\.stressLevel).reduce(0,+)) / count
            let metricLines = [
                "Mood: \(String(format: "%.1f", avgMood))/5",
                "Energy: \(String(format: "%.1f", avgEnergy))/10",
                "Avg sleep: \(String(format: "%.1f", avgSleep)) hrs",
                "Sleep quality: \(String(format: "%.1f", avgQuality))/10",
                "Pain / ache: \(String(format: "%.1f", avgPain))/10",
                "Brain fog: \(String(format: "%.1f", avgFog))/10",
                "Anxiety: \(String(format: "%.1f", avgAnxiety))/10",
            ]
            for line in metricLines {
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
            for tracker in customTrackers {
                let values = logs.compactMap { log in log.customMetrics.first { $0.trackerID == tracker.id }?.value }
                guard !values.isEmpty else { continue }
                let avg = Double(values.reduce(0, +)) / Double(values.count)
                let line = "\(tracker.name): \(String(format: "%.1f", avg))\(tracker.unit.isEmpty ? "" : " \(tracker.unit)")"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        // HealthKit objective data (promised by the Export screen's "Includes"
        // list): average of each measure over the days that have it.
        var hkLines: [String] = []
        func hkAverage(_ label: String, _ values: [Double], format: (Double) -> String) {
            guard !values.isEmpty else { return }
            let avg = values.reduce(0, +) / Double(values.count)
            hkLines.append("\(label): \(format(avg)) (\(values.count) days)")
        }
        hkAverage("Steps", logs.compactMap { $0.hkSteps.map(Double.init) }) { String(format: "%.0f", $0) }
        hkAverage("Resting heart rate", logs.compactMap(\.hkRestingHR)) { String(format: "%.0f bpm", $0) }
        hkAverage("Heart rate variability", logs.compactMap(\.hkHRV)) { String(format: "%.0f ms", $0) }
        hkAverage("Sleep (measured)", logs.compactMap(\.hkSleepHours)) { String(format: "%.1f hrs", $0) }
        hkAverage("Active energy", logs.compactMap(\.hkActiveEnergy)) { String(format: "%.0f kcal", $0) }
        hkAverage("Mindful minutes", logs.compactMap(\.hkMindfulMinutes)) { String(format: "%.0f min", $0) }
        hkAverage("Overnight wrist temp", logs.compactMap(\.hkWristTemp)) { String(format: "%.1f °C", $0) }
        hkAverage("Respiratory rate", logs.compactMap(\.hkRespiratoryRate)) { String(format: "%.1f breaths/min", $0) }
        hkAverage("Blood oxygen", logs.compactMap(\.hkBloodOxygen)) { String(format: "%.0f%%", $0) }
        hkAverage("Time in daylight", logs.compactMap(\.hkDaylightMinutes)) { String(format: "%.0f min", $0) }
        hkAverage("Daytime heart rate", logs.compactMap(\.hkDaytimeHR)) { String(format: "%.0f bpm", $0) }
        hkAverage("Workout time", logs.compactMap(\.hkWorkoutMinutes)) { String(format: "%.0f min", $0) }
        if !hkLines.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "HealthKit Data (averages)".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            for line in hkLines {
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        if !medications.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Medications".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            let dateFmt = Date.FormatStyle().month(.abbreviated).day().year()
            for med in medications.sorted(by: { $0.startDate > $1.startDate }) {
                let range = "from \(med.startDate.formatted(dateFmt))" + (med.endDate.map { " to \($0.formatted(dateFmt))" } ?? " (ongoing)")
                let line = "\(med.displayLabel) — \(range)"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        if !flares.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Symptom Flares".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            let dateFmt = Date.FormatStyle().month(.abbreviated).day().year()
            for flare in flares.sorted(by: { $0.startDate > $1.startDate }) {
                let range = flare.endDate.map { "\(flare.startDate.formatted(dateFmt)) – \($0.formatted(dateFmt))" }
                    ?? "since \(flare.startDate.formatted(dateFmt)) (ongoing)"
                let line = "\(range): \(flare.durationDays) day\(flare.durationDays == 1 ? "" : "s"), peak \(flare.peakSeverity)/10"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        let peaksAndValleysDays = logs
            .filter { !$0.peaksAndValleysNote.isEmpty || $0.hasPeaksAndValleysVoiceMemo }
            .sorted { $0.date > $1.date }
        if !peaksAndValleysDays.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Peaks & Valleys".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            let dateFmt = Date.FormatStyle().month(.abbreviated).day()
            for log in peaksAndValleysDays {
                var line = "\(log.date.formatted(dateFmt)): "
                line += log.peaksAndValleysNote.isEmpty ? "(voice memo only)" : log.peaksAndValleysNote
                if log.hasPeaksAndValleysVoiceMemo && !log.peaksAndValleysNote.isEmpty {
                    line += " (+ voice memo)"
                }
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        let intentionDays = logs.filter { !$0.intentionsForTomorrow.isEmpty }.sorted { $0.date > $1.date }
        if !intentionDays.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Intentions for Tomorrow".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            let dateFmt = Date.FormatStyle().month(.abbreviated).day()
            for log in intentionDays {
                let line = "\(log.date.formatted(dateFmt)): \(log.intentionsForTomorrow)"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        let noteDays = logs.filter { !$0.freeNote.isEmpty }.sorted { $0.date > $1.date }
        if !noteDays.isEmpty {
            y += 16
            breakIfNeeded(y: &y, needing: 44, ctx: ctx)
            "Daily Notes".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
            y += 24
            let dateFmt = Date.FormatStyle().month(.abbreviated).day()
            for log in noteDays {
                let line = "\(log.date.formatted(dateFmt)): \(log.freeNote)"
                let h = textHeight(line, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 50, y: y, width: 505, height: h), withAttributes: bodyAttrs)
                y += h + 2
            }
        }

        y += 16
        breakIfNeeded(y: &y, needing: 64, ctx: ctx)
        "Pattern Insights".draw(in: CGRect(x: 40, y: y, width: 515, height: 20), withAttributes: sectionAttrs)
        y += 22
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray,
        ]
        let disclaimer = "Observations from the patient's own daily logs, for awareness — not a diagnosis."
        let disclaimerH = textHeight(disclaimer, attrs: captionAttrs, width: 515)
        disclaimer.draw(in: CGRect(x: 40, y: y, width: 515, height: disclaimerH), withAttributes: captionAttrs)
        y += disclaimerH + 8
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

            // The closing star rating and the auto-populated Week at a Glance
            // stats, mirroring what the review flow itself shows.
            var glanceLines: [String] = []
            if review.overallRating > 0 {
                let stars = String(repeating: "★", count: review.overallRating)
                    + String(repeating: "☆", count: 5 - review.overallRating)
                glanceLines.append("Overall week: \(stars) (\(review.overallRating)/5)")
            }
            if review.avgMood > 0 || review.avgEnergy > 0 || review.avgSleep > 0 {
                glanceLines.append("Averages — mood \(String(format: "%.1f", review.avgMood))/5, energy \(String(format: "%.1f", review.avgEnergy))/10, sleep \(String(format: "%.1f", review.avgSleep)) hrs")
            }
            if !review.topSymptoms.isEmpty {
                glanceLines.append("Top symptoms: \(review.topSymptoms.joined(separator: ", "))")
            }
            for line in glanceLines {
                let h = textHeight(line, attrs: bodyAttrs, width: 515)
                breakIfNeeded(y: &y, needing: h, ctx: ctx)
                line.draw(in: CGRect(x: 40, y: y, width: 515, height: h), withAttributes: bodyAttrs)
                y += h + 4
            }
            if !glanceLines.isEmpty { y += 12 }

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

            if !review.intentionsForTomorrow.isEmpty {
                let title = "Intentions for Tomorrow"
                let text = review.intentionsForTomorrow
                let sectionH = textHeight(title, attrs: sectionAttrs, width: 515)
                let bodyH = textHeight(text, attrs: bodyAttrs, width: 505)
                breakIfNeeded(y: &y, needing: sectionH + 4 + bodyH + 16, ctx: ctx)
                title.draw(in: CGRect(x: 40, y: y, width: 515, height: sectionH), withAttributes: sectionAttrs)
                y += sectionH + 4
                text.draw(in: CGRect(x: 50, y: y, width: 505, height: bodyH), withAttributes: bodyAttrs)
                y += bodyH + 16
            }
        }
    }
}
