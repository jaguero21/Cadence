import SwiftUI
import PDFKit
import Charts

enum PDFBuilder {
    static func build(logs: [DailyLogSnapshot], reviews: [WeeklyReviewSnapshot], medications: [MedicationSnapshot] = [], flares: [FlareSnapshot] = [], customTrackers: [CustomTrackerSnapshot] = []) async -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let uid = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("in-rhythm-cadence-report-\(uid).pdf")

        let insights = PatternEngine.allInsights(from: logs, medications: medications, flares: flares, trackers: customTrackers)
        // Chart images render on the main actor (ImageRenderer requirement),
        // before the PDF context opens.
        let charts = await trendChartImages(logs: logs)

        do {
            try renderer.writePDF(to: url) { ctx in
                renderReport(ctx: ctx, logs: logs, charts: charts, insights: insights, medications: medications, flares: flares, customTrackers: customTrackers)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Print palette

    // Catalog colors resolved for LIGHT mode: a report generated on a dark-mode
    // phone must not come out with dark-variant inks.
    private static func printColor(_ name: String, fallback: UIColor) -> UIColor {
        UIColor(named: name)?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) ?? fallback
    }
    static var inkAccent: UIColor { printColor("AccentColor",  fallback: UIColor(red: 0.16, green: 0.62, blue: 0.56, alpha: 1)) }
    static var inkMood: UIColor   { printColor("MoodBlue",     fallback: UIColor(red: 0.29, green: 0.56, blue: 0.72, alpha: 1)) }
    static var inkEnergy: UIColor { printColor("EnergyOrange", fallback: UIColor(red: 0.91, green: 0.63, blue: 0.23, alpha: 1)) }
    static var inkSleep: UIColor  { printColor("SleepPurple",  fallback: UIColor(red: 0.55, green: 0.49, blue: 0.78, alpha: 1)) }
    static var inkStress: UIColor { printColor("StressRed",    fallback: UIColor(red: 0.91, green: 0.44, blue: 0.32, alpha: 1)) }
    private static let inkText = UIColor(white: 0.13, alpha: 1)
    private static let inkSecondary = UIColor(white: 0.42, alpha: 1)

    // MARK: - Text measurement

    fileprivate static func textHeight(_ text: String, attrs: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height)
    }

    // MARK: - Page cursor

    // Owns the vertical position, page breaks, and the per-page footer, so
    // renderers read as content ("section, line, bar") instead of geometry.
    private final class Cursor {
        static let pageBottom: CGFloat = 790
        let ctx: UIGraphicsPDFRendererContext
        private(set) var page = 0
        var y: CGFloat = 40

        init(ctx: UIGraphicsPDFRendererContext) {
            self.ctx = ctx
        }

        func beginPage() {
            ctx.beginPage()
            page += 1
            y = 40
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.55, alpha: 1),
            ]
            "Created with Cadence — observations from the user's own logs, not medical advice."
                .draw(in: CGRect(x: 40, y: 814, width: 440, height: 12), withAttributes: attrs)
            let pageStyle = NSMutableParagraphStyle()
            pageStyle.alignment = .right
            var pageAttrs = attrs
            pageAttrs[.paragraphStyle] = pageStyle
            "Page \(page)".draw(in: CGRect(x: 480, y: 814, width: 75, height: 12), withAttributes: pageAttrs)
        }

        func breakIfNeeded(_ height: CGFloat) {
            if y + height > Self.pageBottom { beginPage() }
        }

        func space(_ height: CGFloat) {
            y = min(y + height, Self.pageBottom)
        }

        // A body line; wraps and page-breaks as needed.
        func line(_ text: String, font: UIFont = .systemFont(ofSize: 11), color: UIColor = PDFBuilder.inkText, x: CGFloat = 50, width: CGFloat = 505, spacing: CGFloat = 3) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let h = PDFBuilder.textHeight(text, attrs: attrs, width: width)
            breakIfNeeded(h)
            text.draw(in: CGRect(x: x, y: y, width: width, height: h), withAttributes: attrs)
            y += h + spacing
        }

        // "Mar 4: took a long walk" — bold date run, regular body run.
        func datedLine(_ date: String, _ body: String, x: CGFloat = 50, width: CGFloat = 505) {
            let text = NSMutableAttributedString(
                string: date,
                attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: PDFBuilder.inkText]
            )
            text.append(NSAttributedString(
                string: "  \(body)",
                attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: PDFBuilder.inkText]
            ))
            let h = ceil(text.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height)
            breakIfNeeded(h)
            text.draw(in: CGRect(x: x, y: y, width: width, height: h))
            y += h + 4
        }

        // Section header: title plus a short accent tick underneath.
        func section(_ title: String) {
            space(18)
            breakIfNeeded(52)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold),
                .foregroundColor: PDFBuilder.inkText,
            ]
            title.draw(in: CGRect(x: 40, y: y, width: 515, height: 18), withAttributes: attrs)
            y += 20
            PDFBuilder.inkAccent.setFill()
            UIBezierPath(roundedRect: CGRect(x: 40, y: y, width: 26, height: 2.5), cornerRadius: 1.25).fill()
            y += 10
        }

        // Label line + proportional bar (frequency charts without a chart).
        func bar(_ label: String, fraction: CGFloat, color: UIColor) {
            let labelFont = UIFont.systemFont(ofSize: 11)
            let h = PDFBuilder.textHeight(label, attrs: [.font: labelFont], width: 505)
            breakIfNeeded(h + 12)
            line(label, font: labelFont, spacing: 3)
            let width = max(6, 505 * min(max(fraction, 0), 1))
            color.withAlphaComponent(0.75).setFill()
            UIBezierPath(roundedRect: CGRect(x: 50, y: y, width: width, height: 5), cornerRadius: 2.5).fill()
            y += 12
        }

        // A pre-rendered image (trend chart); breaks the page first if needed.
        func image(_ image: UIImage, at x: CGFloat, size: CGSize, advance: Bool) {
            breakIfNeeded(size.height)
            image.draw(in: CGRect(x: x, y: y, width: size.width, height: size.height))
            if advance { y += size.height + 8 }
        }
    }

    // MARK: - Trend charts

    // Rendered per-series so the PDF pages can flow them 2-up. Sized for a
    // half-column; scale 3 keeps them crisp in print.
    static let chartSize = CGSize(width: 247, height: 150)

    private struct TrendSpec {
        let title: String
        let ink: UIColor
        let yDomain: ClosedRange<Double>
        let value: (DailyLogSnapshot) -> Double
    }

    @MainActor
    private static func trendChartImages(logs: [DailyLogSnapshot]) -> [UIImage] {
        // A "trend" of one point is noise; skip charts entirely for tiny sets.
        guard logs.count >= 2 else { return [] }
        let sorted = logs.sorted { $0.date < $1.date }
        let specs: [TrendSpec] = [
            TrendSpec(title: "Mood (1–5)",          ink: inkMood,   yDomain: 1...5)  { Double($0.mood) },
            TrendSpec(title: "Energy (0–10)",       ink: inkEnergy, yDomain: 0...10) { Double($0.energy) },
            TrendSpec(title: "Sleep quality (0–10)", ink: inkSleep,  yDomain: 0...10) { Double($0.sleepQuality) },
            TrendSpec(title: "Anxiety (0–10)",      ink: inkStress, yDomain: 0...10) { Double($0.stressLevel) },
        ]
        return specs.compactMap { spec in
            let points = sorted.map { (date: $0.date, value: spec.value($0)) }
            let average = points.map(\.value).reduce(0, +) / Double(points.count)
            let view = PDFTrendChart(
                title: spec.title,
                color: Color(uiColor: spec.ink),
                points: points,
                yDomain: spec.yDomain,
                average: average
            )
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            return renderer.uiImage
        }
    }

    private static func drawChartGrid(_ charts: [UIImage], cursor: Cursor) {
        guard !charts.isEmpty else { return }
        cursor.section("Trends")
        for pair in stride(from: 0, to: charts.count, by: 2) {
            cursor.breakIfNeeded(chartSize.height + 8)
            cursor.image(charts[pair], at: 40, size: chartSize, advance: pair + 1 >= charts.count)
            if pair + 1 < charts.count {
                cursor.image(charts[pair + 1], at: 40 + chartSize.width + 14, size: chartSize, advance: true)
            }
        }
    }

    // MARK: - Report

    private static func renderReport(ctx: UIGraphicsPDFRendererContext, logs: [DailyLogSnapshot], charts: [UIImage], insights: [InsightCard], medications: [MedicationSnapshot], flares: [FlareSnapshot], customTrackers: [CustomTrackerSnapshot]) {
        let cursor = Cursor(ctx: ctx)
        cursor.beginPage()
        drawReportHeader(cursor: cursor, title: "In Rhythm: Your Cadence Report", logs: logs)

        drawChartGrid(charts, cursor: cursor)

        // Symptom frequency as bars, with the average severity the old text
        // list never carried.
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let entries = logs.flatMap(\.symptoms)
        let symptomCounts = entries.reduce(into: [String: Int]()) { $0[$1.name, default: 0] += 1 }
        cursor.section("Symptom Frequency")
        if symptomCounts.isEmpty {
            cursor.line("No symptoms logged in this period.", font: bodyFont, color: inkSecondary)
        }
        let maxCount = symptomCounts.values.max() ?? 1
        for (symptom, count) in symptomCounts.sorted(by: { $0.value > $1.value }) {
            let severities = entries.filter { $0.name == symptom }.map(\.severity)
            let avgSeverity = Double(severities.reduce(0, +)) / Double(max(severities.count, 1))
            let label = "\(symptom) — \(count) day\(count == 1 ? "" : "s") · avg severity \(String(format: "%.1f", avgSeverity))/10"
            cursor.bar(label, fraction: CGFloat(count) / CGFloat(maxCount), color: inkAccent)
        }

        let factorCounts = logs.flatMap(\.factors).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if !factorCounts.isEmpty {
            cursor.section("Common Factors")
            let maxFactor = factorCounts.values.max() ?? 1
            for (factor, count) in factorCounts.sorted(by: { $0.value > $1.value }) {
                cursor.bar("\(factor) — \(count) day\(count == 1 ? "" : "s")",
                           fraction: CGFloat(count) / CGFloat(maxFactor), color: inkMood)
            }
        }

        let basicsCounts = logs.flatMap(\.basicsCompleted).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if !basicsCounts.isEmpty {
            cursor.section("Daily Basics")
            for (basic, count) in basicsCounts.sorted(by: { $0.value > $1.value }) {
                cursor.bar("\(basic) — \(count) of \(logs.count) days",
                           fraction: CGFloat(count) / CGFloat(max(logs.count, 1)), color: inkSleep)
            }
        }

        if !logs.isEmpty {
            cursor.section("Average Metrics")
            let count = Double(logs.count)
            let avg: (KeyPath<DailyLogSnapshot, Int>) -> Double = { path in
                Double(logs.map { $0[keyPath: path] }.reduce(0, +)) / count
            }
            let metricLines = [
                "Mood: \(String(format: "%.1f", avg(\.mood)))/5",
                "Energy: \(String(format: "%.1f", avg(\.energy)))/10",
                "Avg sleep: \(String(format: "%.1f", logs.map(\.sleepHours).reduce(0,+) / count)) hrs",
                "Sleep quality: \(String(format: "%.1f", avg(\.sleepQuality)))/10",
                "Pain / ache: \(String(format: "%.1f", avg(\.painLevel)))/10",
                "Brain fog: \(String(format: "%.1f", avg(\.brainFogLevel)))/10",
                "Anxiety: \(String(format: "%.1f", avg(\.stressLevel)))/10",
            ]
            for line in metricLines {
                cursor.line(line, font: bodyFont)
            }
            for tracker in customTrackers {
                let values = logs.compactMap { log in log.customMetrics.first { $0.trackerID == tracker.id }?.value }
                guard !values.isEmpty else { continue }
                let avgValue = Double(values.reduce(0, +)) / Double(values.count)
                cursor.line("\(tracker.name): \(String(format: "%.1f", avgValue))\(tracker.unit.isEmpty ? "" : " \(tracker.unit)")", font: bodyFont)
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
            cursor.section("HealthKit Data (averages)")
            for line in hkLines {
                cursor.line(line, font: bodyFont)
            }
        }

        let dateFmt = Date.FormatStyle().month(.abbreviated).day().year()
        if !medications.isEmpty {
            cursor.section("Medications")
            for med in medications.sorted(by: { $0.startDate > $1.startDate }) {
                let range = "from \(med.startDate.formatted(dateFmt))" + (med.endDate.map { " to \($0.formatted(dateFmt))" } ?? " (ongoing)")
                cursor.line("\(med.displayLabel) — \(range)", font: bodyFont)
            }
        }

        if !flares.isEmpty {
            cursor.section("Symptom Flares")
            for flare in flares.sorted(by: { $0.startDate > $1.startDate }) {
                let range = flare.endDate.map { "\(flare.startDate.formatted(dateFmt)) – \($0.formatted(dateFmt))" }
                    ?? "since \(flare.startDate.formatted(dateFmt)) (ongoing)"
                cursor.line("\(range): \(flare.durationDays) day\(flare.durationDays == 1 ? "" : "s"), peak \(flare.peakSeverity)/10", font: bodyFont)
            }
        }

        let dayFmt = Date.FormatStyle().month(.abbreviated).day()
        let peaksAndValleysDays = logs
            .filter { !$0.peaksAndValleysNote.isEmpty || $0.hasPeaksAndValleysVoiceMemo }
            .sorted { $0.date > $1.date }
        if !peaksAndValleysDays.isEmpty {
            cursor.section("Peaks & Valleys")
            for log in peaksAndValleysDays {
                var body = log.peaksAndValleysNote.isEmpty ? "(voice memo only)" : log.peaksAndValleysNote
                if log.hasPeaksAndValleysVoiceMemo && !log.peaksAndValleysNote.isEmpty {
                    body += " (+ voice memo)"
                }
                cursor.datedLine(log.date.formatted(dayFmt), body)
            }
        }

        let intentionDays = logs.filter { !$0.intentionsForTomorrow.isEmpty }.sorted { $0.date > $1.date }
        if !intentionDays.isEmpty {
            cursor.section("Intentions for Tomorrow")
            for log in intentionDays {
                cursor.datedLine(log.date.formatted(dayFmt), log.intentionsForTomorrow)
            }
        }

        let noteDays = logs.filter { !$0.freeNote.isEmpty }.sorted { $0.date > $1.date }
        if !noteDays.isEmpty {
            cursor.section("Daily Notes")
            for log in noteDays {
                cursor.datedLine(log.date.formatted(dayFmt), log.freeNote)
            }
        }

        cursor.section("Pattern Insights")
        cursor.line("Observations from the patient's own daily logs, for awareness — not a diagnosis.",
                    font: .systemFont(ofSize: 9.5), color: inkSecondary, x: 40, width: 515, spacing: 8)
        if insights.isEmpty {
            cursor.line("No patterns detected from the current log set.", font: bodyFont, color: inkSecondary)
        } else {
            for insight in insights {
                cursor.line("\(insight.title) — \(Int(insight.confidence * 100))% confidence",
                            font: .systemFont(ofSize: 11, weight: .semibold), spacing: 2)
                cursor.line(insight.detail, font: bodyFont, color: inkSecondary, x: 60, width: 495, spacing: 10)
            }
        }
    }

    // MARK: - Shared header

    private static func drawReportHeader(cursor: Cursor, title: String, logs: [DailyLogSnapshot]) {
        title.draw(in: CGRect(x: 40, y: cursor.y, width: 420, height: 30),
                   withAttributes: [.font: UIFont.systemFont(ofSize: 23, weight: .bold), .foregroundColor: inkText])

        let rightStyle = NSMutableParagraphStyle()
        rightStyle.alignment = .right
        "Generated \(Date.now.formatted(date: .abbreviated, time: .omitted))"
            .draw(in: CGRect(x: 380, y: cursor.y + 10, width: 175, height: 14),
                  withAttributes: [.font: UIFont.systemFont(ofSize: 9.5), .foregroundColor: inkSecondary, .paragraphStyle: rightStyle])
        cursor.y += 34

        let subtitle: String
        if let earliest = logs.map(\.date).min(), let latest = logs.map(\.date).max() {
            let spanDays = (Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0) + 1
            subtitle = "\(earliest.formatted(date: .abbreviated, time: .omitted)) – \(latest.formatted(date: .abbreviated, time: .omitted))"
                + " · \(logs.count) of \(spanDays) days logged"
        } else {
            subtitle = "No logged days in the selected range"
        }
        subtitle.draw(in: CGRect(x: 40, y: cursor.y, width: 515, height: 16),
                      withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: inkSecondary])
        cursor.y += 24

        inkAccent.setFill()
        UIBezierPath(roundedRect: CGRect(x: 40, y: cursor.y, width: 515, height: 3), cornerRadius: 1.5).fill()
        cursor.y += 18
    }
}

// The chart drawn into report pages: same series look as the in-app trend
// charts (line + soft area + dashed average), sized for a half-column and
// rendered opaque white for print.
private struct PDFTrendChart: View {
    let title: String
    let color: Color
    let points: [(date: Date, value: Double)]
    let yDomain: ClosedRange<Double>
    let average: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(white: 0.13))
                Spacer()
                Text("avg \(String(format: "%.1f", average))")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.42))
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Day", point.date), y: .value(title, point.value))
                        .foregroundStyle(
                            LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", point.date), y: .value(title, point.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Color(white: 0.88))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 7))
                        .foregroundStyle(Color(white: 0.42))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Color(white: 0.88))
                    AxisValueLabel()
                        .font(.system(size: 7))
                        .foregroundStyle(Color(white: 0.42))
                }
            }
        }
        .padding(10)
        .frame(width: PDFBuilder.chartSize.width, height: PDFBuilder.chartSize.height)
        .background(Color.white)
    }
}
