import CoreGraphics

/// Things that earn a small pop in the compact notch.
enum ArrivalKind: Sendable {
    case trackChanged, downloadCompleted, eventSoon
}

/// The rules and numbers of the arrival bounce.
enum ArrivalBounce {
    /// The most the shape ever grows: 6 pt wider (3 per side), 2 pt taller. The top edge never moves.
    static let peak = CGSize(width: 6, height: 2)
    /// Quick rise, then a critically damped spring back to exactly the resting size: no undershoot.
    static let riseDuration: Duration = .milliseconds(100)
    static let settleDuration: Duration = .milliseconds(280)
    /// Events arriving within this window become one bounce.
    static let coalesceWindow: Duration = .milliseconds(150)

    static func canBounce(playfulEnabled: Bool, reduceMotion: Bool, isExpanded: Bool,
                          isTransitioning: Bool, isBouncing: Bool) -> Bool {
        playfulEnabled && !reduceMotion && !isExpanded && !isTransitioning && !isBouncing
    }
}
