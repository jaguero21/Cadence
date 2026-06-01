import SwiftUI

enum CadenceColor {
    static let accent       = Color(red: 0.200, green: 0.471, blue: 0.941)
    static let background   = Color(.systemGroupedBackground)
    static let cardBG       = Color(.secondarySystemGroupedBackground)
    static let moodBlue     = Color(red: 0.27, green: 0.53, blue: 0.94)
    static let energyOrange = Color(red: 0.98, green: 0.60, blue: 0.22)
    static let sleepPurple  = Color(red: 0.58, green: 0.36, blue: 0.89)
    static let stressRed    = Color(red: 0.94, green: 0.36, blue: 0.36)
    static let successGreen = Color(red: 0.28, green: 0.78, blue: 0.49)
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
