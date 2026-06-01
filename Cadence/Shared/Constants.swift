import SwiftUI
import UIKit

enum CadenceColor {
    // System adaptive colors — already track light/dark automatically.
    static let background = Color(.systemGroupedBackground)
    static let cardBG     = Color(.secondarySystemGroupedBackground)

    // Brand colors — slightly lighter in dark mode to maintain contrast
    // against dark card backgrounds (UIColor dynamicProvider handles the shift).
    static let accent       = Color(uiColor: .dynamic(light: (0.200, 0.471, 0.941), dark: (0.35, 0.57, 0.96)))
    static let moodBlue     = Color(uiColor: .dynamic(light: (0.27,  0.53,  0.94),  dark: (0.40, 0.62, 0.97)))
    static let energyOrange = Color(uiColor: .dynamic(light: (0.98,  0.60,  0.22),  dark: (1.00, 0.70, 0.35)))
    static let sleepPurple  = Color(uiColor: .dynamic(light: (0.58,  0.36,  0.89),  dark: (0.70, 0.50, 0.95)))
    static let stressRed    = Color(uiColor: .dynamic(light: (0.94,  0.36,  0.36),  dark: (1.00, 0.50, 0.50)))
    static let successGreen = Color(uiColor: .dynamic(light: (0.28,  0.78,  0.49),  dark: (0.40, 0.88, 0.58)))
}

private extension UIColor {
    static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dark.0,  green: dark.1,  blue: dark.2,  alpha: 1)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        }
    }
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
