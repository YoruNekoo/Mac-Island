import AppKit

/// Observes mouse-down events delivered to *other* apps so the island can dismiss itself.
///
/// Uses `NSEvent.addGlobalMonitorForEvents`: it is read-only (cannot block or alter clicks) and
/// mouse events need no Accessibility permission. Limitations: it never fires for clicks inside this
/// app's own windows (the island itself, its status menu), and is only installed while expanded.
@MainActor
final class OutsideClickMonitor {
    private var monitor: Any?

    func start(onOutsideClick: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            Task { @MainActor in onOutsideClick() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
