import SwiftUI

// Menu-bar-only app. The AppDelegate owns the status item, the menu,
// and the global scroll monitor. The Settings scene keeps SwiftUI happy
// without opening any window.
@main
struct VolumeLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
