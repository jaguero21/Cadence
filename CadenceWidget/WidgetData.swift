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

    struct Summary: Codable, Equatable {
        var date: Date          // start of day the summary describes
        var loggedToday: Bool
        var streak: Int
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
            return Summary(date: now, loggedToday: false, streak: 0)
        }
        if cal.isDate(stored.date, inSameDayAs: now) { return stored }
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let streak = cal.isDate(stored.date, inSameDayAs: yesterday) ? stored.streak : 0
        return Summary(date: now, loggedToday: false, streak: streak)
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

    static func stashPendingQuickLog(mood: Int, date: Date = .now, defaults: UserDefaults? = nil) {
        let store = defaults ?? self.store
        var pending = readPending(from: store)
        pending.append(PendingQuickLog(mood: mood, date: date))
        // Bound the queue; the oldest taps are the least meaningful to keep.
        if pending.count > maxPending { pending.removeFirst(pending.count - maxPending) }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        store?.set(data, forKey: pendingKey)
    }

    // Read-and-clear: the caller owns the returned entries.
    static func consumePendingQuickLogs(defaults: UserDefaults? = nil) -> [PendingQuickLog] {
        let store = defaults ?? self.store
        let pending = readPending(from: store)
        if !pending.isEmpty { store?.removeObject(forKey: pendingKey) }
        return pending
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
}
