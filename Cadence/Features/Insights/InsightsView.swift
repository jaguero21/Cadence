import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @State private var vm = InsightsViewModel()
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState

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
            .onAppear { vm.refresh(logs: logs) }
            .onDisappear { vm.cancelRefresh() }
            .onChange(of: logs) { _, _ in vm.refresh(logs: logs) }
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

    private var chartsSection: some View {
        let filtered = filteredLogs
        return VStack(spacing: 16) {
            ForEach(ChartMetric.allCases, id: \.self) { metric in
                TrendChartView(logs: filtered, metric: metric, range: vm.chartRange)
            }
        }
    }

    private var filteredLogs: [DailyLog] {
        let cutoff: Date
        switch vm.chartRange {
        case .sevenDay:  cutoff = Calendar.current.date(byAdding: .day, value: -7,  to: .now) ?? .now
        case .thirtyDay: cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        case .ninetyDay: cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        }
        return logs.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
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
