import SwiftUI
import Charts

// What a trend chart draws: display metadata plus a per-log value extractor.
// Built-in metrics (ChartMetric.series) and user-defined trackers (.custom)
// both map into this, so custom trackers get the identical average-line and
// period-comparison treatment. `value` returns nil for days without data —
// a custom tracker not logged that day is skipped, never drawn as zero.
struct ChartSeries {
    let label: String
    let icon: String
    let color: Color
    let yDomain: ClosedRange<Double>
    // nil = direction unknowable (custom trackers: is "Hydration" up good? is
    // "Screen time"?). The comparison badge then shows the delta neutrally
    // instead of guessing Improved/Worsened.
    let higherIsBetter: Bool?
    let value: (DailyLog) -> Double?

    func isImprovement(delta: Double) -> Bool? {
        higherIsBetter.map { (delta > 0) == $0 }
    }

    static func custom(_ tracker: CustomTracker) -> ChartSeries {
        // Capture plain values, not the @Model, so the closure can't touch a
        // deleted tracker's backing data.
        let id = tracker.id
        let range = tracker.range
        return ChartSeries(
            label: tracker.name,
            icon: "slider.horizontal.3",
            color: CadenceColor.accent,
            yDomain: Double(range.lowerBound)...Double(range.upperBound),
            higherIsBetter: nil,
            value: { log in
                log.customMetrics.first { $0.trackerID == id }.map { Double($0.value) }
            }
        )
    }
}

struct TrendChartView: View {
    let logs: [DailyLog]   // pre-filtered and sorted ascending by caller
    let series: ChartSeries
    let range: InsightsViewModel.ChartRange
    var previousLogs: [DailyLog] = []   // same-length window immediately before, for comparison
    // Lets the parent open the scrubbed day (e.g. LogDetailView). nil = chart
    // still scrubs, just without the drill-in button.
    var onOpenDay: ((Date) -> Void)? = nil

    // Live scrub position (non-nil only while the finger is down) and the last
    // day it landed on, which persists after release so the footer can offer
    // the drill-in.
    @State private var selection: Date?
    @State private var pinned: (date: Date, value: Double)?

    private var points: [(date: Date, value: Double)] {
        logs.compactMap { log in series.value(log).map { (log.date, $0) } }
    }

    // Snap a scrub position to the nearest plotted day — custom trackers skip
    // unlogged days, so the raw x-position rarely hits a point exactly.
    static func nearestPoint(to target: Date, in points: [(date: Date, value: Double)]) -> (date: Date, value: Double)? {
        points.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(series.label, systemImage: series.icon)
                    .font(.headline)
                    .foregroundStyle(series.color)
                Spacer()
                // The period average itself is annotated on the chart's RuleMark,
                // so the header only carries the period-over-period badge.
                comparisonBadge
            }

            let points = points
            if points.isEmpty {
                Text("No entries in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart {
                    ForEach(points, id: \.date) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value(series.label, point.value)
                        )
                        .foregroundStyle(series.color.opacity(0.15))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(series.label, point.value)
                        )
                        .foregroundStyle(series.color)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(series.label, point.value)
                        )
                        .foregroundStyle(series.color)
                        .symbolSize(25)
                    }

                    if let avg = average {
                        RuleMark(y: .value("Average", avg))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(series.color.opacity(0.5))
                            .annotation(position: .topLeading, alignment: .leading) {
                                Text("avg \(String(format: "%.1f", avg))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    // Scrub lollipop: vertical rule + enlarged point + value
                    // bubble on the day nearest the finger.
                    if let selection, let picked = Self.nearestPoint(to: selection, in: points) {
                        RuleMark(x: .value("Selected", picked.date))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.secondary.opacity(0.5))
                        PointMark(
                            x: .value("Date", picked.date),
                            y: .value(series.label, picked.value)
                        )
                        .foregroundStyle(series.color)
                        .symbolSize(90)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            Text(String(format: "%.1f", picked.value))
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(series.color.opacity(0.15), in: Capsule())
                        }
                    }
                }
                .chartYScale(domain: series.yDomain)
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .stride(by: .day, count: range == .sevenDay ? 1 : 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartXSelection(value: $selection)
                .frame(height: 160)
                .onChange(of: selection) { _, newValue in
                    // Remember the last scrubbed day so the drill-in footer
                    // survives the finger lifting (selection resets to nil).
                    if let newValue, let picked = Self.nearestPoint(to: newValue, in: points) {
                        pinned = picked
                    }
                }
                .onChange(of: range) { _, _ in
                    pinned = nil
                    selection = nil
                }

                if let pinned {
                    HStack(spacing: 8) {
                        Text("\(pinned.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) — \(String(format: "%.1f", pinned.value))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let onOpenDay {
                            Button {
                                onOpenDay(pinned.date)
                            } label: {
                                HStack(spacing: 2) {
                                    Text("View day")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(series.color)
                        }
                        Button {
                            self.pinned = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear selection")
                    }
                    .transition(.opacity)
                }
            }
        }
        .cadenceCard()
    }

    @ViewBuilder
    private var comparisonBadge: some View {
        if let avg = average, let prev = previousAverage {
            let delta = avg - prev
            if abs(delta) >= ChartThreshold.comparisonBadgeMinimumDelta {
                let improved = series.isImprovement(delta: delta)
                // Built with String(localized:) so the direction words extract
                // into the catalog; a bare ternary String would not localize.
                let direction: String = switch improved {
                case true?:  String(localized: "Improved")
                case false?: String(localized: "Worsened")
                case nil:    String(localized: "Changed")
                }
                HStack(spacing: 2) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.1f", delta))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(badgeColor(improved: improved))
                .accessibilityLabel("\(direction) by \(String(format: "%.1f", abs(delta))) versus the previous \(range.voiceLabel)")
            }
        }
    }

    private func badgeColor(improved: Bool?) -> Color {
        switch improved {
        case true?:  return CadenceColor.successGreen
        case false?: return CadenceColor.stressRed
        case nil:    return .secondary
        }
    }

    private var average: Double? { Self.mean(logs.compactMap { series.value($0) }) }
    private var previousAverage: Double? { Self.mean(previousLogs.compactMap { series.value($0) }) }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum ChartMetric: CaseIterable {
    case mood, energy, sleep, stress

    var series: ChartSeries {
        ChartSeries(
            label: label,
            icon: icon,
            color: color,
            yDomain: yDomain,
            higherIsBetter: higherIsBetter,
            value: { [self] log in value(for: log) }
        )
    }

    var label: String {
        switch self {
        case .mood:   return "Mood"
        case .energy: return "Energy"
        case .sleep:  return "Sleep Quality"
        case .stress: return "Stress"
        }
    }

    var icon: String {
        switch self {
        case .mood:   return "face.smiling"
        case .energy: return "bolt.fill"
        case .sleep:  return "moon.fill"
        case .stress: return "brain.head.profile"
        }
    }

    var color: Color {
        switch self {
        case .mood:   return CadenceColor.moodBlue
        case .energy: return CadenceColor.energyOrange
        case .sleep:  return CadenceColor.sleepPurple
        case .stress: return CadenceColor.stressRed
        }
    }

    var yDomain: ClosedRange<Double> {
        switch self {
        case .mood:   return 1...5
        case .energy, .sleep, .stress: return 0...10
        }
    }

    // For stress, a lower value is the desirable direction; for the rest, higher.
    var higherIsBetter: Bool {
        switch self {
        case .mood, .energy, .sleep: return true
        case .stress: return false
        }
    }

    // Whether a change of `delta` (current minus previous average) is an improvement.
    func isImprovement(delta: Double) -> Bool {
        (delta > 0) == higherIsBetter
    }

    func value(for log: DailyLog) -> Double {
        switch self {
        case .mood:   return Double(log.mood)
        case .energy: return Double(log.energy)
        case .sleep:  return Double(log.sleepQuality)
        case .stress: return Double(log.stressLevel)
        }
    }
}
