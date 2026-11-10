import AppKit

/// Pure geometry plus screen selection. One place to extend for multiple displays.
enum IslandPositionManager {
    /// One connected display, reduced to what choosing a display needs.
    struct Display: Equatable, Sendable {
        var id: CGDirectDisplayID
        var frame: CGRect
        var isBuiltIn: Bool
        /// The display has a physical camera notch. Mac Island never shows on such a display.
        var hasNotch: Bool = false
    }

    /// Every connected display. `NSScreen.screens.first` is the main display (the one with the menu bar).
    /// A display whose lid is closed is not in this list.
    @MainActor
    static func connectedDisplays() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            return Display(id: id, frame: screen.frame, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                           hasNotch: hasCameraNotch(screen))
        }
    }

    /// Public API only: a notched display reports a top safe-area inset and the menu bar areas either
    /// side of the camera housing.
    @MainActor
    static func hasCameraNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
    }

    /// Picks the display for a setting. The first display is the main one. Anything unavailable falls back
    /// to it: no built-in display (lid closed, desktop Mac), or a cursor that is on no display.
    ///
    /// A notched display is never chosen. Built-in falls back to the main display, then to any display
    /// without a notch. Follow cursor stays on `current` (the last valid display) while the cursor is on a
    /// notched display. `nil` means no display without a notch is connected: the notch hides.
    static func resolveDisplay(_ selection: DisplaySelection, among displays: [Display], cursor: CGPoint,
                               current: CGDirectDisplayID? = nil) -> Display? {
        let valid = displays.filter { !$0.hasNotch }
        guard let fallback = valid.first else { return nil }
        // The main display when it is valid, otherwise the first valid one (display order is kept).
        let main = displays.first.flatMap { $0.hasNotch ? nil : $0 } ?? fallback
        switch selection {
        case .main:
            return main
        case .builtIn:
            return valid.first(where: \.isBuiltIn) ?? main
        case .followCursor:
            if let underCursor = displays.first(where: { contains(cursor, in: $0.frame) }) {
                if !underCursor.hasNotch { return underCursor }
                if let current = valid.first(where: { $0.id == current }) { return current }
            }
            return main
        }
    }

    /// Follow cursor may move the notch only while it is compact and at rest, and only to a different display.
    static func shouldFollowCursor(selection: DisplaySelection, isExpanded: Bool, isTransitioning: Bool,
                                   currentDisplayID: CGDirectDisplayID?, targetDisplayID: CGDirectDisplayID) -> Bool {
        selection == .followCursor && !isExpanded && !isTransitioning && targetDisplayID != currentDisplayID
    }

    /// Inclusive on every edge, unlike `CGRect.contains`: a cursor pushed against the top of a display sits
    /// exactly on `maxY`, which is where the notch is.
    static func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Frame for a top-centered panel of `size` on a screen whose full frame is `screenFrame`.
    /// AppKit origin is bottom-left, so the top edge is `maxY`; `visibleFrame` is deliberately unused
    /// because it excludes the menu bar.
    static func panelFrame(size: CGSize, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }

    /// Frame of the visible notch inside the stable panel: horizontally centered, top edge on the panel's
    /// top edge (AppKit: `maxY`). This is the one definition of "where the notch is" for hit testing.
    static func shapeFrame(size: CGSize, panelFrame: CGRect) -> CGRect {
        CGRect(x: panelFrame.midX - size.width / 2,
               y: panelFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }

    /// Whether `point` (screen coordinates) is inside the visible shape: a rectangle with square top
    /// corners and bottom corners rounded by `bottomRadius`. The transparent corner cut-outs are outside.
    static func shapeContains(_ point: CGPoint, shape: CGRect, bottomRadius: CGFloat) -> Bool {
        guard shape.contains(point) else { return false }
        let radius = min(bottomRadius, shape.width / 2, shape.height)
        // AppKit y grows upward, so the bottom edge is `minY`.
        let leftCenter = CGPoint(x: shape.minX + radius, y: shape.minY + radius)
        let rightCenter = CGPoint(x: shape.maxX - radius, y: shape.minY + radius)
        if point.y < leftCenter.y {
            if point.x < leftCenter.x { return hypot(point.x - leftCenter.x, point.y - leftCenter.y) <= radius }
            if point.x > rightCenter.x { return hypot(point.x - rightCenter.x, point.y - rightCenter.y) <= radius }
        }
        return true
    }
}
