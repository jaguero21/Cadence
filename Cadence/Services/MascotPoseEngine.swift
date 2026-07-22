import Foundation

// Resolves which mascot pose best matches the current moment, using the
// same "strongest signal wins" philosophy as PatternEngine (see
// PatternEngine.allInsights): an active flare or a real low-mood stretch
// always outranks a celebratory streak pose, which outranks the plain
// default. Pure and snapshot-based (never a @Model across actors, same
// rule PatternEngine follows) — only the app computes a pose with this
// function; the widget extension has no SwiftData access and instead
// reads the pose the app already computed and published to
// WidgetData.Summary.mascotPose (see that type's doc comment).
enum MascotPoseEngine {
    static func pose(
        for logs: [DailyLogSnapshot],
        activeFlare: FlareSnapshot?,
        streakDays: Int
    ) -> WidgetData.MascotPose {
        let isFlareActive = activeFlare.map { $0.endDate == nil } ?? false
        if isFlareActive || hasLowMoodTrend(logs) {
            return .cozy
        }
        if streakDays >= MascotThreshold.streakDaysForSoaking {
            return .soaking
        }
        guard !logs.isEmpty else {
            return .welcoming
        }
        return .resting
    }

    // The most recent `lowMoodTrendDays` logged days (by date, regardless
    // of gaps between them — a user who skipped a day mid-slump should
    // still get the comforting pose) are all below the mean mood of every
    // OLDER logged day (the baseline). Comparing against a baseline that
    // excludes the recent window itself avoids two problems: at exactly
    // `lowMoodTrendDays` total logs the recent window would equal the
    // whole array, making "all below their own mean" mathematically
    // impossible regardless of mood values; and even with more logs,
    // including the recent (low) days in their own baseline would bias
    // that baseline downward, making the trend harder to detect than it
    // should be. Requires at least one older day to compare against.
    private static func hasLowMoodTrend(_ logs: [DailyLogSnapshot]) -> Bool {
        let sorted = logs.sorted { $0.date > $1.date }
        let recent = sorted.prefix(MascotThreshold.lowMoodTrendDays)
        let baseline = sorted.dropFirst(MascotThreshold.lowMoodTrendDays)
        guard recent.count == MascotThreshold.lowMoodTrendDays, !baseline.isEmpty else { return false }
        let baselineMeanMood = Double(baseline.map(\.mood).reduce(0, +)) / Double(baseline.count)
        return recent.allSatisfy { Double($0.mood) < baselineMeanMood }
    }
}
