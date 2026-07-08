import SwiftUI

@main
struct CadenceWidget_Watch_AppApp: App {
    init() {
        // Activate the WCSession at launch so the first "Save to iPhone" tap
        // isn't racing session activation.
        _ = WatchConnectivityManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
