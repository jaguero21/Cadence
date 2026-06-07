import SwiftUI

// The @Entry macro (iOS 17+) generates the EnvironmentKey conformance plus the
// getter/setter, and emits a Sendable-correct key under Swift 6 strict
// concurrency. The defaults reference @MainActor singletons, which are
// implicitly Sendable.
extension EnvironmentValues {
    @Entry var healthKitService: any HealthKitServiceProtocol = HealthKitService.shared
    @Entry var notificationService: any NotificationServiceProtocol = NotificationService.shared
}
