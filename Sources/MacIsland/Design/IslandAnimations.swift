import SwiftUI

enum IslandAnimations {
    /// The one spring for every size change: compact <-> expanded and feature switches while expanded.
    /// Critically damped enough to avoid visible bounce.
    static let morph = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// The notch's size change with Reduce Motion on: near-instant, with the content cross-fading in and out
    /// (`contentFadeIn`/`contentFadeOut`) instead of the spring.
    static let morphReduced = Animation.easeInOut(duration: 0.1)
    static let contentFadeIn = Animation.easeOut(duration: 0.2).delay(0.12)
    static let contentFadeOut = Animation.easeIn(duration: 0.1)

    /// The one "settle" spring for playback visuals (artwork and soundwave), about 0.35 s.
    static let playbackResponse = 0.35
    static let playbackDamping = 0.85

    /// The charging flash's battery fill rising to the current level.
    static let chargeFill = Animation.easeOut(duration: 0.7)

    /// Swipe-to-skip feedback: the artwork nudges out quickly, holds briefly, then springs back.
    static let nudgeOut = Animation.easeOut(duration: 0.08)
    static let nudgeHold: Duration = .milliseconds(80)
    static let nudgeBack = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// The tab lens settling onto a tab after it is released (or tapped).
    static let tabLens = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// The same move with Reduce Motion on: a short fade-like ease, no springiness.
    static let tabLensReduced = Animation.easeInOut(duration: 0.12)

    /// Cross-fade between feature views. Scoped to content changes, never to the notch morph.
    static let contentSwitch = Animation.easeInOut(duration: 0.18)

    /// Ignore repeated click-toggles inside this window so rapid clicks cannot cause animation glitches.
    static let toggleDebounce: Duration = .milliseconds(300)


    /// Arrival bounce: a quick rise to the peak, then a critically damped spring back (no undershoot).
    static let bounceRise = Animation.easeOut(duration: 0.1)
    static let bounceSettle = Animation.spring(response: 0.28, dampingFraction: 1.0)

    /// Accent color changes (a new track in "Match album art" mode, or picking another accent).
    static let accentChange = Animation.easeInOut(duration: 0.4)

    /// After an expand or collapse the shape is still moving for about this long.
    static let settleTime: Duration = .milliseconds(600)
}
