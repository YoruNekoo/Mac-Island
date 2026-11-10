import SwiftUI

enum PlaybackFormatting {
    /// "3:07", or "1:03:07" from an hour up. Seconds are floored, like a media player.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Position (0...1) of a pointer x within a bar of `width`.
    static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        width > 0 ? min(max(Double(x / width), 0), 1) : 0
    }
}

/// Elapsed / remaining time over a bar that can be scrubbed or tapped.
///
/// The bar follows the interpolated playback position (no player round trips). While the pointer is down it
/// follows the pointer instead, and exactly one seek is sent when it is released. A tap is a zero-length drag.
struct PlaybackProgressBar: View {
    @Environment(\.islandPalette) private var palette
    let progress: PlaybackProgress
    let tint: Color
    let onSeek: (TimeInterval) -> Void

    @Environment(\.islandActions) private var actions
    @Environment(\.islandIsExpanded) private var isExpanded
    @State private var scrubFraction: Double?
    @State private var isAtLimit = false

    private static let trackHeight: CGFloat = 4
    private static let touchHeight: CGFloat = 16

    var body: some View {
        // Redraws once per second, and only while expanded and playing; never while paused, compact or scrubbing.
        // The bar moves under a point per step on any realistic track, and the labels change once per second anyway.
        WholeSecondTimeline(anchor: WholeSecondSchedule.anchorForCountUp(elapsedSeconds: progress.position(at: .now)),
                            isTicking: progress.isPlaying && isExpanded && scrubFraction == nil) { date in
            let fraction = scrubFraction ?? progress.fraction(at: date)
            let elapsed = fraction * progress.duration
            VStack(spacing: IslandSpacing.xxs) {
                bar(fraction: fraction)
                HStack {
                    Text(PlaybackFormatting.clock(elapsed))
                    Spacer(minLength: 8)
                    Text("-" + PlaybackFormatting.clock(progress.duration - elapsed))
                }
                .font(IslandType.clockCaption)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            }
            // For VoiceOver the bar is a real slider: swipe up or down to move by 10 seconds, or set a position
            // directly. Every change is one seek, the same single command a tap or the end of a scrub sends.
            .accessibilityRepresentation {
                Slider(value: Binding(get: { elapsed }, set: { onSeek($0) }),
                       in: 0...max(progress.duration, 1), step: 10)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(PlaybackFormatting.clock(elapsed)) of \(PlaybackFormatting.clock(progress.duration))")
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Self.trackHeight / 2, style: .continuous)
                    .fill(palette.track)
                    .frame(height: Self.trackHeight)
                RoundedRectangle(cornerRadius: Self.trackHeight / 2, style: .continuous)
                    .fill(tint)
                    .frame(width: max(Self.trackHeight, width * fraction), height: Self.trackHeight)
                if scrubFraction != nil {
                    Circle().fill(tint).frame(width: 9, height: 9)
                        .offset(x: min(max(width * fraction - 4.5, 0), width - 9))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = PlaybackFormatting.fraction(forX: value.location.x, width: width)
                        scrubFraction = fraction
                        // One subtle tick each time the scrub reaches the start or the end.
                        let atLimit = fraction <= 0 || fraction >= 1
                        if atLimit, !isAtLimit { actions.haptic(.scrubLimit) }
                        isAtLimit = atLimit
                        actions.interact()
                    }
                    .onEnded { value in
                        let target = PlaybackFormatting.fraction(forX: value.location.x, width: width) * progress.duration
                        scrubFraction = nil
                        isAtLimit = false
                        onSeek(target)     // the only seek command: on release
                    }
            )
        }
        .frame(height: Self.touchHeight)
    }
}
