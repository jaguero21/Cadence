import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query private var logs: [DailyLog]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \Flare.startDate, order: .reverse) private var flares: [Flare]
    @Query(sort: \CustomTracker.sortOrder) private var customTrackers: [CustomTracker]
    @State private var vm = InsightsViewModel()
    // Day opened by scrubbing a chart and tapping "View day".
    @State private var detailLog: DailyLog?

    // referenceDate anchors the query window so it refreshes in place at a
    // midnight rollover rather than via a full view rebuild. The cutoff is 2×
    // the largest chart window (180 days) — the previous-period comparison for
    // the 90D range needs logs 90–180 days back; insight computation still uses
    // the canonical 90-day slice (see insightLogs).
    init(referenceDate: Date = .now) {
        let day = Calendar.current.startOfDay(for: referenceDate)
        let cutoff = Calendar.current.date(byAdding: .day, value: -2 * PatternThreshold.insightWindowDays, to: day) ?? .distantPast
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= cutoff }, sort: \DailyLog.date, order: .reverse)
    }
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CadenceLayout.sectionSpacing) {
                    rangeSelector
                    chartsSection
                    if store.isPro {
                        insightsSection
                    } else {
                        proGate
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(CadenceColor.background)
            .navigationTitle("Insights")
            .toolbar {
                if store.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            InsightHistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("Insight history")
                    }
                }
            }
            .sheet(item: $detailLog) { log in
                LogDetailView(log: log)
            }
            .onAppear { refreshAndRecord() }
            .onChange(of: logs) { _, _ in refreshAndRecord() }
            .onChange(of: medications) { _, _ in refreshAndRecord() }
            .onChange(of: flares) { _, _ in refreshAndRecord() }
            .onChange(of: customTrackers) { _, _ in refreshAndRecord() }
        }
    }

    // Insights compute over the canonical window (the @Query is wider — 180
    // days — for chart comparisons), keeping this surface consistent with the
    // foreground notification check in ContentView.
    private var insightLogs: [DailyLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -PatternThreshold.insightWindowDays, to: .now) ?? .distantPast
        return logs.filter { $0.date >= cutoff }
    }

    private func openDay(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        detailLog = logs.first { Calendar.current.startOfDay(for: $0.date) == day }
    }

    private func refreshAndRecord() {
        vm.refresh(logs: insightLogs, medications: medications, flares: flares, trackers: customTrackers)
        if store.isPro {
            InsightRecorder.record(vm.insights, context: modelContext)
        }
    }

    private var rangeSelector: some View {
        @Bindable var vm = vm
        let availableRanges = InsightsViewModel.ChartRange.allCases.filter {
            $0 != .ninetyDay || store.isPro
        }
        return Picker("Range", selection: $vm.chartRange) {
            ForEach(availableRanges, id: \.self) { range in
                Text(range.rawValue).tag(range)
                    .accessibilityLabel(range.voiceLabel)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: store.isPro) { _, isPro in
            if !isPro && vm.chartRange == .ninetyDay {
                vm.chartRange = .thirtyDay
            }
        }
    }

    @ViewBuilder
    private var chartsSection: some View {
        let filtered = filteredLogs
        let previous = previousLogs
        if filtered.isEmpty {
            // One friendly card instead of a wall of per-chart "No entries"
            // cards when the selected range has no logs at all. The per-chart
            // message still handles the mixed case (logs exist, but a custom
            // tracker wasn't recorded).
            chartsEmptyState
        } else {
            VStack(spacing: 16) {
                ForEach(ChartMetric.allCases, id: \.self) { metric in
                    TrendChartView(logs: filtered, series: metric.series, range: vm.chartRange,
                                   previousLogs: previous, onOpenDay: openDay)
                }
                // Custom trackers chart with the same average/comparison treatment;
                // days without an entry are skipped, not drawn as zero.
                ForEach(customTrackers) { tracker in
                    TrendChartView(logs: filtered, series: .custom(tracker), range: vm.chartRange,
                                   previousLogs: previous, onOpenDay: openDay)
                }
                // Workout minutes from HealthKit — only once any day in the
                // window actually carries one (no empty chart for users
                // without Health access or workouts).
                if let longest = filtered.compactMap(\.hkWorkoutMinutes).max() {
                    TrendChartView(logs: filtered, series: .workoutMinutes(longestSession: longest),
                                   range: vm.chartRange, previousLogs: previous, onOpenDay: openDay)
                }
            }
        }
    }

    private var chartsEmptyState: some View {
        // System empty-state component (matches History, Flares, Medications…)
        // rather than a hand-rolled card.
        ContentUnavailableView {
            Label("Nothing logged in the last \(vm.chartRange.days) days", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Complete a few daily logs and your trends will appear here — mood, energy, sleep, and more.")
        }
        .cadenceCard()
    }

    private var filteredLogs: [DailyLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -vm.chartRange.days, to: .now) ?? .now
        return logs.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    // The equal-length window immediately before the current one, for comparison.
    private var previousLogs: [DailyLog] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: -vm.chartRange.days, to: .now) ?? .now
        let start = cal.date(byAdding: .day, value: -2 * vm.chartRange.days, to: .now) ?? .now
        return logs.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pattern Insights")
                .font(.headline)
            if vm.insights.isEmpty {
                Text("Log at least \(PatternThreshold.minimumLogs) days to start seeing patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cadenceCard()
            } else {
                ForEach(vm.insights) { insight in
                    CorrelationCardView(insight: insight)
                }
                Text("These are observations from your own logs, shown to build awareness of how you feel day to day — not medical advice or a diagnosis.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var proGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Pattern Insights — Pro")
                .font(.headline)
            Text("Unlock correlation detection, trend annotations, and the full 90-day view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock Pro") {
                appState.showingProPaywall = true
            }
            .buttonStyle(.borderedProminent)
        }
        .cadenceCard()
    }
}

struct CorrelationCardView: View {
    let insight: InsightCard

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: insight.icon)
                .font(.title2)
                .foregroundStyle(insight.color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(.subheadline.bold())
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Confidence")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ProgressView(value: insight.confidence)
                        .tint(insight.color)
                        .frame(width: 80)
                    Text("\(Int(insight.confidence * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Text(insight.category.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(insight.color.opacity(0.15), in: Capsule())
                .foregroundStyle(insight.color)
        }
        .cadenceCard()
    }
}
