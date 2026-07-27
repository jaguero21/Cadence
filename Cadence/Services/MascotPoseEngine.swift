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
        streakDays: Int,
        referenceDate: Date = .now
    ) -> WidgetData.MascotPose {
        // Bound the logs we reason about to the canonical insight window
        // (PatternThreshold.insightWindowDays) before deciding anything —
        // the same window every other cross-surface pattern computation
        // uses (see InsightRecorder). Callers hand us wildly different
        // breadths: the Dashboard passes its own 90-day @Query slice, while
        // the widget-publish paths pass the whole unbounded DailyLog table.
        // Both hasLowMoodTrend's baseline (mean of every OLDER day) and the
        // welcoming-vs-resting `isEmpty` check below shift with how many
        // older days are included, so without this the Dashboard's own pose
        // and the pose published to the widget could disagree for the same
        // day. The cutoff mirrors DashboardView's @Query exactly
        // (startOfDay(referenceDate) − window), so a caller's 90-day slice
        // and an unbounded caller's table window down to the identical set.
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -PatternThreshold.insightWindowDays,
            to: Calendar.current.startOfDay(for: referenceDate)
        ) ?? .distantPast
        let windowed = logs.filter { $0.date >= cutoff }

        let isFlareActive = activeFlare.map { $0.endDate == nil } ?? false
        if isFlareActive || hasLowMoodTrend(windowed) {
            return .cozy
        }
        if streakDays >= MascotThreshold.streakDaysForSoaking {
            return .soaking
        }
        guard !windowed.isEmpty else {
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
        // Collapse to one mood per calendar day before splitting recent vs
        // baseline — CloudKit sync can leave two logs for the same day (no
        // @Attribute(.unique) on DailyLog; DashboardViewModel.computeStreak
        // dedupes for the same reason). Without this, a duplicate today
        // would fill the recent window with two records for one calendar
        // day, so "the most recent 3 days" would silently span only 2 real
        // days. Same-day records are averaged, so a merge conflict between
        // two entries for one day resolves to a neutral midpoint.
        let dailyMoods = Dictionary(grouping: logs) { Calendar.current.startOfDay(for: $0.date) }
            .mapValues { sameDay in Double(sameDay.map(\.mood).reduce(0, +)) / Double(sameDay.count) }
            .sorted { $0.key > $1.key }
            .map(\.value)
        let recent = dailyMoods.prefix(MascotThreshold.lowMoodTrendDays)
        let baseline = dailyMoods.dropFirst(MascotThreshold.lowMoodTrendDays)
        guard recent.count == MascotThreshold.lowMoodTrendDays, !baseline.isEmpty else { return false }
        let baselineMeanMood = baseline.reduce(0, +) / Double(baseline.count)
        return recent.allSatisfy { $0 < baselineMeanMood }
    }
}
