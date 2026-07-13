import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen button (iOS 18): one tap opens the app straight
// into today's log. Deliberately NOT a "log a default mood" button — logging
// data the user didn't choose would be fake awareness. The intent stashes an
// open request in the App Group (controls run in the extension process) and
// the app consumes it on foreground.
@available(iOS 18.0, *)
struct CheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.carpecadence.app.checkin") {
            ControlWidgetButton(action: OpenCheckInIntent()) {
                Label("Log Check-In", systemImage: "pencil.and.list.clipboard")
            }
        }
        .displayName("Cadence Check-In")
        .description("Opens today's log.")
    }
}

@available(iOS 18.0, *)
struct OpenCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Check-In"
    static let description = IntentDescription("Opens Cadence to today's log.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetData.requestCheckInOpen()
        return .result()
    }
}
