import SwiftUI

extension View {
    func cadenceCard() -> some View {
        self
            .padding(CadenceLayout.cardPadding)
            .background(CadenceColor.cardBG, in: RoundedRectangle(cornerRadius: CadenceLayout.cardCornerRadius))
    }

    func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
            self
        }
    }

    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            }
        )
    }
}

extension Color {
    static func metricColor(for value: Int, max: Int = 10, inverted: Bool = false) -> Color {
        let normalized = Double(value) / Double(max)
        let score = inverted ? 1.0 - normalized : normalized
        if score > 0.7 { return CadenceColor.successGreen }
        if score > 0.4 { return CadenceColor.energyOrange }
        return CadenceColor.stressRed
    }
}

extension Date {
    var startOfWeek: Date {
        let cal = Calendar.current
        return cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: self).date ?? self
    }

    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: .now, toGranularity: .weekOfYear)
    }
}
