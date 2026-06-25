import Foundation

// Lightweight app↔widget bridge over the shared App Group. The app writes a
// small summary after refreshing; the widget reads it in its timeline. This
// avoids sharing the whole SwiftData stack with the extension.
enum WidgetData {
    static let appGroup = "group.com.carpecadence.app"
    private static let key = "todaySummary"

    struct Summary: Codable {
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
}
