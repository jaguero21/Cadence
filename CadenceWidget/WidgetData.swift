import Foundation

// Lightweight app↔widget bridge over the shared App Group. The app writes a
// small summary after refreshing; the widget reads it in its timeline. This
// avoids sharing the whole SwiftData stack with the extension.
enum WidgetData {
    static let appGroup = "group.com.carpecadence.app"
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
}
