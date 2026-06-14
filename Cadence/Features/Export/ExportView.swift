import SwiftUI
import SwiftData

struct ExportView: View {
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @State private var reportType: ReportType = .doctor
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var isGenerating = false
    @State private var shareItem: URL?
    @State private var showingShare = false
    @State private var generationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Report Type") {
                    Picker("Type", selection: $reportType) {
                        ForEach(ReportType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Date Range") {
                    DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                    DatePicker("To",   selection: $endDate,   in: startDate..., displayedComponents: .date)
                }

                Section("Includes") {
                    includes
                }

                Section {
                    if store.isPro {
                        Button {
                            generate()
                        } label: {
                            HStack {
                                Label("Generate PDF", systemImage: "doc.richtext.fill")
                                Spacer()
                                if isGenerating {
                                    ProgressView().progressViewStyle(.circular)
                                }
                            }
                        }
                        .disabled(isGenerating)
                    } else {
                        proPrompt
                    }
                }
            }
            .navigationTitle("Export")
            .sheet(isPresented: $showingShare) {
                if let url = shareItem {
                    ShareSheet(items: [url])
                }
            }
            .onDisappear { generationTask?.cancel() }
        }
    }

    @ViewBuilder
    private var includes: some View {
        switch reportType {
        case .doctor:
            Label("Symptom frequency table", systemImage: "checkmark")
            Label("Medication list",          systemImage: "checkmark")
            Label("Pattern flags",            systemImage: "checkmark")
            Label("HealthKit objective data", systemImage: "checkmark")
        case .personal:
            Label("Weekly reviews",           systemImage: "checkmark")
            Label("Trend charts",             systemImage: "checkmark")
            Label("Win/miss/intention history",systemImage: "checkmark")
        }
    }

    private var proPrompt: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(CadenceColor.sleepPurple)
            Text("PDF export is a Pro feature.")
            Spacer()
            Button("Upgrade") {
                appState.showingProPaywall = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func generate() {
        isGenerating = true
        let logSnapshots = logs
            .filter { $0.date >= startDate && $0.date <= endDate }
            .map(DailyLogSnapshot.init)
        let reviewSnapshots = reviews
            .filter { $0.weekStartDate <= endDate && $0.weekEndDate >= startDate }
            .map(WeeklyReviewSnapshot.init)

        generationTask?.cancel()
        generationTask = Task.detached {
            let url = await PDFBuilder.build(
                type: reportType,
                logs: logSnapshots,
                reviews: reviewSnapshots
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isGenerating = false
                shareItem = url
                showingShare = url != nil
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
