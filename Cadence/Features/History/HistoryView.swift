import SwiftUI
import SwiftData

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all         = "All days"
    case completed   = "Completed"
    case inProgress  = "In progress"
    case hasSymptoms = "Has symptoms"
    var id: String { rawValue }
}

struct HistoryView: View {
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @State private var selectedMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedLog: DailyLog?
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all

    private var isFiltering: Bool { !searchText.isEmpty || filter != .all }

    private var filteredLogs: [DailyLog] {
        logs.filter {
            Self.logMatches(
                isComplete: $0.isComplete,
                symptomNames: $0.symptoms.map(\.name),
                factors: $0.factors,
                note: $0.freeNote,
                filter: filter,
                query: searchText
            )
        }
    }

    // Pure match predicate, extracted so it's unit-testable without a ModelContext.
    static func logMatches(isComplete: Bool, symptomNames: [String], factors: [String], note: String, filter: HistoryFilter, query: String) -> Bool {
        let passesFilter: Bool
        switch filter {
        case .all:         passesFilter = true
        case .completed:   passesFilter = isComplete
        case .inProgress:  passesFilter = !isComplete
        case .hasSymptoms: passesFilter = !symptomNames.isEmpty
        }
        guard passesFilter else { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return symptomNames.contains { $0.localizedCaseInsensitiveContains(q) }
            || factors.contains { $0.localizedCaseInsensitiveContains(q) }
            || note.localizedCaseInsensitiveContains(q)
    }

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
                    if isFiltering {
                        resultsList
                    } else {
                        monthPicker
                        calendarGrid
                        if let log = selectedLog {
                            selectedLogPreview(log)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, isFiltering ? 8 : 0)
            }
            .background(CadenceColor.background)
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search symptoms, factors, notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .sheet(item: $selectedLog) { log in
                LogDetailView(log: log)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $filter) {
                ForEach(HistoryFilter.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(CadenceColor.accent)
        }
        .accessibilityLabel("Filter")
    }

    @ViewBuilder
    private var resultsList: some View {
        if filteredLogs.isEmpty {
            ContentUnavailableView(
                "No matching days",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term or filter.")
            )
            .padding(.top, 60)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filteredLogs) { log in
                    Button { selectedLog = log } label: { resultRow(log) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultRow(_ log: DailyLog) -> some View {
        let snippet = log.symptoms.map(\.name) + log.factors
        return HStack(spacing: 12) {
            Circle()
                .fill(log.isComplete ? CadenceColor.successGreen : CadenceColor.energyOrange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.dateLabel).font(.subheadline.weight(.medium))
                if !snippet.isEmpty {
                    Text(snippet.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !log.freeNote.isEmpty {
                    Text(log.freeNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .cadenceCard()
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
    private let attachmentStore = AttachmentStore()

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


                if !log.factors.isEmpty {
                    Section("Possible Triggers") {
                        ForEach(log.factors, id: \.self) { factor in
                            Label(factor, systemImage: "exclamationmark.triangle")
                        }
                    }
                }

                if !log.freeNote.isEmpty {
                    Section("Notes") {
                        Text(log.freeNote)
                    }
                }

                let photos = log.attachments.filter { $0.kind == .photo }
                if !photos.isEmpty {
                    Section("Photos") {
                        AttachmentPhotoStrip(photos: photos, store: attachmentStore, tileSize: 88)
                    }
                }

                let voiceNotes = log.attachments.filter { $0.kind == .audio }
                if !voiceNotes.isEmpty {
                    Section("Voice Notes") {
                        ForEach(voiceNotes) { note in
                            HStack(spacing: 10) {
                                AudioPlaybackButton(url: attachmentStore.url(for: note.filename))
                                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if log.hkSteps != nil || log.hkHRV != nil || log.hkRestingHR != nil
                    || log.hkSleepHours != nil || log.hkActiveEnergy != nil || log.hkMindfulMinutes != nil
                    || log.hkWristTemp != nil {
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
                        if let sleep = log.hkSleepHours {
                            Label(String(format: "Sleep (measured): %.1f hrs", sleep), systemImage: "moon.zzz.fill")
                        }
                        if let energy = log.hkActiveEnergy {
                            Label(String(format: "Active energy: %.0f kcal", energy), systemImage: "flame.fill")
                        }
                        if let mindful = log.hkMindfulMinutes {
                            Label(String(format: "Mindful minutes: %.0f min", mindful), systemImage: "brain.head.profile")
                        }
                        if let temp = log.hkWristTemp {
                            Label(String(format: "Wrist temp: %.1f °C", temp), systemImage: "thermometer.medium")
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
