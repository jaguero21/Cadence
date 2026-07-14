import SwiftUI
import SwiftData
import PDFKit

struct ExportView: View {
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \Flare.startDate, order: .reverse) private var flares: [Flare]
    @Query(sort: \CustomTracker.sortOrder) private var customTrackers: [CustomTracker]
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @AppStorage(UserDefaultsKey.lastVisitDate) private var lastVisitInterval: Double = 0
    @State private var reportType: ReportType = .doctor
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var isGenerating = false
    @State private var shareItem: URL?
    @State private var showingShare = false
    @State private var previewItem: ReportPreviewItem?
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

                appointmentSection

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

                        Button {
                            exportCSV()
                        } label: {
                            Label("Export Spreadsheet (CSV)", systemImage: "tablecells")
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
            // PDFs open in a preview first — check the report before handing
            // it to anyone; sharing happens from the preview's toolbar.
            .sheet(item: $previewItem) { item in
                ReportPreviewSheet(url: item.url)
            }
            .onDisappear { generationTask?.cancel() }
        }
    }

    private var lastVisitDate: Date? {
        lastVisitInterval > 0 ? Date(timeIntervalSinceReferenceDate: lastVisitInterval) : nil
    }

    @ViewBuilder
    private var appointmentSection: some View {
        Section {
            if let last = lastVisitDate {
                HStack {
                    Text("Last visit")
                    Spacer()
                    Text(last.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                Button("Set range to since last visit") {
                    startDate = last
                    endDate = .now
                }
            }
            Button("Mark today as last visit") {
                lastVisitInterval = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
            }
        } header: {
            Text("Appointment")
        } footer: {
            Text("Mark a visit, then quickly scope your next report to everything since then.")
        }
    }

    @ViewBuilder
    private var includes: some View {
        switch reportType {
        case .doctor:
            Label("Trend charts",             systemImage: "checkmark")
            Label("Symptom frequency & severity", systemImage: "checkmark")
            Label("Medication list",          systemImage: "checkmark")
            Label("Pattern flags",            systemImage: "checkmark")
            Label("HealthKit objective data", systemImage: "checkmark")
        case .personal:
            Label("Trend charts",             systemImage: "checkmark")
            Label("Weekly reviews",           systemImage: "checkmark")
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

    private func exportCSV() {
        let logSnapshots = logs
            .filter { $0.date >= startDate && $0.date <= endDate }
            .map(DailyLogSnapshot.init)
        if let url = CSVBuilder.build(logs: logSnapshots) {
            shareItem = url
            showingShare = true
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
        // Include any medication whose course overlaps the export range.
        let medicationSnapshots = medications
            .filter { $0.startDate <= endDate && ($0.endDate ?? .distantFuture) >= startDate }
            .map(MedicationSnapshot.init)
        // Include any flare overlapping the export range.
        let flareSnapshots = flares
            .filter { $0.startDate <= endDate && ($0.endDate ?? .distantFuture) >= startDate }
            .map(FlareSnapshot.init)
        let trackerSnapshots = customTrackers.map(CustomTrackerSnapshot.init)

        generationTask?.cancel()
        generationTask = Task.detached {
            let url = await PDFBuilder.build(
                type: reportType,
                logs: logSnapshots,
                reviews: reviewSnapshots,
                medications: medicationSnapshots,
                flares: flareSnapshots,
                customTrackers: trackerSnapshots
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isGenerating = false
                previewItem = url.map(ReportPreviewItem.init)
            }
        }
    }
}

// A generated PDF, wrapped for sheet(item:) presentation.
struct ReportPreviewItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// Full-page preview of the generated report so the user can read what they're
// about to hand over; the share action lives in its toolbar.
struct ReportPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFDocumentView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Report Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

// PDFKit-backed page view; PDFView has no SwiftUI equivalent.
private struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
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
