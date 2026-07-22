import Foundation

// Resolves which mascot pose best matches the current moment, using the
// same "strongest signal wins" philosophy as PatternEngine (see
// PatternEngine.allInsights): an active flare or a real low-mood stretch
// always outranks a celebratory streak pose, which outranks the plain
// default. Pure and snapshot-based (never a @Model across actors, same
// rule PatternEngine follows) so every caller — the app now, the widget
// once it's wired — computes the identical pose from the identical inputs.
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
    // still get the comforting pose) are all below the average mood across
    // every provided log. Requires at least that many logs to evaluate at
    // all, so a single low day early on can't trigger it.
    private static func hasLowMoodTrend(_ logs: [DailyLogSnapshot]) -> Bool {
        guard logs.count >= MascotThreshold.lowMoodTrendDays else { return false }
        let overallMeanMood = Double(logs.map(\.mood).reduce(0, +)) / Double(logs.count)
        let recent = logs.sorted { $0.date > $1.date }.prefix(MascotThreshold.lowMoodTrendDays)
        return recent.allSatisfy { Double($0.mood) < overallMeanMood }
    }
}
