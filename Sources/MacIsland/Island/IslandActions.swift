import SwiftUI

/// Callbacks views use to talk to the controller. Injected through the environment so feature
/// views can report interaction without knowing about the controller.
struct IslandActions: Sendable {
    /// User clicked the notch body: expand when compact, collapse when expanded (debounced).
    var toggle: @MainActor @Sendable () -> Void
    /// Explicit collapse (e.g. a close button).
    var collapse: @MainActor @Sendable () -> Void
    /// Any user activity inside the island; resets the auto-collapse delay.
    var interact: @MainActor @Sendable () -> Void
    /// Show a different feature in the expanded island.
    var select: @MainActor @Sendable (IslandContent) -> Void
    /// A feature's natural content size (before padding and clamping). The id lets the controller ignore
    /// reports from a feature that is fading out.
    var reportContentSize: @MainActor @Sendable (IslandContent, CGSize) -> Void
    /// Pointer entered or left the island.
    var pointerInside: @MainActor @Sendable (Bool) -> Void
    /// A subtle haptic tick, if the user has haptics on.
    var haptic: @MainActor @Sendable (HapticKind) -> Void

    static let none = IslandActions(toggle: {}, collapse: {}, interact: {}, select: { _ in }, reportContentSize: { _, _ in }, pointerInside: { _ in }, haptic: { _ in })
}

private struct IslandActionsKey: EnvironmentKey {
    static let defaultValue = IslandActions.none
}

extension EnvironmentValues {
    var islandActions: IslandActions {
        get { self[IslandActionsKey.self] }
        set { self[IslandActionsKey.self] = newValue }
    }
}

private struct IslandIsExpandedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the island is expanded. Feature views use it to pause animation timelines when hidden.
    var islandIsExpanded: Bool {
        get { self[IslandIsExpandedKey.self] }
        set { self[IslandIsExpandedKey.self] = newValue }
    }
}
