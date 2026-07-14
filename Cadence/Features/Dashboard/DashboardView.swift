import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationService) private var notificationService
    @Query private var logs: [DailyLog]
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @State private var vm = DashboardViewModel()
    @State private var showingDailyLog = false
    @State private var showingWeeklyReview = false

    // referenceDate anchors the query window. The parent passes the current day
    // so that when it rolls over at midnight this view re-inits with a fresh
    // cutoff — updating the @Query without destroying its view state.
    init(referenceDate: Date = .now) {
        let day = Calendar.current.startOfDay(for: referenceDate)
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: day) ?? .distantPast
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= cutoff }, sort: \DailyLog.date, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CadenceLayout.sectionSpacing) {
                    greetingHeader
                    todayCard
                    weeklyCard
                    if let insight = vm.latestInsight {
                        insightPreviewCard(insight)
                    }
                    if logs.isEmpty {
                        emptyState
                    } else {
                        quickStats
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .readableColumn()
            }
            .background(AmbientMeshBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear { vm.refresh(logs: logs, reviews: reviews, medications: medications, notifications: notificationService) }
            .onChange(of: logs)    { _, _ in vm.refresh(logs: logs, reviews: reviews, medications: medications, notifications: notificationService) }
            .onChange(of: reviews) { _, _ in vm.refresh(logs: logs, reviews: reviews, medications: medications, notifications: notificationService) }
        }
    }

    // MARK: - Subviews

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.largeTitle.bold())
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.streak > 0 {
                StreakBadge(count: vm.streak)
            }
        }
        .padding(.top, 8)
    }

    private var todayCard: some View {
        Button {
            showingDailyLog = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(vm.todayLog?.isComplete == true ? CadenceColor.successGreen : CadenceColor.moodBlue)
                        .frame(width: 52, height: 52)
                    // An in-progress log with a chosen mood shows that mood —
                    // a glanceable "here's how today feels so far" instead of
                    // a generic pencil.
                    if vm.todayLog?.isComplete == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    } else if let log = vm.todayLog, log.didEditMood {
                        Text(MoodScale.emoji(for: log.mood))
                            .font(.system(size: 26))
                    } else {
                        Image(systemName: "pencil")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Log")
                        .font(.headline)
                    if let log = vm.todayLog {
                        Text(log.isComplete ? "Completed" : "In progress — tap to finish")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not started — 90 seconds")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .cadenceCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todayCardAccessibilityLabel)
        .sheet(isPresented: $showingDailyLog) {
            LogInputFlow(existingLog: vm.todayLog)
        }
    }

    private var weeklyCard: some View {
        Button {
            showingWeeklyReview = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(vm.thisWeekReview?.isComplete == true ? CadenceColor.successGreen : CadenceColor.sleepPurple)
                        .frame(width: 52, height: 52)
                    Image(systemName: vm.thisWeekReview?.isComplete == true ? "checkmark" : "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Review")
                        .font(.headline)
                    Text(vm.thisWeekReview?.isComplete == true ? "Completed this week" : "Ready to review")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .cadenceCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.thisWeekReview?.isComplete == true
            ? "Weekly Review, completed this week"
            : "Weekly Review, ready to review")
        .sheet(isPresented: $showingWeeklyReview) {
            ReviewFlowView(existingReview: vm.thisWeekReview, logs: logs)
        }
    }

    private func insightPreviewCard(_ insight: InsightCard) -> some View {
        NavigationLink {
            InsightsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    // "Top Pattern", not "New Insight" — cards are ranked by
                    // confidence, and this one may be weeks old. Don't claim
                    // novelty the data doesn't have.
                    Text("Top Pattern")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(insight.title)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .cadenceCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var quickStats: some View {
        let recent = Array(logs.prefix(7))
        let count = Double(recent.count)
        if count > 0 {
            let avgMood   = Int((Double(recent.map(\.mood).reduce(0, +)) / count).rounded())
            let avgEnergy = Int((Double(recent.map(\.energy).reduce(0, +)) / count).rounded())
            let avgSleep  = recent.map(\.sleepHours).reduce(0, +) / count
            VStack(alignment: .leading, spacing: 12) {
                Text("7-Day Snapshot")
                    .font(.headline)
                HStack(spacing: 10) {
                    statPill(label: "Mood", value: "\(avgMood)", color: CadenceColor.moodBlue, suffix: "/ 5")
                    statPill(label: "Energy", value: "\(avgEnergy)", color: CadenceColor.energyOrange)
                    statPill(label: "Sleep", value: String(format: "%.1f", avgSleep), color: CadenceColor.sleepPurple, suffix: "hrs")
                    statPill(label: "Logs", value: "\(recent.count)", color: CadenceColor.successGreen, suffix: "/ 7")
                }
            }
        }
    }

    private func statPill(label: String, value: String, color: Color, suffix: String = "/ 10") -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxHeight: .infinity)
            Text(suffix)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(CadenceColor.cardBG, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value) \(suffix)")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Log your first day to see insights")
                .font(.subheadline.weight(.medium))
            Text("Tap Today's Log above to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cadenceCard()
    }

    private var todayCardAccessibilityLabel: String {
        if let log = vm.todayLog {
            return log.isComplete ? "Today's Log, completed" : "Today's Log, in progress"
        }
        return "Today's Log, not started. Takes about 90 seconds."
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }
}
