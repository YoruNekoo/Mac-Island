import SwiftUI

/// Album artwork "rests" while music is paused: it shrinks a little and dims, then returns when it plays.
/// Applies to the compact and the expanded artwork alike. All the numbers live here.
enum ArtworkPauseStyle {
    /// Paused artwork is drawn at this fraction of its slot, around its center.
    static let pausedScale: CGFloat = 0.85
    /// Paused artwork keeps about this much of its brightness (a black overlay darkens the rest).
    static let pausedBrightness: Double = 0.55

    /// What the artwork looks like for a given `pausedProgress` (0 = playing, 1 = paused). Pure, so it can be tested.
    /// With Reduce Motion the size never changes; only the dimming fades.
    static func appearance(pausedProgress: Double, reduceMotion: Bool) -> (scale: CGFloat, darkening: Double) {
        let p = min(max(pausedProgress, -0.05), 1.05)
        let scale = reduceMotion ? 1 : 1 + (pausedScale - 1) * CGFloat(p)
        return (scale, (1 - pausedBrightness) * p)
    }
}

private struct ArtworkPauseModifier<Shape: InsettableShape>: ViewModifier {
    let visual: PlaybackVisual
    let shape: Shape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Driven by the same PlaybackVisual and spring as the soundwave. A new track that arrives while paused
        // is drawn paused straight away: the state has not changed, so there is nothing to animate.
        PlaybackTimeline(visual: visual, keepsTicking: false, isActive: true) { date in
            let look = ArtworkPauseStyle.appearance(pausedProgress: visual.pausedProgress(at: date, reduceMotion: reduceMotion),
                                                    reduceMotion: reduceMotion)
            content
                // A black overlay in the artwork's own shape: it looks right on pure black and follows the corners.
                .overlay(shape.fill(Color.black.opacity(look.darkening)))
                // scaleEffect does not change layout, so the artwork's slot and everything around it stay put.
                .scaleEffect(look.scale, anchor: .center)
        }
    }
}

extension View {
    /// Shrinks and dims the artwork while music is paused. Apply after the artwork has been clipped to `shape`.
    func artworkPauseStyle<S: InsettableShape>(visual: PlaybackVisual, shape: S) -> some View {
        modifier(ArtworkPauseModifier(visual: visual, shape: shape))
    }
}
