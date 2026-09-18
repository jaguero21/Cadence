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

    // Two keys rather than one Vary-by-Plural entry, on Xcode's own instruction:
    // a plural variation whose value doesn't reference the number is a hard
    // build error ("use separate top-level strings for one and greater than
    // one"). The count is rendered by its own bold Text in the badge, so these
    // values are the bare noun and can't carry it.
    //
    // Returns Text rather than branching inside a Group — same shape as
    // WeeklyReviewView.statusText, and it keeps ONE view identity as the count
    // crosses 1→2 or hits a milestone. A Group here builds _ConditionalContent,
    // whose identity changes on those transitions, inside a badge that animates
    // its count and flame deliberately.
    private var unitText: Text {
        if isMilestone { return Text("day streak!") }
        if count == 1 { return Text("day") }
        return Text("days")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(isMilestone ? .yellow : .orange)
                .cadenceSymbolBounce(value: isMilestone, repeating: 2)
            Text("\(count)")
                .font(.subheadline.bold())
                .contentTransition(.numericText())
            unitText
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
            ? Text("Milestone: \(count) day logging streak")
            : Text("\(count) day logging streak"))
    }
}
