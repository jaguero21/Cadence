import SwiftUI
import Charts

struct TrendChartView: View {
    let logs: [DailyLog]   // pre-filtered and sorted ascending by caller
    let metric: ChartMetric
    let range: InsightsViewModel.ChartRange
    var previousLogs: [DailyLog] = []   // same-length window immediately before, for comparison

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(metric.label, systemImage: metric.icon)
                    .font(.headline)
                    .foregroundStyle(metric.color)
                Spacer()
                // The period average itself is annotated on the chart's RuleMark,
                // so the header only carries the period-over-period badge.
                comparisonBadge
            }

            Chart {
                ForEach(logs) { log in
                    AreaMark(
                        x: .value("Date", log.date),
                        y: .value(metric.label, metric.value(for: log))
                    )
                    .foregroundStyle(metric.color.opacity(0.15))

                    LineMark(
                        x: .value("Date", log.date),
                        y: .value(metric.label, metric.value(for: log))
                    )
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", log.date),
                        y: .value(metric.label, metric.value(for: log))
                    )
                    .foregroundStyle(metric.color)
                    .symbolSize(25)
                }

                if let avg = average {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(metric.color.opacity(0.5))
                        .annotation(position: .topLeading, alignment: .leading) {
                            Text("avg \(String(format: "%.1f", avg))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: metric.yDomain)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .stride(by: .day, count: range == .sevenDay ? 1 : 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 160)
        }
        .cadenceCard()
    }

    @ViewBuilder
    private var comparisonBadge: some View {
        if let avg = average, let prev = previousAverage {
            let delta = avg - prev
            if abs(delta) >= ChartThreshold.comparisonBadgeMinimumDelta {
                let improved = metric.isImprovement(delta: delta)
                // Built with String(localized:) so the direction words extract
                // into the catalog; a bare ternary String would not localize.
                let direction = improved
                    ? String(localized: "Improved")
                    : String(localized: "Worsened")
                HStack(spacing: 2) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.1f", delta))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(improved ? CadenceColor.successGreen : CadenceColor.stressRed)
                .accessibilityLabel("\(direction) by \(String(format: "%.1f", abs(delta))) versus the previous \(range.voiceLabel)")
            }
        }
    }

    private var average: Double? { Self.mean(logs.map { metric.value(for: $0) }) }
    private var previousAverage: Double? { Self.mean(previousLogs.map { metric.value(for: $0) }) }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum ChartMetric: CaseIterable {
    case mood, energy, sleep, stress

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
