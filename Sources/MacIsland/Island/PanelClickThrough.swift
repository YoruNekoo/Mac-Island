import AppKit

/// Makes every part of the panel outside the visible notch transparent to the mouse.
///
/// The panel is always as large as the biggest possible notch, so most of it is empty. The panel
/// ignores mouse events (clicks, scrolls, hovers all reach the apps and menu bar beneath) unless the
/// pointer is inside the visible rounded shape. Nothing here depends on alpha-based hit testing.
///
/// While the panel ignores events it cannot see the mouse, so a global monitor watches pointer movement
/// in other apps. While it does not ignore them, a local monitor watches movement over the panel.
/// Both only compare the pointer with the shape and flip one property; nothing runs when the mouse is still.
@MainActor
final class PanelClickThrough {
    private weak var panel: IslandPanel?
    private let currentShape: @MainActor () -> (size: CGSize, bottomRadius: CGFloat)
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Called with the pointer position (screen coordinates) on every move. The same monitors that drive
    /// click-through feed Hover and Follow cursor, so nothing extra is installed and no permission is needed.
    var onPointerMove: (@MainActor (CGPoint) -> Void)?
    /// Called for scroll events that landed on the visible shape. Events outside it never reach the panel
    /// (it ignores them), so they scroll the app beneath as usual.
    var onScroll: (@MainActor (ScrollSample) -> Void)?
    private var scrollMonitor: Any?

    /// Movement, plus button releases: a release is when a drag that ended off the notch can hand the mouse back.
    private static let movementEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseUp, .rightMouseUp, .otherMouseUp,
    ]

    init(panel: IslandPanel, currentShape: @escaping @MainActor () -> (size: CGSize, bottomRadius: CGFloat)) {
        self.panel = panel
        self.currentShape = currentShape
    }

    func start() {
        guard globalMonitor == nil else { return }
        panel?.ignoresMouseEvents = true
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.movementEvents) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.movementEvents) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) }
            return event
        }
        refresh()
    }

    private func scrolled(_ event: NSEvent) {
        guard let panel, event.window === panel, isInsideVisibleShape(NSEvent.mouseLocation) else { return }
        onScroll?(ScrollSample(event: event))
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        globalMonitor = nil
        localMonitor = nil
        scrollMonitor = nil
        panel?.ignoresMouseEvents = false
    }

    private func pointerMoved() {
        refresh()
        onPointerMove?(NSEvent.mouseLocation)
    }

    /// Re-evaluates with the current pointer position. Call whenever the shape's size or the panel frame changes.
    func refresh() {
        update(pointer: NSEvent.mouseLocation)
    }

    /// Whether `pointer` (screen coordinates) is inside the visible notch right now.
    func isInsideVisibleShape(_ pointer: CGPoint) -> Bool {
        guard let panel else { return false }
        let shape = currentShape()
        let frame = IslandPositionManager.shapeFrame(size: shape.size, panelFrame: panel.frame)
        return IslandPositionManager.shapeContains(pointer, shape: frame, bottomRadius: shape.bottomRadius)
    }

    /// Decides whether the panel should accept or ignore the mouse for a pointer position.
    ///
    /// While any mouse button is down the decision is frozen: a drag that started on the notch (the progress
    /// bar scrub, the tab lens) must keep receiving events when it leaves the shape, and a press that started
    /// elsewhere must not be captured when it wanders in. The state is re-evaluated at the next move after release.
    func update(pointer: CGPoint, pressedButtons: Int = Int(NSEvent.pressedMouseButtons)) {
        guard let panel, pressedButtons == 0 else { return }
        let shouldIgnore = !isInsideVisibleShape(pointer)
        if panel.ignoresMouseEvents != shouldIgnore { panel.ignoresMouseEvents = shouldIgnore }
    }
}
