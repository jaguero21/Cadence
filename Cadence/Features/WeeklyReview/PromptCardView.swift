import SwiftUI

struct PromptCardView: View {
    let prompt: Prompt
    @Binding var response: String
    let index: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(index + 1) of \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(prompt.section)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CadenceColor.accent)
            }

            Text(prompt.question)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            TextField(prompt.placeholder, text: $response, axis: .vertical)
                .font(.body)
                .lineLimit(5...12)
                .padding(14)
                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .cadenceCard()
    }
}

struct WeekSummaryView: View {
    let review: WeeklyReview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Week at a Glance")
                .font(.title3.bold())

            HStack(spacing: 0) {
                summaryMetric(label: "Mood", value: review.avgMood, color: CadenceColor.moodBlue, icon: "face.smiling")
                Divider().frame(height: 50)
                summaryMetric(label: "Energy", value: review.avgEnergy, color: CadenceColor.energyOrange, icon: "bolt.fill")
                Divider().frame(height: 50)
                summaryMetric(label: "Sleep", value: review.avgSleep, color: CadenceColor.sleepPurple, icon: "moon.fill", suffix: "hrs")
            }

            if !review.topSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top symptoms this week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(review.topSymptoms, id: \.self) { symptom in
                            Text(symptom)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(CadenceColor.stressRed.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
        .cadenceCard()
    }

    private func summaryMetric(label: String, value: Double, color: Color, icon: String, suffix: String = "/ 10") -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(String(format: "%.1f", value))
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(suffix).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StarRatingDisplayView: View {
    let rating: Int
    var font: Font = .body
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(font)
                    .foregroundStyle(star <= rating ? Color.yellow : Color(.quaternaryLabel))
            }
        }
    }
}

struct StarRatingView: View {
    @Binding var rating: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("Overall, how was this week?")
                .font(.title3.bold())
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(CadenceAnimation.spring) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 36))
                            .foregroundStyle(star <= rating ? Color.yellow : Color(.quaternaryLabel))
                    }
                    .buttonStyle(.plain)
                    .hapticFeedback(.medium)
                    .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars") out of 5")
                    .accessibilityAddTraits(star == rating ? [.isSelected] : [])
                }
            }
        }
        .cadenceCard()
    }
}
