import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings window arrives in Milestone 5. The notch lives in an NSPanel, not a Scene.
        Settings { EmptyView() }
    }
}
