import SwiftUI
import Charts

struct TrendChartView: View {
    let logs: [DailyLog]   // pre-filtered and sorted ascending by caller
    let metric: ChartMetric
    let range: InsightsViewModel.ChartRange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(metric.label, systemImage: metric.icon)
                    .font(.headline)
                    .foregroundStyle(metric.color)
                Spacer()
                if let avg = average {
                    Text("Avg: \(String(format: "%.1f", avg))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Chart(logs) { log in
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

    private var average: Double? {
        let values = logs.map { metric.value(for: $0) }
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

    func value(for log: DailyLog) -> Double {
        switch self {
        case .mood:   return Double(log.mood)
        case .energy: return Double(log.energy)
        case .sleep:  return Double(log.sleepQuality)
        case .stress: return Double(log.stressLevel)
        }
    }
}
