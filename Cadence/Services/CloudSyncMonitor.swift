import Foundation
import CloudKit
import CoreData
import Observation
import OSLog

// Surfaces iCloud sync health in Settings. SwiftData's CloudKit mirroring is
// built on NSPersistentCloudKitContainer, which posts eventChangedNotification
// for every setup/import/export pass — we fold those events (plus the CloudKit
// account status) into a single user-facing state. Purely observational: it
// never drives sync, so a wrong state here can't corrupt anything.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    enum SyncState: Equatable {
        case localOnly            // store isn't CloudKit-backed (entitlement absent / init failed)
        case noAccount            // device has no iCloud account signed in
        case waiting              // cloud-backed, no sync event observed yet this launch
        case syncing              // an import/export/setup pass is in flight
        case synced(Date)         // last successful pass finished at this time
        case error(String)        // last pass failed
    }

    private(set) var state: SyncState = .waiting
    private var observer: (any NSObjectProtocol)?
    // Called after a remote import settles. Injected by CadenceApp so this
    // class stays about sync and never learns what a widget or an insight is.
    // @ObservationIgnored: these are wiring, not state any view renders, and
    // an @Observable class otherwise tracks every stored property.
    @ObservationIgnored var onRemoteImport: (() -> Void)?
    @ObservationIgnored var coalesceInterval: Duration = .seconds(SyncThreshold.remoteImportCoalesceSeconds)
    @ObservationIgnored private var reactTask: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.carpecadence", category: "CloudSync")

    // Pure state fold, unit-tested in isolation. `finished` is whether the
    // event carries an endDate (in-flight events don't).
    static func stateAfterEvent(
        finished: Bool,
        succeeded: Bool,
        endDate: Date?,
        errorDescription: String?,
        previous: SyncState
    ) -> SyncState {
        guard finished else { return .syncing }
        if succeeded { return .synced(endDate ?? .now) }
        return .error(errorDescription ?? String(localized: "Sync failed"))
    }

    // Which events deserve a refresh, kept pure and separate from the display
    // fold above. An export is this device's own write — every save path
    // already republishes at the save site — and setup moves no data. An
    // unfinished pass has nothing to show yet, and a failed one has nothing
    // true to show.
    static func shouldReactTo(isImport: Bool, finished: Bool, succeeded: Bool) -> Bool {
        isImport && finished && succeeded
    }

    // Cancel-and-restart around a sleep: the cancellation is what collapses a
    // burst into one call. DashboardView.scheduleRefresh uses the same handle
    // pattern with no sleep, which only coalesces triggers landing in the same
    // runloop tick — enough for @Query publishers firing together, but CloudKit
    // import events arrive spread over seconds, so this one has to wait.
    private func scheduleRemoteImportReaction() {
        reactTask?.cancel()
        let interval = coalesceInterval
        reactTask = Task { [self] in
            try? await Task.sleep(for: interval)
            // A cancelled sleep throws, which `try?` swallows — so re-check
            // rather than treating cancellation as "time elapsed".
            guard !Task.isCancelled else { return }
            onRemoteImport?()
        }
    }

    // Default-arg isolation: resolve the flag inside the body (a @MainActor
    // default argument would be evaluated in a nonisolated context).
    //
    // The observer registration is still guarded to run once (NotificationCenter
    // would otherwise stack a duplicate closure on every call), but the account
    // probe below is NOT — it runs on every call. `start()` used to be called
    // only when the user opened Settings, so probing there was also the only
    // time the row could go stale. Now CadenceApp's launch `.task` calls
    // `start()` first, so the old `guard observer == nil else { return }`
    // covering the whole function turned SyncBackupSection's own
    // `.task { syncMonitor.start() }` into a silent no-op: sign out of
    // iCloud, launch (state settles on .noAccount), sign back in from
    // Settings.app, return to Cadence's Settings — the row was stuck reading
    // "No iCloud account" for the rest of the session because nothing ever
    // probed again.
    func start(cloudBacked: Bool? = nil) {
        guard cloudBacked ?? CadenceApp.usingCloudKitStore else {
            state = .localOnly
            return
        }

        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: nil
            ) { note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { return }
                // Extract plain Sendable values before hopping actors — Event isn't Sendable.
                let finished = event.endDate != nil
                let succeeded = event.succeeded
                let endDate = event.endDate
                let errorDescription = event.error?.localizedDescription
                let isImport = event.type == .import
                Task { @MainActor in
                    CloudSyncMonitor.shared.apply(
                        isImport: isImport,
                        finished: finished,
                        succeeded: succeeded,
                        endDate: endDate,
                        errorDescription: errorDescription
                    )
                }
            }
        }

        Task { await refreshAccountStatus() }
    }

    func apply(isImport: Bool, finished: Bool, succeeded: Bool, endDate: Date?, errorDescription: String?) {
        // Once events are flowing, they're the truth — even if the account
        // check hasn't come back yet.
        state = Self.stateAfterEvent(
            finished: finished,
            succeeded: succeeded,
            endDate: endDate,
            errorDescription: errorDescription,
            previous: state
        )
        if case .error(let message) = state {
            Self.log.error("CloudKit sync event failed: \(message, privacy: .public)")
        }
        if Self.shouldReactTo(isImport: isImport, finished: finished, succeeded: succeeded) {
            scheduleRemoteImportReaction()
        }
    }

    private func refreshAccountStatus() async {
        guard let status = try? await CKContainer.default().accountStatus() else { return }
        // Only downgrade to noAccount while we're still waiting — a sync event
        // that already arrived is stronger evidence than the account probe.
        if status != .available, state == .waiting {
            state = .noAccount
        }
        // Recovery direction: the account came back after we'd already
        // stranded the row on .noAccount (signed back into iCloud in
        // Settings.app, then returned to Cadence). Now that start() re-probes
        // on every call instead of only once at launch, this branch is what
        // actually gets hit — go back to .waiting for the first sync event,
        // same as a fresh launch with an account already signed in. A sync
        // event still outranks the probe in both directions: don't overwrite
        // .synced/.syncing/.error, only the .noAccount holding pattern.
        if status == .available, state == .noAccount {
            state = .waiting
        }
    }
}
