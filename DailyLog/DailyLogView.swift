import SwiftUI
import SwiftData

struct DailyLogView: View {
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @State private var showingInputFlow = false
    @State private var selectedLog: DailyLog?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CadenceLayout.sectionSpacing) {
                    todaySection
                    recentLogs
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(CadenceColor.background)
            .navigationTitle("Daily Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingInputFlow = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingInputFlow) {
                LogInputFlow(existingLog: todayLog)
            }
            .sheet(item: $selectedLog) { log in
                LogDetailView(log: log)
            }
        }
    }

    private var todayLog: DailyLog? {
        logs.first { Calendar.current.isDateInToday($0.date) }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                if let log = todayLog {
                    Text(log.isComplete ? "Complete" : "In Progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(log.isComplete ? CadenceColor.successGreen : CadenceColor.energyOrange)
                }
            }

            if let log = todayLog {
                Button {
                    selectedLog = log
                } label: {
                    LogRowView(log: log)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showingInputFlow = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(CadenceColor.accent)
                        Text("Start today's log")
                            .foregroundStyle(CadenceColor.accent)
                        Spacer()
                        Text("~90 sec")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .cadenceCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent").font(.headline)
            ForEach(logs.filter { !Calendar.current.isDateInToday($0.date) }.prefix(14)) { log in
                Button {
                    selectedLog = log
                } label: {
                    LogRowView(log: log)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LogRowView: View {
    let log: DailyLog

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(log.date.formatted(.dateTime.day()))
                    .font(.title2.bold())
                Text(log.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(log.dateLabel).font(.subheadline.bold())
                if !log.symptoms.isEmpty {
                    Text(log.symptoms.map { $0.emoji }.joined(separator: " "))
                        .font(.body)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ScoreBadge(value: log.mood, total: 5, color: CadenceColor.moodBlue)
                ScoreBadge(value: log.energy, total: 10, color: CadenceColor.energyOrange)
            }
        }
        .cadenceCard()
        .opacity(log.isComplete ? 1 : 0.7)
    }
}
