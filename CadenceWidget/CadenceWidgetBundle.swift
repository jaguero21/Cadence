import WidgetKit
import SwiftUI

@main
struct CadenceWidgetBundle: WidgetBundle {
    var body: some Widget {
        CadenceWidget()
        if #available(iOS 18.0, *) {
            CheckInControl()
        }
    }
}
