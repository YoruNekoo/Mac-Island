import CoreGraphics
import Observation

/// Single source of truth for what the island looks like and how the user is interacting with it.
/// Mutated only by `IslandController`; views read it.
@MainActor
@Observable
final class IslandState {
    /// Visual state driving the morph animation.
    var isExpanded = false
    /// Target expanded size for the current feature (already clamped). Set by the controller from the
    /// size the feature view reports.
    var expandedSize = IslandMetrics.standard.expandedMinSize
    /// Which feature view the expanded island shows.
    var content: IslandContent = .nowPlaying
    var autoCollapse = AutoCollapseConfig.standard
    /// Pointer is currently over the island (reported by the view).
    var isPointerInside = false
    /// Extra size added to the compact shape during the arrival bounce (zero at rest; never more than 6 x 2 pt).
    var bounceDelta = CGSize.zero
    var isBouncing = false
    /// The compact charging flash while it is showing.
    var chargingFlash: ChargingFlash?
    /// Brief horizontal nudge of the artwork after a swipe (zero at rest).
    var artworkNudge: CGFloat = 0
}
