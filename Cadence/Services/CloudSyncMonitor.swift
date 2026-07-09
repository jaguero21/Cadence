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

    // Default-arg isolation: resolve the flag inside the body (a @MainActor
    // default argument would be evaluated in a nonisolated context).
    func start(cloudBacked: Bool? = nil) {
        guard observer == nil else { return }
        guard cloudBacked ?? CadenceApp.usingCloudKitStore else {
            state = .localOnly
            return
        }

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
            Task { @MainActor in
                CloudSyncMonitor.shared.apply(
                    finished: finished,
                    succeeded: succeeded,
                    endDate: endDate,
                    errorDescription: errorDescription
                )
            }
        }

        Task { await refreshAccountStatus() }
    }

    private func apply(finished: Bool, succeeded: Bool, endDate: Date?, errorDescription: String?) {
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
    }

    private func refreshAccountStatus() async {
        guard let status = try? await CKContainer.default().accountStatus() else { return }
        // Only downgrade to noAccount while we're still waiting — a sync event
        // that already arrived is stronger evidence than the account probe.
        if status != .available, state == .waiting {
            state = .noAccount
        }
    }
}
