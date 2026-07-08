import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Settings section: live iCloud sync status plus JSON backup/restore.
// Backup/restore is intentionally free (not Pro-gated) — users always own
// their data. Photo and voice binaries live outside SwiftData and are not
// part of the backup document.
struct SyncBackupSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var syncMonitor = CloudSyncMonitor.shared

    @Query(sort: \DailyLog.date) private var logs: [DailyLog]
    @Query(sort: \WeeklyReview.weekStartDate) private var reviews: [WeeklyReview]
    @Query(sort: \SymptomTag.sortOrder) private var tags: [SymptomTag]
    @Query(sort: \Medication.startDate) private var medications: [Medication]
    @Query(sort: \Flare.startDate) private var flares: [Flare]
    @Query(sort: \CustomTracker.sortOrder) private var trackers: [CustomTracker]

    @State private var backupURL: URL?
    @State private var showingBackupShare = false
    @State private var showingImporter = false
    @State private var resultMessage: String?
    @State private var showingResult = false

    var body: some View {
        Section {
            syncStatusRow

            Button {
                exportBackup()
            } label: {
                Label("Back Up Data", systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(CadenceColor.accent)

            Button {
                showingImporter = true
            } label: {
                Label("Restore from Backup", systemImage: "square.and.arrow.down")
            }
            .foregroundStyle(CadenceColor.accent)
        } header: {
            Label("iCloud & Backup", systemImage: "icloud.fill")
        } footer: {
            Text("Backups include logs, reviews, medications, flares, trackers, and symptoms as a JSON file. Photos and voice notes aren't included. Restoring merges — nothing on this device is overwritten.")
        }
        .task { syncMonitor.start() }
        .sheet(isPresented: $showingBackupShare) {
            if let backupURL {
                ShareSheet(items: [backupURL])
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            restoreBackup(from: result)
        }
        .alert("Backup", isPresented: $showingResult) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var syncStatusRow: some View {
        HStack {
            Label("iCloud Sync", systemImage: syncStatusSymbol)
            Spacer()
            syncStatusText
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var syncStatusSymbol: String {
        switch syncMonitor.state {
        case .localOnly, .noAccount: return "icloud.slash"
        case .waiting, .syncing:     return "arrow.triangle.2.circlepath.icloud"
        case .synced:                return "checkmark.icloud"
        case .error:                 return "exclamationmark.icloud"
        }
    }

    @ViewBuilder
    private var syncStatusText: some View {
        switch syncMonitor.state {
        case .localOnly:
            Text("Off — local storage")
        case .noAccount:
            Text("No iCloud account")
        case .waiting:
            Text("Waiting…")
        case .syncing:
            Text("Syncing…")
        case .synced(let date):
            Text("Synced \(date.formatted(.relative(presentation: .named)))")
        case .error:
            Text("Sync problem")
                .foregroundStyle(CadenceColor.stressRed)
        }
    }

    private func exportBackup() {
        let document = BackupService.document(
            logs: logs, reviews: reviews, tags: tags,
            medications: medications, flares: flares, trackers: trackers
        )
        do {
            backupURL = try BackupService.writeBackupFile(document)
            showingBackupShare = true
        } catch {
            resultMessage = String(localized: "Backup failed: \(error.localizedDescription)")
            showingResult = true
        }
    }

    private func restoreBackup(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let document = try BackupService.decode(try Data(contentsOf: url))
            let summary = try BackupService.restore(document, context: modelContext)
            // Restored logs can change today's status/streak on the widget.
            DashboardViewModel.publishWidgetSummary(logs: logs)
            if summary.insertedTotal == 0 {
                resultMessage = String(localized: "Everything in that backup is already on this device.")
            } else {
                resultMessage = String(localized: "Restored \(summary.insertedTotal) record(s); skipped \(summary.skipped) already on this device.")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            resultMessage = String(localized: "Restore failed: \(error.localizedDescription)")
        }
        showingResult = true
    }
}
