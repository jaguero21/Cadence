import SwiftUI

struct MetricSlider: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...10
    var labelLow: String = "Low"
    var labelHigh: String = "High"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(value)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .animation(CadenceAnimation.smooth, value: value)
            }

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { newVal in
                            let rounded = Int(newVal.rounded())
                            if rounded != value { value = rounded }
                        }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .tint(color)
                .sensoryFeedback(.impact(weight: .light), trigger: value)

                HStack {
                    Text(labelLow).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(labelHigh).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .cadenceCard()
    }
}

struct ScoreBadge: View {
    let value: Int
    let total: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: Double(value) / Double(total))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.caption.bold())
                .foregroundStyle(color)
        }
        .frame(width: 36, height: 36)
    }
}

struct StreakBadge: View {
    let count: Int

    // Streak milestones worth celebrating. On these days the flame goes gold,
    // bounces, and the badge says so — a streak feature should notice.
    static let milestones: Set<Int> = [7, 14, 30, 50, 100, 200, 365]

    private var isMilestone: Bool { Self.milestones.contains(count) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(isMilestone ? .yellow : .orange)
                .symbolEffect(.bounce, options: .repeat(2), value: isMilestone)
            Text("\(count)")
                .font(.subheadline.bold())
                .contentTransition(.numericText())
            Text(isMilestone ? "day streak!" : (count == 1 ? "day" : "days"))
                .font(.subheadline)
                .foregroundStyle(isMilestone ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isMilestone ? AnyShapeStyle(.yellow.opacity(0.18)) : AnyShapeStyle(.orange.opacity(0.12)),
            in: Capsule()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMilestone
            ? "Milestone: \(count) day logging streak"
            : "\(count) day logging streak")
    }
}
