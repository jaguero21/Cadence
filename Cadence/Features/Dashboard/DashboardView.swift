import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationService) private var notificationService
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @State private var vm = DashboardViewModel()
    @State private var showingDailyLog = false
    @State private var showingWeeklyReview = false

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
                    quickStats
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(CadenceColor.background)
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
            .onAppear { vm.refresh(logs: logs, reviews: reviews, notifications: notificationService) }
            .onChange(of: logs)    { _, _ in vm.refresh(logs: logs, reviews: reviews, notifications: notificationService) }
            .onChange(of: reviews) { _, _ in vm.refresh(logs: logs, reviews: reviews, notifications: notificationService) }
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
                    Image(systemName: vm.todayLog?.isComplete == true ? "checkmark" : "pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
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
            }
            .cadenceCard()
        }
        .buttonStyle(.plain)
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
                    Text("New Insight")
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
            VStack(alignment: .leading, spacing: 12) {
                Text("7-Day Snapshot")
                    .font(.headline)
                HStack(spacing: 12) {
                    statPill(label: "Mood", value: avgMood, color: CadenceColor.moodBlue)
                    statPill(label: "Energy", value: avgEnergy, color: CadenceColor.energyOrange)
                    statPill(label: "Logs", value: recent.count, color: CadenceColor.successGreen, suffix: "/ 7")
                }
            }
        }
    }

    private func statPill(label: String, value: Int, color: Color, suffix: String = "/ 10") -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(suffix)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(CadenceColor.cardBG, in: RoundedRectangle(cornerRadius: 12))
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
