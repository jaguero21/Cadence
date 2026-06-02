import SwiftUI

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: any HealthKitServiceProtocol = HealthKitService.shared
}

private struct NotificationServiceKey: EnvironmentKey {
    static let defaultValue: any NotificationServiceProtocol = NotificationService.shared
}

extension EnvironmentValues {
    var healthKitService: any HealthKitServiceProtocol {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }

    var notificationService: any NotificationServiceProtocol {
        get { self[NotificationServiceKey.self] }
        set { self[NotificationServiceKey.self] = newValue }
    }
}
