import AppKit
import SwiftUI

/// Owns the single Settings window. Showing it again focuses the existing window; it is never duplicated.
///
/// The app stays an accessory app (no Dock icon) the whole time: the activation policy is never changed.
/// An accessory app can still own a key window, so activating the app and ordering the window front is enough.
@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginModel
    private var window: NSWindow?
    private var activeObserver: NSObjectProtocol?

    init(settings: AppSettings, launchAtLogin: LaunchAtLoginModel = LaunchAtLoginModel()) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
    }

    func show() {
        launchAtLogin.refresh()     // always reflect the real login-item status on open
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, launchAtLogin: launchAtLogin))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Mac Island Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false          // closing hides it; the same window is reused
        window.setContentSize(SettingsView.size)
        window.center()
        // The status may change in System Settings while this window is open.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.launchAtLogin.refresh() }
        }
        return window
    }

    var isWindowVisible: Bool { window?.isVisible ?? false }
}
