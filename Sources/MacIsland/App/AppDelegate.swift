import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var islandController: IslandController?
    private var statusItem: NSStatusItem?
    private var toggleNotchItem: NSMenuItem?
    private var playbackItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        let controller = IslandController(settings: settings)
        controller.show()
        islandController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        islandController?.tearDown()
    }

    /// The menu bar icon: always present, since an accessory app has no Dock icon or main menu.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.behavior = []          // the user cannot Command-drag it out of the menu bar
        item.isVisible = true
        if let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Mac Island") {
            image.isTemplate = true // monochrome: follows light and dark menu bars automatically
            item.button?.image = image
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false       // availability is set in menuNeedsUpdate, from the live state
        // The notch is a panel that never takes keyboard focus, so these are the keyboard route to it.
        let toggle = NSMenuItem(title: "Expand Notch", action: #selector(toggleNotch), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleNotchItem = toggle
        menu.addItem(.separator())
        for (title, selector) in [("Play/Pause", #selector(playPause)), ("Next Track", #selector(nextTrack)),
                                  ("Previous Track", #selector(previousTrack))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            playbackItems.append(item)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(title: "About Mac Island", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mac Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let controller = islandController
        toggleNotchItem?.title = controller?.isExpanded == true ? "Collapse Notch" : "Expand Notch"
        toggleNotchItem?.isEnabled = controller?.canToggleExpanded ?? false
        // Playback items need a supported player that is running (and that Mac Island may control).
        let canControl = controller?.canControlPlayback ?? false
        playbackItems.forEach { $0.isEnabled = canControl }
    }

    @objc private func toggleNotch() { islandController?.toggleExpandedFromMenu() }
    @objc private func playPause() { islandController?.sendPlayback(.playPause) }
    @objc private func nextTrack() { islandController?.sendPlayback(.next) }
    @objc private func previousTrack() { islandController?.sendPlayback(.previous) }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppInfo.name])
    }
}
