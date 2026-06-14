import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @State private var selectedMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedLog: DailyLog?

    private var logsByDate: [Date: DailyLog] {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = cal.date(from: components),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)
        else { return [:] }
        let monthLogs = logs.filter { $0.date >= monthStart && $0.date < monthEnd }
        return Dictionary(
            monthLogs.map { (cal.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CadenceLayout.sectionSpacing) {
                    monthPicker
                    calendarGrid
                    if let log = selectedLog {
                        selectedLogPreview(log)
                    }
                }
                .padding(.horizontal)
            }
            .background(CadenceColor.background)
            .navigationTitle("History")
            .sheet(item: $selectedLog) { log in
                LogDetailView(log: log)
            }
        }
    }

    private var monthPicker: some View {
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth)
        let canGoForward = nextMonth.map { $0 <= .now } ?? false
        return HStack {
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(CadenceColor.accent)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(selectedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()
            Button {
                if let next = nextMonth { selectedMonth = next }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(canGoForward ? CadenceColor.accent : .secondary)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
    }

    private var calendarGrid: some View {
        let daysInMonth = daysForMonth(selectedMonth)
        let columns = Array(repeating: GridItem(.flexible()), count: 7)

        return VStack(spacing: 4) {
            // Day headers — rotated to match the locale's first weekday
            HStack(spacing: 0) {
                ForEach(Array(localizedWeekdayHeaders.enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day: day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .cadenceCard()
    }

    private func dayCell(day: Date) -> some View {
        let log = logsByDate[day]
        let isSelected = selectedLog.map { Calendar.current.isDate($0.date, inSameDayAs: day) } ?? false
        let isToday = Calendar.current.isDateInToday(day)
        let isFuture = day > Calendar.current.startOfDay(for: .now)

        return Button {
            if let log { selectedLog = log }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(cellBackground(log: log, isSelected: isSelected, isToday: isToday))
                    .frame(height: 40)

                VStack(spacing: 1) {
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(cellTextColor(log: log, isSelected: isSelected, isFuture: isFuture))
                    if let log {
                        Circle()
                            .fill(log.isComplete ? CadenceColor.successGreen : CadenceColor.energyOrange)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isFuture || log == nil)
        .accessibilityLabel(dayCellLabel(day: day, log: log, isToday: isToday))
        .accessibilityHint(log != nil && !isFuture ? "Double-tap to view details" : "")
    }

    private func dayCellLabel(day: Date, log: DailyLog?, isToday: Bool) -> String {
        let dateText = isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day())
        guard let log else { return "\(dateText), no log" }
        let status = log.isComplete ? "complete" : "in progress"
        return "\(dateText), logged \(status), mood \(log.mood) of 5"
    }

    private func cellBackground(log: DailyLog?, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return CadenceColor.accent }
        if isToday    { return CadenceColor.accent.opacity(0.15) }
        if let log {
            let mood = Double(log.mood) / 5.0
            return CadenceColor.moodBlue.opacity(0.1 + mood * 0.3)
        }
        return Color.clear
    }

    private func cellTextColor(log: DailyLog?, isSelected: Bool, isFuture: Bool) -> Color {
        if isSelected { return .white }
        if isFuture   { return Color(.quaternaryLabel) }
        if log == nil { return .secondary }
        return .primary
    }

    private func selectedLogPreview(_ log: DailyLog) -> some View {
        Button {
            selectedLog = log
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(log.dateLabel).font(.headline)
                HStack(spacing: 20) {
                    metricPill("Mood", value: log.mood, color: CadenceColor.moodBlue)
                    metricPill("Energy", value: log.energy, color: CadenceColor.energyOrange)
                    metricPill("Sleep Q", value: log.sleepQuality, color: CadenceColor.sleepPurple)
                }
                if !log.symptoms.isEmpty {
                    Text(log.symptoms.map { "\($0.emoji) \($0.name)" }.joined(separator: "  "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Tap to view full log →")
                    .font(.caption)
                    .foregroundStyle(CadenceColor.accent)
            }
            .cadenceCard()
        }
        .buttonStyle(.plain)
    }

    private func metricPill(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var localizedWeekdayHeaders: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols  // Sun-indexed, locale-aware
        let offset = cal.firstWeekday - 1          // 0-based: 0=Sun, 1=Mon, …
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func daysForMonth(_ date: Date) -> [Date?] {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: date)
        guard let first = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }

        let dayIndex = cal.component(.weekday, from: first) - 1  // 0-based, Sun=0
        let firstWeekdayIndex = cal.firstWeekday - 1
        let leadingBlanks = (dayIndex - firstWeekdayIndex + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: first))
        }
        return days
    }
}

struct LogDetailView: View {
    let log: DailyLog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Metrics") {
                    metricRow("Mood", value: "\(log.mood)/5", icon: "face.smiling", color: CadenceColor.moodBlue)
                    metricRow("Energy", value: "\(log.energy)/10", icon: "bolt.fill", color: CadenceColor.energyOrange)
                    metricRow("Sleep Quality", value: "\(log.sleepQuality)/10", icon: "moon.fill", color: CadenceColor.sleepPurple)
                    metricRow("Anxiety", value: "\(log.stressLevel)/10", icon: "brain.head.profile", color: CadenceColor.stressRed)
                }

                if !log.symptoms.isEmpty {
                    Section("Symptoms") {
                        ForEach(log.symptoms) { s in
                            HStack {
                                Text("\(s.emoji) \(s.name)")
                                Spacer()
                                Text("Severity: \(s.severity)/10")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }


                if !log.freeNote.isEmpty {
                    Section("Notes") {
                        Text(log.freeNote)
                    }
                }

                if log.hkSteps != nil || log.hkHRV != nil {
                    Section("HealthKit Data") {
                        if let steps = log.hkSteps {
                            Label("\(steps) steps", systemImage: "figure.walk")
                        }
                        if let hrv = log.hkHRV {
                            Label(String(format: "HRV: %.0f ms", hrv), systemImage: "waveform.path.ecg")
                        }
                        if let hr = log.hkRestingHR {
                            Label(String(format: "Resting HR: %.0f bpm", hr), systemImage: "heart.fill")
                        }
                    }
                }
            }
            .navigationTitle(log.dateLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func metricRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
