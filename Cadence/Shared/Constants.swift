import SwiftUI

enum CadenceColor {
    // System adaptive colors — already track light/dark automatically.
    static let background = Color(.systemGroupedBackground)
    static let cardBG     = Color(.secondarySystemGroupedBackground)

    // Brand colors — sourced from Assets.xcassets, which carries the light/dark
    // variants and lets us add high-contrast variants without code changes.
    static let accent       = Color("AccentColor")
    static let moodBlue     = Color("MoodBlue")
    static let energyOrange = Color("EnergyOrange")
    static let sleepPurple  = Color("SleepPurple")
    static let stressRed    = Color("StressRed")
    static let successGreen = Color("SuccessGreen")
}

enum CadenceLayout {
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    // Widest a single card column may grow (iPad / landscape); see
    // View.readableColumn(). Insights runs wider to fit charts two-up.
    static let readableColumnWidth: CGFloat = 640
    static let insightsColumnWidth: CGFloat = 1000
}

enum CadenceAnimation {
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.75)
    static let smooth = Animation.easeInOut(duration: 0.25)
}

enum StoreKitID {
    static let proOneTime = "com.carpecadence.pro.lifetime"
    static let proMonthly = "com.carpecadence.pro.monthly"
}

enum UserDefaultsKey {
    static let onboarded            = "cadence.onboarded"
    static let symptomTagsSeeded    = "cadence.symptomTagsSeeded"
    static let dailyReminderHour    = "dailyReminderHour"
    static let dailyReminderMinute  = "dailyReminderMinute"
    static let weeklyReminderEnabled = "weeklyReminderEnabled"
    static let lastVisitDate          = "lastVisitDate"   // timeIntervalSinceReferenceDate; 0 = unset
    static let lastInsightCheckDay    = "lastInsightCheckDay"   // startOfDay interval; foreground insight check runs once per day
}

enum PatternThreshold {
    // Minimum data requirements before running any pattern
    static let minimumLogs: Int = 5
    static let minimumPoorSleepEvents: Int = 3
    static let minimumStressFatigueEvents: Int = 2
    static let minimumMoodSleepPairs: Int = 7

    // Detection levels
    static let poorSleepHours: Double = 6       // below this is "poor sleep"
    static let highStressLevel: Int = 7          // at or above is "high stress"
    static let consecutiveStressDays: Int = 3    // streak length that triggers the pattern

    // Confidence gates
    static let minimumConfidence: Double = 0.5

    // Standard-normal quantile for the Wilson confidence lower bound. ~1.0 is a
    // soft (≈68%) interval: enough to penalise thin samples (so a 2/2 streak no
    // longer reports 100%) without suppressing genuine patterns at the small
    // sample sizes daily logging produces. Raising it tightens evidence demands.
    static let confidenceZ: Double = 1.0

    // Energy trend
    static let energyTrendWindow: Int = 14
    static let energyDropThreshold: Double = 1.5
    static let confidenceScale: Double = 5.0     // normalises a point-scale delta to 0–1

    // Mood/sleep correlation
    static let moodDiffThreshold: Double = 1.0

    // Medication effect: minimum logged days on each side of a med's start date
    // before/after which we'll compare, and the smallest change in average daily
    // symptom count worth surfacing.
    static let minimumMedEffectDays: Int = 5
    static let medSymptomDeltaThreshold: Double = 0.5

    // Factor (trigger) correlation: minimum days with and without a factor before
    // comparing, and the smallest increase in average daily symptom count on
    // factor days worth surfacing as a likely trigger.
    static let minimumFactorDays: Int = 3
    static let factorSymptomDeltaThreshold: Double = 0.5

    // Custom tracker correlation: minimum logged days on each side of the
    // tracker's mean value before comparing, and the smallest difference in
    // average daily symptom count worth surfacing.
    static let minimumTrackerDays: Int = 5
    static let trackerSymptomDeltaThreshold: Double = 0.5

    // Flare precursors: minimum flares with pre-flare logs before comparing the
    // run-up window against baseline days, and the smallest average stress rise
    // / sleep drop in that window worth surfacing.
    static let minimumFlaresForPattern: Int = 2
    static let flarePrecursorWindowDays: Int = 3
    static let flareStressDeltaThreshold: Double = 1.0
    static let flareSleepDeltaThreshold: Double = 0.75
    // Smallest average overnight wrist-temperature rise (°C) in the run-up
    // window worth surfacing as a flare precursor.
    static let flareTempDeltaThreshold: Double = 0.3
    // Smallest average overnight respiratory-rate rise (breaths/min) in the
    // run-up window worth surfacing as a flare precursor.
    static let flareRespiratoryDeltaThreshold: Double = 1.0

    // Daylight ↔ mood correlation: minimum days carrying a daylight
    // measurement before comparing above- vs below-average daylight days
    // (the mood delta gate reuses moodDiffThreshold).
    static let minimumDaylightDays: Int = 7

    // Workout patterns (HealthKit-fed): minimum days on each side before
    // comparing workout days against rest days (the mood delta gate reuses
    // moodDiffThreshold), and the smallest next-day symptom-count rise after
    // a workout worth surfacing as a recovery/pacing observation.
    static let minimumWorkoutDays: Int = 3
    static let workoutSymptomDeltaThreshold: Double = 0.5

    // Sample-size damping for mean-comparison confidence: with this many days
    // on the comparison's thinner side, confidence is halved; it approaches the
    // raw effect size as data accumulates. Keeps a 2-point swing over 4 days
    // from displaying the same confidence as over 40 days.
    static let smallSampleShrinkage: Double = 5

    // Canonical window for pattern detection. Every surface (Insights tab,
    // foreground notification check, insight history) computes over this window
    // so they can never disagree about which patterns exist.
    static let insightWindowDays: Int = 90
}

enum ChartThreshold {
    // Minimum period-over-period delta before the trend comparison badge shows.
    static let comparisonBadgeMinimumDelta: Double = 0.05
}

enum HealthThreshold {
    // A day's HealthKit workouts count as "Intense exercise" (auto-selecting
    // that factor chip) when they total at least this much time or energy.
    static let intenseWorkoutMinutes: Double = 45
    static let intenseWorkoutKilocalories: Double = 400
    // Logged dietary caffeine (mg) that auto-selects the "Caffeine" factor —
    // roughly half a cup of coffee; trace amounts don't count.
    static let caffeineMilligrams: Double = 50
    // Logged dietary water (litres) that auto-checks the "Hydration" basic.
    static let hydrationLiters: Double = 1.5
}

enum AppLaunch {
    // Set by the UI test runner (see CadenceUITests). Switches the app to an
    // in-memory store, fresh onboarding, and no permission prompts so UI tests
    // are deterministic and never blocked by system dialogs.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitest")
}
