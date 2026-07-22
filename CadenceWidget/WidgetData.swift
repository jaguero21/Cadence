import Darwin
import Foundation

// Lightweight app↔widget bridge over the shared App Group. The app writes a
// small summary after refreshing; the widget reads it in its timeline. This
// avoids sharing the whole SwiftData stack with the extension.
enum WidgetData {
    static let appGroup = "group.com.carpecadence.app"
    // The widget's kind identifier — shared so targeted timeline reloads and
    // the widget configuration can't drift apart.
    static let widgetKind = "CadenceWidget"
    private static let key = "todaySummary"

    // Ambient companion pose, computed by MascotPoseEngine
    // (Cadence/Services/MascotPoseEngine.swift) on the app side and
    // published here so the widget extension — which has no SwiftData
    // access — can render the same pose without recomputing it. Defined
    // here rather than in Cadence/Models/ because this file is already
    // compiled into both the Cadence and CadenceWidgetExtension targets,
    // and Summary (below) needs this type to compile in both.
    enum MascotPose: String, CaseIterable, Codable {
        case welcoming, resting, soaking, cozy, sleepy
    }

    struct Summary: Codable, Equatable {
        var date: Date          // start of day the summary describes
        var loggedToday: Bool
        var streak: Int
        var mascotPose: MascotPose
    }

    private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func write(_ summary: Summary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        store?.set(data, forKey: key)
    }

    static func read() -> Summary? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }

    // Resolves a stored summary against the current moment. The stored value
    // describes the day it was written, so after midnight it must be
    // reinterpreted rather than displayed as-is: "logged today" only holds for
    // a summary from today, and a streak survives exactly one day past its
    // summary (yesterday's streak is alive until tonight); older is broken.
    // Pure and `now`-injected so it's unit-testable from the app's test bundle.
    static func resolved(_ stored: Summary?, now: Date = .now) -> Summary {
        let cal = Calendar.current
        guard let stored else {
            return Summary(date: now, loggedToday: false, streak: 0, mascotPose: .welcoming)
        }
        if cal.isDate(stored.date, inSameDayAs: now) { return stored }
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let streak = cal.isDate(stored.date, inSameDayAs: yesterday) ? stored.streak : 0
        return Summary(date: now, loggedToday: false, streak: streak, mascotPose: stored.mascotPose)
    }

    // MARK: - Pending quick logs (widget → app)

    // A mood tapped on the widget. The widget can't open the app's SwiftData
    // store, so taps are stashed here (stamped with the day they were tapped)
    // and applied by the app on its next foregrounding via the same upsert seam
    // the watch uses — a tap left overnight lands on the day it was recorded.
    struct PendingQuickLog: Codable, Equatable {
        var mood: Int
        var date: Date

        // The wire shape PhoneConnectivityManager.applyQuickLog expects.
        var payload: [String: Any] {
            ["mood": mood, "date": date.timeIntervalSinceReferenceDate]
        }
    }

    private static let pendingKey = "pendingQuickLogs"
    private static let maxPending = 30

    // stash/consume/restore each do a read-modify-write on the same
    // UserDefaults key; UserDefaults is thread-safe per call but not
    // transactional across processes, so the app and the widget extension
    // can race on this key and silently stomp each other's write. An
    // advisory POSIX file lock on a marker file in the shared App Group
    // container serializes the three across processes. Falls back to
    // running unsynchronized if the container is unavailable (e.g. no App
    // Group entitlement in a test host) rather than dropping the tap.
    private static func withPendingLock<T>(_ body: () -> T) -> T {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return body()
        }
        let fd = open(containerURL.appendingPathComponent("pendingQuickLogs.lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return body() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return body()
    }

    // Cap at maxPending (oldest taps are least meaningful to keep), encode,
    // and persist — the common tail of every mutation to the pending queue.
    private static func persistPending(_ pending: [PendingQuickLog], to store: UserDefaults?) {
        var pending = pending
        if pending.count > maxPending { pending.removeFirst(pending.count - maxPending) }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        store?.set(data, forKey: pendingKey)
    }

    static func stashPendingQuickLog(mood: Int, date: Date = .now, defaults: UserDefaults? = nil) {
        let store = defaults ?? self.store
        withPendingLock {
            var pending = readPending(from: store)
            pending.append(PendingQuickLog(mood: mood, date: date))
            persistPending(pending, to: store)
        }
    }

    // Read-and-clear: the caller owns the returned entries.
    static func consumePendingQuickLogs(defaults: UserDefaults? = nil) -> [PendingQuickLog] {
        let store = defaults ?? self.store
        return withPendingLock {
            let pending = readPending(from: store)
            if !pending.isEmpty { store?.removeObject(forKey: pendingKey) }
            return pending
        }
    }

    // Re-stash entries consumed but never successfully applied (e.g. a
    // SwiftData save failure) so the next foreground retries them instead of
    // losing the tap. Merges back in recorded-date order, honoring the same
    // queue cap as a fresh stash.
    static func restorePendingQuickLogs(_ entries: [PendingQuickLog], defaults: UserDefaults? = nil) {
        guard !entries.isEmpty else { return }
        let store = defaults ?? self.store
        withPendingLock {
            let pending = (entries + readPending(from: store)).sorted { $0.date < $1.date }
            persistPending(pending, to: store)
        }
    }

    // The most recent pending mood for the given day, for the widget's own
    // display ("mood saved" state until the app picks the tap up).
    static func pendingMood(on day: Date, defaults: UserDefaults? = nil) -> Int? {
        let cal = Calendar.current
        return readPending(from: defaults ?? store).last { cal.isDate($0.date, inSameDayAs: day) }?.mood
    }

    private static func readPending(from store: UserDefaults?) -> [PendingQuickLog] {
        guard let data = store?.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingQuickLog].self, from: data)) ?? []
    }

    // MARK: - Check-in open request (Control Center → app)

    // The Control Center button can't run a mood picker, so it opens the app
    // instead; this flag tells the app "go straight to today's log" on the
    // foreground that follows.
    private static let checkInRequestKey = "pendingCheckInOpen"

    static func requestCheckInOpen(defaults: UserDefaults? = nil) {
        (defaults ?? store)?.set(true, forKey: checkInRequestKey)
    }

    // Read-and-clear.
    static func consumeCheckInOpenRequest(defaults: UserDefaults? = nil) -> Bool {
        let store = defaults ?? self.store
        let requested = store?.bool(forKey: checkInRequestKey) ?? false
        if requested { store?.removeObject(forKey: checkInRequestKey) }
        return requested
    }
}
