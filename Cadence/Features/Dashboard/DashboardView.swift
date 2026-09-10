import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationService) private var notificationService
    @Query private var logs: [DailyLog]
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \Flare.startDate, order: .reverse) private var flares: [Flare]
    @Query(sort: \CustomTracker.sortOrder) private var customTrackers: [CustomTracker]
    // Objective HealthKit values (local-only store), observed rather than
    // fetched so refreshes never re-enter a SwiftUI update.
    @Query private var healthRows: [HealthSnapshot]
    @State private var vm = DashboardViewModel()
    @State private var showingDailyLog = false
    @State private var showingWeeklyReview = false
    @State private var refreshTask: Task<Void, Never>?

    // referenceDate anchors the query window. The parent passes the current day
    // so that when it rolls over at midnight this view re-inits with a fresh
    // cutoff — updating the @Query without destroying its view state.
    // Retained (not just used for the cutoff) so the 7-Day Snapshot windows
    // against the same day the parent considers "today" — including after a
    // midnight rollover, which re-inits this view with a new reference date.
    private let referenceDate: Date

    init(referenceDate: Date = .now) {
        self.referenceDate = referenceDate
        let day = Calendar.current.startOfDay(for: referenceDate)
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: day) ?? .distantPast
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= cutoff }, sort: \DailyLog.date, order: .reverse)
        // Windowed to match `logs`. HealthSnapshot is per-day data, not a small
        // reference table, so an unbounded query here would materialise every
        // row the device has ever recorded to join against 90 days of logs.
        _healthRows = Query(filter: #Predicate<HealthSnapshot> { $0.date >= cutoff })
    }

    var body: some View {
        NavigationStack {
            content
                .onAppear { scheduleRefresh() }
                .onChange(of: logs)           { _, _ in scheduleRefresh() }
                .onChange(of: healthRows)     { _, _ in scheduleRefresh() }
                .onChange(of: reviews)        { _, _ in scheduleRefresh() }
                .onChange(of: medications)    { _, _ in scheduleRefresh() }
                .onChange(of: flares)         { _, _ in scheduleRefresh() }
                .onChange(of: customTrackers) { _, _ in scheduleRefresh() }
        }
    }

    // Split out of `body` so the type checker can solve the view hierarchy
    // and the onAppear/onChange chain as two separate expressions — inlined
    // together, six chained modifiers (five of them generic over a different
    // Equatable query type) on top of this tree is enough to make the
    // compiler give up with "unable to type-check in reasonable time."
    private var content: some View {
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
        // Text(verbatim:), not "": a bare empty literal is a LocalizedStringKey
        // and extracts an empty key into the catalog, where it sits forever as
        // an untranslated string nobody can translate.
        .navigationTitle(Text(verbatim: ""))
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
    }

    // Single entry point for every trigger above — keeps the 6 call sites
    // from drifting out of sync (medications was previously threaded into
    // vm.refresh() with no onChange to ever trigger it) and coalesces
    // same-runloop-tick triggers into one vm.refresh() call: a single
    // multi-model save (e.g. a JSON restore inserting logs, flares, and
    // trackers together) would otherwise re-run the full
    // PatternEngine.allInsights pass once per changed query instead of once.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            guard !Task.isCancelled else { return }
            vm.refresh(logs: logs, health: healthRows, reviews: reviews, medications: medications, flares: flares, customTrackers: customTrackers, notifications: notificationService)
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
                        (log.isComplete
                            ? Text("Completed")
                            : Text("In progress — tap to finish"))
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
                    (vm.thisWeekReview?.isComplete == true
                        ? Text("Completed this week")
                        : Text("Ready to review"))
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
            ? Text("Weekly Review, completed this week")
            : Text("Weekly Review, ready to review"))
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
        // Computed by the pure helper, which windows to the real trailing seven
        // days and averages only over values the user actually entered — see
        // DashboardViewModel.sevenDayStats.
        // Windowed BEFORE snapshotting. `sevenDayStats` filters to today-6...today
        // itself, but reaching it meant building a DailyLogSnapshot for all ~90
        // logs the query holds — each one copying symptoms, factors, basics and
        // custom metrics — on every body evaluation, to then discard 83 of them.
        // Filtering on `date` first is a cheap comparison and leaves the helper's
        // own window as the authority.
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate))
            ?? calendar.startOfDay(for: referenceDate)
        let recent = logs.filter { $0.date >= windowStart }
        let stats = DashboardViewModel.sevenDayStats(from: recent.map { DailyLogSnapshot($0) }, referenceDate: referenceDate)
        if stats.loggedDays > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("7-Day Snapshot")
                    .font(.headline)
                HStack(spacing: 10) {
                    statPill(label: "Mood", value: rounded(stats.averageMood), color: CadenceColor.moodBlue, suffix: "/ 5")
                    statPill(label: "Energy", value: rounded(stats.averageEnergy), color: CadenceColor.energyOrange)
                    statPill(label: "Sleep", value: oneDecimal(stats.averageSleepHours), color: CadenceColor.sleepPurple, suffix: "hrs")
                    statPill(label: "Logs", value: "\(stats.loggedDays)", color: CadenceColor.successGreen, suffix: "/ 7")
                }
            }
        }
    }

    // An em dash, not a zero: a week with no mood entered has no average, and
    // printing "0" would be inventing one.
    private func rounded(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private func oneDecimal(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
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

    // Gated purely on `logs.isEmpty`, so `vm.mascotPose` here is always
    // either `.welcoming` (no active flare) or `.cozy` (an active flare
    // outranks the empty-history default — see MascotPoseEngine's priority
    // order) — never `.soaking`/`.resting`, which both require history or a
    // streak. The headline must track which of those two it actually is:
    // showing the comfort pose next to first-time-user copy reads as a
    // mismatch for someone logging a flare during a hard stretch.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(vm.mascotPose.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(CadenceColor.accent)
                .accessibilityHidden(true)
            if vm.mascotPose == .cozy {
                Text("Tracking can help through a hard stretch")
                    .font(.subheadline.weight(.medium))
            } else {
                Text("Log your first day to see insights")
                    .font(.subheadline.weight(.medium))
            }
            Text("Tap Today's Log above to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cadenceCard()
    }

    // Built with String(localized:) rather than returned as bare literals: a
    // plain String reaches Text/.accessibilityLabel through the non-localizing
    // StringProtocol overload, so these never entered the catalog at all.
    private var todayCardAccessibilityLabel: String {
        if let log = vm.todayLog {
            return log.isComplete
                ? String(localized: "Today's Log, completed")
                : String(localized: "Today's Log, in progress")
        }
        return String(localized: "Today's Log, not started. Takes about 90 seconds.")
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        case 17..<21: return String(localized: "Good evening")
        default:      return String(localized: "Good night")
        }
    }
}
