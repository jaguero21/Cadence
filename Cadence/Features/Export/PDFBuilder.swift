import SwiftUI
import PDFKit
import Charts
import OSLog

enum PDFBuilder {
    // `range` is the period the person chose; the header reports coverage
    // against it (nil = the span of the logs themselves, for callers with no
    // chosen range). `includePersonalNotes` adds the diary-style sections —
    // Peaks & Valleys, intentions, notes, weekly reflections — after the
    // clinical ones; ExportView lets the person leave them out of a report
    // they're handing to someone else.
    static func build(logs: [DailyLogSnapshot], reviews: [WeeklyReviewSnapshot], medications: [MedicationSnapshot] = [], flares: [FlareSnapshot] = [], customTrackers: [CustomTrackerSnapshot] = [], menopause: [MenopausalTransition] = [], range: ClosedRange<Date>? = nil, includePersonalNotes: Bool = true, paper: PaperSize = .forCurrentRegion) async -> URL? {
        // Title metadata so Mail/Files/Preview show a document name, not the
        // file name.
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: reportTitle,
            kCGPDFContextCreator as String: "Cadence",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: paper.size), format: format)
        // A readable name — this is what lands in a clinician's inbox — in a
        // per-export folder, so two reports for the same range can't collide.
        let url = ExportScratch.uniqueURL(named: fileName(range: range ?? logSpan(logs)))

        let insights = PatternEngine.allInsights(from: logs, medications: medications, flares: flares, trackers: customTrackers, menopause: menopause)
        // Chart images render on the main actor (ImageRenderer requirement),
        // before the PDF context opens.
        let charts = await trendChartImages(logs: logs)

        // Rendered to Data and written through ExportScratch rather than with
        // `renderer.writePDF(to:)`. That call writes the file itself and accepts
        // no write options, so the finished report — a full narrative health
        // history — landed without the complete-protection class the CSV and the
        // JSON backup both get. Holding a report in memory briefly is a fair
        // price; these are hundreds of KB, not hundreds of MB.
        let data = renderer.pdfData { ctx in
            renderReport(ctx: ctx, paper: paper, logs: logs, charts: charts, insights: insights, reviews: reviews, medications: medications, flares: flares, customTrackers: customTrackers, menopause: menopause, range: range, includePersonalNotes: includePersonalNotes)
        }
        do {
            try ExportScratch.write(data, to: url)
            return url
        } catch {
            // ExportView turns nil into a visible "Couldn't create the report"
            // message, but the reason would otherwise be lost entirely.
            log.error("Failed to write report: \(error, privacy: .public)")
            return nil
        }
    }

    private static let log = Logger(subsystem: "com.carpecadence", category: "PDFBuilder")

    static let reportTitle = "In Rhythm: Your Cadence Report"

    // MARK: - Paper

    // The layout is designed on A4's 515pt content width. US Letter is wider
    // and shorter, so each Letter page centres that same column (a horizontal
    // translate in Cursor.beginPage) and moves the bottom margin and footer up.
    enum PaperSize: Equatable {
        case a4, letter

        var size: CGSize {
            switch self {
            case .a4:     return CGSize(width: 595, height: 842)
            case .letter: return CGSize(width: 612, height: 792)
            }
        }

        // Letter is the paper standard in the US and Canada and across most of
        // Latin America's Letter-using countries; everywhere else uses A4.
        nonisolated static func forRegion(_ identifier: String?) -> PaperSize {
            let letterRegions: Set<String> = ["US", "CA", "MX", "PR", "PH", "CL", "CO", "VE", "GT", "CR", "PA", "DO", "SV", "NI", "HN", "BZ"]
            return identifier.map { letterRegions.contains($0) } == true ? .letter : .a4
        }

        static var forCurrentRegion: PaperSize { forRegion(Locale.current.region?.identifier) }
    }

    // MARK: - Naming and coverage

    nonisolated static func logSpan(_ logs: [DailyLogSnapshot]) -> ClosedRange<Date>? {
        guard let first = logs.map(\.date).min(), let last = logs.map(\.date).max() else { return nil }
        return first...last
    }

    // "Cadence Report, Sep 1 – Sep 30, 2026.pdf". Abbreviated month names, so
    // no locale can introduce a "/" into the file name.
    nonisolated static func fileName(range: ClosedRange<Date>?, prefix: String = "Cadence Report", ext: String = "pdf") -> String {
        guard let range else { return "\(prefix).\(ext)" }
        return "\(prefix), \(rangeLabel(range)).\(ext)"
    }

    nonisolated static func rangeLabel(_ range: ClosedRange<Date>) -> String {
        let cal = Calendar.current
        let full = Date.FormatStyle().month(.abbreviated).day().year()
        if cal.isDate(range.lowerBound, inSameDayAs: range.upperBound) {
            return range.lowerBound.formatted(full)
        }
        let sameYear = cal.component(.year, from: range.lowerBound) == cal.component(.year, from: range.upperBound)
        let start = range.lowerBound.formatted(sameYear ? Date.FormatStyle().month(.abbreviated).day() : full)
        return "\(start) – \(range.upperBound.formatted(full))"
    }

    // The header's coverage line, measured against the CHOSEN range: picking
    // Sep 1–30 having logged from Sep 10 must read "21 of 30 days logged", not
    // "21 of 21" over a span quietly narrowed to the logs. Days after `today`
    // aren't counted as missed.
    nonisolated static func coverage(loggedDays: Int, range: ClosedRange<Date>, today: Date = .now) -> (label: String, totalDays: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: range.lowerBound)
        let end = min(cal.startOfDay(for: range.upperBound), cal.startOfDay(for: today))
        let total = max((cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
        return ("\(rangeLabel(range)) · \(loggedDays) of \(total) days logged", total)
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
        static let top: CGFloat = 40
        let ctx: UIGraphicsPDFRendererContext
        let paper: PaperSize
        // Content stops 52pt above the page edge; the footer sits 28pt above it.
        let pageBottom: CGFloat
        private let footerY: CGFloat
        private(set) var page = 0
        var y: CGFloat = 40

        init(ctx: UIGraphicsPDFRendererContext, paper: PaperSize) {
            self.ctx = ctx
            self.paper = paper
            pageBottom = paper.size.height - 52
            footerY = paper.size.height - 28
        }

        func beginPage() {
            ctx.beginPage()
            // Centre the 595pt-wide layout on wider paper (Letter).
            ctx.cgContext.translateBy(x: (paper.size.width - 595) / 2, y: 0)
            page += 1
            y = Self.top
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.55, alpha: 1),
            ]
            "Made with Cadence, from your own daily reflections."
                .draw(in: CGRect(x: 40, y: footerY, width: 440, height: 12), withAttributes: attrs)
            let pageStyle = NSMutableParagraphStyle()
            pageStyle.alignment = .right
            var pageAttrs = attrs
            pageAttrs[.paragraphStyle] = pageStyle
            "Page \(page)".draw(in: CGRect(x: 480, y: footerY, width: 75, height: 12), withAttributes: pageAttrs)
        }

        func breakIfNeeded(_ height: CGFloat) {
            if y + height > pageBottom { beginPage() }
        }

        func space(_ height: CGFloat) {
            y = min(y + height, pageBottom)
        }

        // A body line; wraps and page-breaks as needed.
        func line(_ text: String, font: UIFont = .systemFont(ofSize: 11), color: UIColor = PDFBuilder.inkText, x: CGFloat = 50, width: CGFloat = 505, spacing: CGFloat = 3) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let h = PDFBuilder.textHeight(text, attrs: attrs, width: width)
            guard h > pageBottom - Self.top else {
                breakIfNeeded(h)
                text.draw(in: CGRect(x: x, y: y, width: width, height: h), withAttributes: attrs)
                y += h + spacing
                return
            }
            // Taller than a whole page (a very long note): a single draw
            // would run through the footer and off the page. Emit it in
            // whole-word chunks that each fit the space left on the page.
            var chunk = ""
            func flush() {
                let ch = PDFBuilder.textHeight(chunk, attrs: attrs, width: width)
                chunk.draw(in: CGRect(x: x, y: y, width: width, height: ch), withAttributes: attrs)
                y += ch
            }
            for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = chunk.isEmpty ? String(word) : chunk + " " + word
                if !chunk.isEmpty, PDFBuilder.textHeight(candidate, attrs: attrs, width: width) > pageBottom - y {
                    flush()
                    beginPage()
                    chunk = String(word)
                } else {
                    chunk = candidate
                }
            }
            if !chunk.isEmpty { flush() }
            y += spacing
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
            // A note taller than a page goes through line(), which splits it.
            guard h <= pageBottom - Self.top else {
                line("\(date)  \(body)", x: x, width: width, spacing: 4)
                return
            }
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
        // nil for a day the person never set this value (see the gates below).
        let value: (DailyLogSnapshot) -> Double?
    }

    @MainActor
    private static func trendChartImages(logs: [DailyLogSnapshot]) -> [UIImage] {
        // A "trend" of one point is noise; skip charts entirely for tiny sets.
        guard logs.count >= 2 else { return [] }
        let sorted = logs.sorted { $0.date < $1.date }
        let specs: [TrendSpec] = [
            // Gated on the edit flags, like the in-app charts and PatternEngine:
            // an untouched field holds DailyLog's default (mood 3, energy 5…),
            // and a doctor's report must not chart that as a reading.
            TrendSpec(title: "Mood (1–5)",          ink: inkMood,   yDomain: 1...5)  { $0.didEditMood ? Double($0.mood) : nil },
            TrendSpec(title: "Energy (0–10)",       ink: inkEnergy, yDomain: 0...10) { $0.didEditMetrics ? Double($0.energy) : nil },
            TrendSpec(title: "Sleep quality (0–10)", ink: inkSleep,  yDomain: 0...10) { $0.didEditMetrics ? Double($0.sleepQuality) : nil },
            TrendSpec(title: "Anxiety (0–10)",      ink: inkStress, yDomain: 0...10) { $0.didEditMetrics ? Double($0.stressLevel) : nil },
        ]
        return specs.compactMap { spec in
            let points = sorted.compactMap { log in spec.value(log).map { (date: log.date, value: $0) } }
            guard points.count >= 2 else { return nil }
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
        cursor.section("Your rhythm at a glance")
        for pair in stride(from: 0, to: charts.count, by: 2) {
            cursor.breakIfNeeded(chartSize.height + 8)
            cursor.image(charts[pair], at: 40, size: chartSize, advance: pair + 1 >= charts.count)
            if pair + 1 < charts.count {
                cursor.image(charts[pair + 1], at: 40 + chartSize.width + 14, size: chartSize, advance: true)
            }
        }
    }

    // Weekly reflections folded in from the retired Personal Summary: per week,
    // the star rating, prompt responses, and weekly intentions. Rendered
    // compactly inline (not a page-per-week). `reviews` arrive newest-first from
    // the caller; the snapshot carries no date, so we keep that order as given.
    private static func drawWeeklyReflections(_ reviews: [WeeklyReviewSnapshot], cursor: Cursor) {
        guard !reviews.isEmpty else { return }
        let bodyFont = UIFont.systemFont(ofSize: 11)
        cursor.section("Weekly reflections")
        for review in reviews {
            cursor.line(review.weekLabel, font: .systemFont(ofSize: 12, weight: .semibold), spacing: 2)
            if review.overallRating > 0 {
                let stars = String(repeating: "★", count: review.overallRating)
                    + String(repeating: "☆", count: 5 - review.overallRating)
                cursor.line("Overall: \(stars) (\(review.overallRating)/5)", font: bodyFont, color: inkSecondary, spacing: 3)
            }
            for response in review.promptResponses where !response.response.isEmpty {
                cursor.line(response.section, font: .systemFont(ofSize: 10.5, weight: .medium), color: inkSecondary, spacing: 1)
                cursor.line(response.response, font: bodyFont, x: 60, width: 495, spacing: 4)
            }
            if !review.intentionsForTomorrow.isEmpty {
                cursor.line("Intentions: \(review.intentionsForTomorrow)", font: bodyFont, spacing: 8)
            }
        }
    }

    // MARK: - Report

    // Order: patterns and the clinical sections first — the parts a doctor
    // reads — then, only when included, the person's own writing. The diary
    // sections used to come before the averages and symptoms, so a report
    // handed over at an appointment opened with private journal entries.
    private static func renderReport(ctx: UIGraphicsPDFRendererContext, paper: PaperSize, logs: [DailyLogSnapshot], charts: [UIImage], insights: [InsightCard], reviews: [WeeklyReviewSnapshot], medications: [MedicationSnapshot], flares: [FlareSnapshot], customTrackers: [CustomTrackerSnapshot], menopause: [MenopausalTransition] = [], range: ClosedRange<Date>? = nil, includePersonalNotes: Bool = true) {
        let cursor = Cursor(ctx: ctx, paper: paper)
        cursor.beginPage()
        drawReportHeader(
            cursor: cursor,
            title: reportTitle,
            intro: "A look back at the days you logged — what shifted, what held steady, and a few patterns worth noticing.",
            logs: logs,
            range: range
        )

        let bodyFont = UIFont.systemFont(ofSize: 11)

        // ===== Part 1 · What stood out =====

        // What we're noticing (Pattern Insights) — moved to the top.
        cursor.section("What we're noticing")
        // Computed over THIS report's date range, so it can differ from the
        // Insights tab, which always looks at the last 90 days.
        cursor.line("Patterns found in your logs from this date range, offered for reflection — not medical advice.",
                    font: .systemFont(ofSize: 9.5), color: inkSecondary, x: 40, width: 515, spacing: 8)
        if insights.isEmpty {
            cursor.line("No patterns detected from the current log set.", font: bodyFont, color: inkSecondary)
        } else {
            for insight in insights {
                cursor.line("\(insight.title) — \(InsightStrength(confidence: insight.confidence).plainLabel) signal",
                            font: .systemFont(ofSize: 11, weight: .semibold), spacing: 2)
                cursor.line(insight.detail, font: bodyFont, color: inkSecondary, x: 60, width: 495, spacing: 10)
            }
        }

        // Your rhythm at a glance (Trends). drawChartGrid draws its own section header.
        drawChartGrid(charts, cursor: cursor)

        // ===== Part 2 · The details =====

        // How your days felt (Average Metrics).
        if !logs.isEmpty {
            cursor.section("How your days felt")
            // Each average runs only over days that actually recorded it —
            // mood over didEditMood days, the sliders over didEditMetrics days.
            // Averaging every log folded DailyLog's defaults (mood 3, energy 5,
            // sleep 7h…) into figures a clinician reads as measurements.
            let moodLogs = logs.filter(\.didEditMood)
            let metricLogs = logs.filter(\.didEditMetrics)
            func avg(_ subset: [DailyLogSnapshot], _ value: (DailyLogSnapshot) -> Double) -> String? {
                guard !subset.isEmpty else { return nil }
                return String(format: "%.1f", subset.map(value).reduce(0, +) / Double(subset.count))
            }
            func line(_ label: String, _ value: String?, _ suffix: String) -> String {
                value.map { "\(label): \($0)\(suffix)" } ?? "\(label): not recorded"
            }
            let metricLines = [
                line("Mood", avg(moodLogs) { Double($0.mood) }, "/5"),
                line("Energy", avg(metricLogs) { Double($0.energy) }, "/10"),
                line("Avg sleep", avg(metricLogs) { $0.sleepHours }, " hrs"),
                line("Sleep quality", avg(metricLogs) { Double($0.sleepQuality) }, "/10"),
                line("Pain / ache", avg(metricLogs) { Double($0.painLevel) }, "/10"),
                line("Brain fog", avg(metricLogs) { Double($0.brainFogLevel) }, "/10"),
                line("Anxiety", avg(metricLogs) { Double($0.stressLevel) }, "/10"),
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

        // Symptoms (Symptom Frequency + severity).
        let entries = logs.flatMap(\.symptoms)
        let symptomCounts = entries.reduce(into: [String: Int]()) { $0[$1.name, default: 0] += 1 }
        cursor.section("Symptoms")
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

        // What tends to be around (Common Factors).
        let factorCounts = logs.flatMap(\.factors).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if !factorCounts.isEmpty {
            cursor.section("What tends to be around")
            let maxFactor = factorCounts.values.max() ?? 1
            for (factor, count) in factorCounts.sorted(by: { $0.value > $1.value }) {
                cursor.bar("\(factor) — \(count) day\(count == 1 ? "" : "s")",
                           fraction: CGFloat(count) / CGFloat(maxFactor), color: inkMood)
            }
        }

        // Daily basics.
        let basicsCounts = logs.flatMap(\.basicsCompleted).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if !basicsCounts.isEmpty {
            cursor.section("Daily basics")
            for (basic, count) in basicsCounts.sorted(by: { $0.value > $1.value }) {
                cursor.bar("\(basic) — \(count) of \(logs.count) days",
                           fraction: CGFloat(count) / CGFloat(max(logs.count, 1)), color: inkSleep)
            }
        }

        // From your Health data (HealthKit averages).
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
            cursor.section("From your Health data")
            for line in hkLines {
                cursor.line(line, font: bodyFont)
            }
        }

        // Health context: a state the clinician should know about, read from
        // Health and never entered in Cadence.
        let dateFmt = Date.FormatStyle().month(.abbreviated).day().year()
        if !menopause.isEmpty {
            cursor.section("Health context")
            for transition in menopause.sorted(by: { $0.began < $1.began }) {
                cursor.line("\(transition.state.rawValue.capitalized) — recorded \(transition.began.formatted(dateFmt))", font: bodyFont)
            }
        }

        // Medications.
        if !medications.isEmpty {
            cursor.section("Medications")
            for med in medications.sorted(by: { $0.startDate > $1.startDate }) {
                let range = "from \(med.startDate.formatted(dateFmt))" + (med.endDate.map { " to \($0.formatted(dateFmt))" } ?? " (ongoing)")
                cursor.line("\(med.displayLabel) — \(range)", font: bodyFont)
            }
        }

        // Flares.
        if !flares.isEmpty {
            cursor.section("Flares")
            for flare in flares.sorted(by: { $0.startDate > $1.startDate }) {
                let range = flare.endDate.map { "\(flare.startDate.formatted(dateFmt)) – \($0.formatted(dateFmt))" }
                    ?? "since \(flare.startDate.formatted(dateFmt)) (ongoing)"
                cursor.line("\(range): \(flare.durationDays) day\(flare.durationDays == 1 ? "" : "s"), peak \(flare.peakSeverity)/10", font: bodyFont)
            }
        }

        // ===== Part 3 · In your own words (optional) =====
        if includePersonalNotes {
            drawPersonalNotes(logs: logs, reviews: reviews, cursor: cursor)
        }
    }

    private static func drawPersonalNotes(logs: [DailyLogSnapshot], reviews: [WeeklyReviewSnapshot], cursor: Cursor) {
        drawWeeklyReflections(reviews, cursor: cursor)

        // Moments you marked (Peaks & Valleys).
        let dayFmt = Date.FormatStyle().month(.abbreviated).day()
        let peaksAndValleysDays = logs
            .filter { !$0.peaksAndValleysNote.isEmpty || $0.hasPeaksAndValleysVoiceMemo }
            .sorted { $0.date > $1.date }
        if !peaksAndValleysDays.isEmpty {
            cursor.section("Moments you marked")
            for log in peaksAndValleysDays {
                var body = log.peaksAndValleysNote.isEmpty ? "(voice memo only)" : log.peaksAndValleysNote
                if log.hasPeaksAndValleysVoiceMemo && !log.peaksAndValleysNote.isEmpty {
                    body += " (+ voice memo)"
                }
                cursor.datedLine(log.date.formatted(dayFmt), body)
            }
        }

        // Notes to yourself (daily Intentions for Tomorrow).
        let intentionDays = logs.filter { !$0.intentionsForTomorrow.isEmpty }.sorted { $0.date > $1.date }
        if !intentionDays.isEmpty {
            cursor.section("Notes to yourself")
            for log in intentionDays {
                cursor.datedLine(log.date.formatted(dayFmt), log.intentionsForTomorrow)
            }
        }

        // In your words (Daily Notes).
        let noteDays = logs.filter { !$0.freeNote.isEmpty }.sorted { $0.date > $1.date }
        if !noteDays.isEmpty {
            cursor.section("In your words")
            for log in noteDays {
                cursor.datedLine(log.date.formatted(dayFmt), log.freeNote)
            }
        }
    }

    // MARK: - Shared header

    private static func drawReportHeader(cursor: Cursor, title: String, intro: String? = nil, logs: [DailyLogSnapshot], range: ClosedRange<Date>? = nil) {
        title.draw(in: CGRect(x: 40, y: cursor.y, width: 420, height: 30),
                   withAttributes: [.font: UIFont.systemFont(ofSize: 23, weight: .bold), .foregroundColor: inkText])

        let rightStyle = NSMutableParagraphStyle()
        rightStyle.alignment = .right
        "Generated \(Date.now.formatted(date: .abbreviated, time: .omitted))"
            .draw(in: CGRect(x: 380, y: cursor.y + 10, width: 175, height: 14),
                  withAttributes: [.font: UIFont.systemFont(ofSize: 9.5), .foregroundColor: inkSecondary, .paragraphStyle: rightStyle])
        cursor.y += 34

        let subtitle: String
        if let range {
            subtitle = coverage(loggedDays: logs.count, range: range).label
        } else if let earliest = logs.map(\.date).min(), let latest = logs.map(\.date).max() {
            let spanDays = (Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0) + 1
            subtitle = "\(earliest.formatted(date: .abbreviated, time: .omitted)) – \(latest.formatted(date: .abbreviated, time: .omitted))"
                + " · \(logs.count) of \(spanDays) days logged"
        } else {
            subtitle = "No logged days in the selected range"
        }
        subtitle.draw(in: CGRect(x: 40, y: cursor.y, width: 515, height: 16),
                      withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: inkSecondary])
        cursor.y += 24

        if let intro {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 10.5),
                .foregroundColor: inkSecondary,
            ]
            let h = textHeight(intro, attrs: attrs, width: 515)
            intro.draw(in: CGRect(x: 40, y: cursor.y, width: 515, height: h), withAttributes: attrs)
            cursor.y += h + 8
        }

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
                    // From the domain floor, not 0 — mood's axis starts at 1.
                    AreaMark(x: .value("Day", point.date),
                             yStart: .value(title, yDomain.lowerBound),
                             yEnd: .value(title, point.value))
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
