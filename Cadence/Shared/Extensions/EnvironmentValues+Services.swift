import SwiftUI

// The @Entry macro (iOS 17+) generates the EnvironmentKey conformance plus the
// getter/setter. The defaults are the @MainActor service singletons; the macro's
// generated `defaultValue` is nonisolated, so we read the singleton through
// MainActor.assumeIsolated. SwiftUI evaluates environment defaults on the main
// actor, so the assertion holds on every render path — but note it is a RUNTIME
// assertion: constructing EnvironmentValues() and reading these keys from a
// non-main executor (e.g. a background test or ImageRenderer path) will trap.
// If such a path ever appears, inject the service explicitly instead of
// relying on the default.
extension EnvironmentValues {
    @Entry var healthKitService: any HealthKitServiceProtocol = MainActor.assumeIsolated { HealthKitService.shared }
    @Entry var notificationService: any NotificationServiceProtocol = MainActor.assumeIsolated { NotificationService.shared }
}
