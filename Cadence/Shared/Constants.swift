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

    // Energy trend
    static let energyTrendWindow: Int = 14
    static let energyDropThreshold: Double = 1.5
    static let confidenceScale: Double = 5.0     // normalises a point-scale delta to 0–1

    // Mood/sleep correlation
    static let moodDiffThreshold: Double = 1.0
}
