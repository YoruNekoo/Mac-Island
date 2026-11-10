import AppKit
import SwiftUI

/// One scroll-wheel event, reduced to what swipe detection needs (and testable without real events).
struct ScrollSample: Equatable, Sendable {
    var phase: NSEvent.Phase
    var momentumPhase: NSEvent.Phase
    var deltaX: CGFloat
    var deltaY: CGFloat
    var isDirectionInvertedFromDevice: Bool

    init(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase = [], deltaX: CGFloat, deltaY: CGFloat = 0,
         isDirectionInvertedFromDevice: Bool) {
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.isDirectionInvertedFromDevice = isDirectionInvertedFromDevice
    }

    init(event: NSEvent) {
        self.init(phase: event.phase, momentumPhase: event.momentumPhase,
                  deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                  isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice)
    }
}

enum SwipeDirection: Sendable {
    case next, previous
}

enum SwipeToSkip {
    /// Horizontal travel, in points, that a swipe must cross to skip a track.
    static let threshold: CGFloat = 40
    /// Once a gesture has travelled this far it is judged horizontal or vertical, and vertical ones are ignored.
    static let axisLockDistance: CGFloat = 8
    /// How far the artwork nudges in the swipe direction as feedback.
    static let nudgeDistance: CGFloat = 5
}

/// Turns the phases of a two-finger scroll into at most one skip per gesture.
///
/// - Direction follows the finger: `isDirectionInvertedFromDevice` is true with natural scrolling, where the
///   scroll delta already follows the fingers; otherwise it is flipped. Swipe left = next, right = previous.
/// - Momentum events, events without a phase (a mouse wheel) and mostly-vertical gestures do nothing.
struct SwipeGestureTracker {
    private enum Stage { case idle, tracking, ignored, fired }

    private var stage = Stage.idle
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0

    mutating func reset() {
        stage = .idle
        travelX = 0
        travelY = 0
    }

    mutating func handle(_ sample: ScrollSample) -> SwipeDirection? {
        guard sample.momentumPhase.isEmpty else { return nil }      // inertia after the fingers lifted
        guard !sample.phase.isEmpty else { return nil }             // a discrete mouse wheel has no phase
        guard !sample.phase.contains(.mayBegin) else { return nil }

        if sample.phase.contains(.began) || stage == .idle {
            reset()
            stage = .tracking
        }
        defer {
            if sample.phase.contains(.ended) || sample.phase.contains(.cancelled) { reset() }
        }
        guard stage == .tracking else { return nil }

        // Positive = fingers moving right.
        let fingerX = sample.isDirectionInvertedFromDevice ? sample.deltaX : -sample.deltaX
        travelX += fingerX
        travelY += abs(sample.deltaY)

        if abs(travelX) + travelY >= SwipeToSkip.axisLockDistance, travelY > abs(travelX) {
            stage = .ignored
            return nil
        }
        guard abs(travelX) >= SwipeToSkip.threshold, abs(travelX) >= travelY else { return nil }
        stage = .fired                                              // at most once per gesture
        return travelX < 0 ? .next : .previous
    }
}

private struct ArtworkNudgeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Horizontal offset the artwork shows briefly after a swipe. Offsetting never changes layout.
    var islandArtworkNudge: CGFloat {
        get { self[ArtworkNudgeKey.self] }
        set { self[ArtworkNudgeKey.self] = newValue }
    }
}


/// Swipe-to-skip feedback on the artwork: a small sideways nudge, or with Reduce Motion a brief dim and recover
/// (the same value and timing drive both, so only the look differs).
private struct ArtworkNudgeModifier: ViewModifier {
    let nudge: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(1 - 0.45 * min(abs(nudge) / SwipeToSkip.nudgeDistance, 1))
        } else {
            content.offset(x: nudge)       // an offset never changes layout
        }
    }
}

extension View {
    func artworkNudge(_ nudge: CGFloat) -> some View { modifier(ArtworkNudgeModifier(nudge: nudge)) }
}
