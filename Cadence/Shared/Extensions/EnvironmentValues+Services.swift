import SwiftUI

// The @Entry macro (iOS 17+) generates the EnvironmentKey conformance plus the
// getter/setter. The defaults are the @MainActor service singletons; the macro's
// generated `defaultValue` is nonisolated, so we read the singleton through
// MainActor.assumeIsolated — SwiftUI evaluates environment defaults on the main
// actor, so the assertion always holds and the cross-isolation warning is avoided.
extension EnvironmentValues {
    @Entry var healthKitService: any HealthKitServiceProtocol = MainActor.assumeIsolated { HealthKitService.shared }
    @Entry var notificationService: any NotificationServiceProtocol = MainActor.assumeIsolated { NotificationService.shared }
}
