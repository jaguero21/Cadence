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
