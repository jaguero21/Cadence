import Foundation

// The 1–5 mood scale shared by the phone app and the watch app (this file is a
// member of both targets, like WidgetData). The integer values travel over
// WatchConnectivity, so both sides must render the same face for the same
// stored value.
enum MoodScale {
    static let emojis = ["😢", "😕", "😐", "🙂", "😊"]

    static func emoji(for value: Int) -> String {
        guard (1...emojis.count).contains(value) else { return "😐" }
        return emojis[value - 1]
    }
}
