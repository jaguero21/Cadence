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
}
