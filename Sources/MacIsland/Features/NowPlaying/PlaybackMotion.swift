import SwiftUI

/// The one description of "how playing or paused the visuals are". The artwork and the soundwave both read it,
/// so they move together, along the same curve, from the same instant.
///
/// It is a plain value (no timers, no flags): the current look is a pure function of the state and the clock.
/// That makes it self-healing: re-creating a view, collapsing or expanding, or toggling rapidly can never leave
/// it stuck, because the answer is recomputed from the stored state every frame.
struct PlaybackVisual: Equatable, Sendable {
    var isPlaying: Bool
    /// When `isPlaying` last changed. `.distantPast` means "already settled".
    var changedAt: Date
    /// How paused the visuals were at `changedAt` (0 = fully playing, 1 = fully paused), so a quick toggle
    /// mid-transition continues smoothly from where things were instead of jumping.
    var pausedAtChange: Double

    static let initial = PlaybackVisual(isPlaying: false, changedAt: .distantPast, pausedAtChange: 1)

    /// A state that is already at rest (no animation), e.g. when music first appears.
    static func settled(isPlaying: Bool) -> PlaybackVisual {
        PlaybackVisual(isPlaying: isPlaying, changedAt: .distantPast, pausedAtChange: isPlaying ? 0 : 1)
    }

    /// 0 = fully playing, 1 = fully paused, at `now`.
    func pausedProgress(at now: Date, reduceMotion: Bool = false) -> Double {
        let target = isPlaying ? 0.0 : 1.0
        let elapsed = now.timeIntervalSince(changedAt)
        let eased = reduceMotion ? PlaybackMotion.crossfadeProgress(elapsed) : PlaybackMotion.springProgress(elapsed)
        return pausedAtChange + (target - pausedAtChange) * eased
    }

    /// The soundwave's energy: 1 = full motion, 0 = still and low.
    func waveEnergy(at now: Date) -> Double {
        min(max(1 - pausedProgress(at: now), 0), 1)
    }

    /// The state after `isPlaying` changes at `now`, continuing from wherever the visuals currently are.
    func changing(isPlaying newValue: Bool, at now: Date) -> PlaybackVisual {
        guard newValue != isPlaying else { return self }
        return PlaybackVisual(isPlaying: newValue, changedAt: now,
                              pausedAtChange: min(max(pausedProgress(at: now), 0), 1))
    }
}

enum PlaybackMotion {
    /// One spring for the artwork and the soundwave (same numbers as everything else that "settles").
    static let response = IslandAnimations.playbackResponse
    static let dampingFraction = IslandAnimations.playbackDamping
    /// After this long the spring is at rest and the transition is over.
    static let duration: TimeInterval = 0.5
    /// With Reduce Motion the artwork only crossfades its dimming, over this long.
    static let crossfadeDuration: TimeInterval = 0.15

    static let transitionFrameInterval: TimeInterval = 1.0 / 60.0
    static let waveFrameInterval: TimeInterval = 1.0 / 24.0

    /// Unit-step response of `Animation.spring(response:dampingFraction:)`, in closed form. It is already moving
    /// at the very first frame (3.5% after 16 ms) and exactly 1 once the transition has finished.
    static func springProgress(_ t: TimeInterval) -> Double {
        if t <= 0 { return 0 }
        if t >= duration { return 1 }
        let omega = 2 * Double.pi / response
        let z = dampingFraction
        guard z < 1 else { return 1 - exp(-omega * t) * (1 + omega * t) }
        let damped = omega * (1 - z * z).squareRoot()
        return 1 - exp(-z * omega * t) * (cos(damped * t) + (z * omega / damped) * sin(damped * t))
    }

    static func crossfadeProgress(_ t: TimeInterval) -> Double {
        min(max(t / crossfadeDuration, 0), 1)
    }
}

/// Frames for the views that follow a `PlaybackVisual`.
///
/// It is a *finite* schedule: frames at 60 fps while the transition runs, then (only for the soundwave while
/// music plays) 24 fps, then it simply ends. When nothing is moving it yields a single frame, so a paused or
/// collapsed wave costs no CPU at all. Any change to its parameters makes SwiftUI start a fresh one, which is
/// why no flag or timer has to be reset.
struct PlaybackMotionSchedule: TimelineSchedule {
    let changedAt: Date
    /// Keep ticking at the wave rate after the transition (playing music, compact notch visible).
    let keepsTicking: Bool
    /// False renders one still frame only (for example while the compact notch is hidden).
    let isActive: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(upcoming: startDate, transitionEnd: changedAt.addingTimeInterval(PlaybackMotion.duration),
                keepsTicking: keepsTicking, isActive: isActive)
    }

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?
        let transitionEnd: Date
        let keepsTicking: Bool
        let isActive: Bool

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            guard isActive else {
                upcoming = nil                                // one still frame, then nothing
                return current
            }
            if current < transitionEnd {
                upcoming = current.addingTimeInterval(PlaybackMotion.transitionFrameInterval)
            } else if keepsTicking {
                upcoming = current.addingTimeInterval(PlaybackMotion.waveFrameInterval)
            } else {
                upcoming = nil                                // settled: the last frame stays on screen
            }
            return current
        }
    }
}


/// A `TimelineView` over a `PlaybackMotionSchedule` that is *replaced* (not just updated) whenever the schedule
/// changes character: transition frames, wave frames, or at rest.
///
/// Measured: a TimelineView whose schedule runs for a while and then ends keeps SwiftUI rendering at the display
/// rate (about 60 wakeups/s, 2.7% CPU) for as long as it stays in the tree, while a view created already at rest
/// costs nothing. Giving the view a new identity when its phase changes makes the finished one go away.
///
/// The "at rest" flag is derived (`settledFor == visual.changedAt`, or the transition is already over), never
/// stored on its own, so a late or cancelled task can only ever leave the view in a state that is still correct.
struct PlaybackTimeline<Content: View>: View {
    let visual: PlaybackVisual
    let keepsTicking: Bool
    let isActive: Bool
    @ViewBuilder let content: (Date) -> Content
    @State private var settledFor: Date?

    private struct Phase: Hashable {
        var keepsTicking: Bool
        var isActive: Bool
        var settled: Bool
    }

    var body: some View {
        let settled = settledFor == visual.changedAt
            || Date.now >= visual.changedAt.addingTimeInterval(PlaybackMotion.duration)
        let schedule = PlaybackMotionSchedule(changedAt: visual.changedAt, keepsTicking: keepsTicking, isActive: isActive)
        TimelineView(schedule) { context in content(context.date) }
            .id(Phase(keepsTicking: keepsTicking, isActive: isActive, settled: settled))
            .task(id: visual.changedAt) {
                // Always ends by recording that this transition is over, even if it already was when the task began:
                // the body may have been evaluated a moment earlier, while it still looked unfinished.
                let remaining = visual.changedAt.addingTimeInterval(PlaybackMotion.duration).timeIntervalSinceNow
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining + 0.02)) }
                guard !Task.isCancelled else { return }
                settledFor = visual.changedAt
            }
    }
}
