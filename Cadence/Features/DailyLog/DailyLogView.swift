import SwiftUI
import SwiftData

struct DailyLogView: View {
    @Query private var logs: [DailyLog]
    @State private var activeSheet: ActiveSheet?

    // referenceDate anchors the query window so a midnight rollover refreshes
    // the @Query in place instead of forcing a full view rebuild (which would
    // dismiss an open log sheet — the cause of the prior midnight data loss).
    init(referenceDate: Date = .now) {
        let day = Calendar.current.startOfDay(for: referenceDate)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: day) ?? .distantPast
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= cutoff }, sort: \DailyLog.date, order: .reverse)
    }

    private enum ActiveSheet: Identifiable {
        case inputFlow
        case viewingLog(DailyLog)

        var id: String {
            switch self {
            case .inputFlow: "inputFlow"
            case .viewingLog: "viewingLog"
            }
        }
    }

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
                        activeSheet = .inputFlow
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .inputFlow:
                    LogInputFlow(existingLog: todayLog)
                case .viewingLog(let log):
                    LogDetailView(log: log)
                }
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
                    activeSheet = .viewingLog(log)
                } label: {
                    LogRowView(log: log)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    activeSheet = .inputFlow
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

    private var pastLogs: [DailyLog] {
        Array(logs.drop(while: { Calendar.current.isDateInToday($0.date) }).prefix(14))
    }

    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent").font(.headline)
            ForEach(pastLogs) { log in
                Button {
                    activeSheet = .viewingLog(log)
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
