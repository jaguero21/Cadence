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
        Label("Trend charts",                 systemImage: "checkmark")
        Label("Symptom frequency & severity", systemImage: "checkmark")
        Label("Medication list",              systemImage: "checkmark")
        Label("Pattern flags",                systemImage: "checkmark")
        Label("HealthKit objective data",     systemImage: "checkmark")
        Label("Weekly reflections",           systemImage: "checkmark")
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

    // The From picker's date keeps a time-of-day (it defaults to now-1mo and
    // DatePicker preserves time components), while log days are midnight-
    // normalized — every range filter must compare against midnight or the
    // range's first day silently drops out.
    private var rangeStart: Date { Calendar.current.startOfDay(for: startDate) }

    // CloudKit sync can leave two complete DailyLog rows for the same day
    // (DailyLog has no @Attribute(.unique), per this app's CloudKit
    // constraints) — collapse to one log per day before export so a synced
    // duplicate can't inflate a PDF's "N of M days logged" count or emit a
    // duplicate CSV row for that date. Prefers the complete log when only one
    // of the pair is; otherwise keeps whichever the store returns first.
    private func dedupedByDay(_ source: [DailyLog]) -> [DailyLog] {
        var seenDays: Set<Date> = []
        var result: [DailyLog] = []
        for log in source.sorted(by: { $0.isComplete && !$1.isComplete }) {
            if seenDays.insert(Calendar.current.startOfDay(for: log.date)).inserted {
                result.append(log)
            }
        }
        return result
    }

    private func exportCSV() {
        let logSnapshots = dedupedByDay(logs.filter { $0.date >= rangeStart && $0.date <= endDate })
            .map(DailyLogSnapshot.init)
        let trackerSnapshots = customTrackers.map(CustomTrackerSnapshot.init)
        if let url = CSVBuilder.build(logs: logSnapshots, trackers: trackerSnapshots) {
            shareItem = url
            showingShare = true
        }
    }

    private func generate() {
        isGenerating = true
        let logSnapshots = dedupedByDay(logs.filter { $0.date >= rangeStart && $0.date <= endDate })
            .map(DailyLogSnapshot.init)
        let reviewSnapshots = reviews
            .filter { $0.weekStartDate <= endDate && $0.weekEndDate >= rangeStart }
            .map(WeeklyReviewSnapshot.init)
        // Include any medication whose course overlaps the export range.
        let medicationSnapshots = medications
            .filter { $0.startDate <= endDate && ($0.endDate ?? .distantFuture) >= rangeStart }
            .map(MedicationSnapshot.init)
        // Include any flare overlapping the export range.
        let flareSnapshots = flares
            .filter { $0.startDate <= endDate && ($0.endDate ?? .distantFuture) >= rangeStart }
            .map(FlareSnapshot.init)
        let trackerSnapshots = customTrackers.map(CustomTrackerSnapshot.init)

        generationTask?.cancel()
        generationTask = Task.detached {
            let url = await PDFBuilder.build(
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
