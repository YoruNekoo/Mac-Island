import SwiftUI

/// Pure animation math for the soundwave. Stylized, not driven by real audio: each bar follows two slow
/// out-of-phase sine waves, which reads as organic movement. `energy` blends from a still, low pose (0) to
/// full motion (1), so pausing settles smoothly.
enum SoundwaveModel {
    static let barCount = 5

    /// Bar heights in 0...1 at `time` seconds.
    static func heights(at time: TimeInterval, energy: Double) -> [Double] {
        (0..<barCount).map { index in
            let i = Double(index)
            let slow = 0.5 + 0.5 * sin(time * (1.3 + i * 0.41) + i * 2.9)
            let fast = 0.5 + 0.5 * sin(time * (2.1 + i * 0.67) + i * 1.7)
            let moving = 0.2 + 0.8 * (0.4 * slow + 0.6 * fast)
            let still = 0.22 + 0.05 * Double(index % 2)
            return still + (moving - still) * min(max(energy, 0), 1)
        }
    }
}

/// Compact-notch soundwave: 5 rounded bars tinted with the artwork color.
///
/// Everything it shows is computed from the shared `PlaybackVisual` and the clock: the bar phase from the time,
/// the energy from the same spring the artwork uses. There is no flag, task or stored animation state, so it
/// cannot get stuck. It is drawn by Core Animation, so a paused wave, a collapsed one, or Reduce Motion cost nothing.
struct SoundwaveView: View {
    let color: Color
    let visual: PlaybackVisual

    static let barWidth: CGFloat = 2.6
    static let barSpacing: CGFloat = 2
    static let maxHeight: CGFloat = 16
    static var width: CGFloat {
        CGFloat(SoundwaveModel.barCount) * barWidth + CGFloat(SoundwaveModel.barCount - 1) * barSpacing
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandIsExpanded) private var isExpanded

    var body: some View {
        // The compact notch is hidden while expanded, and Reduce Motion means still bars.
        LayerSoundwave(color: color, visual: visual, isActive: !reduceMotion && !isExpanded, reduceMotion: reduceMotion)
            .frame(width: Self.width, height: Self.maxHeight)
            .accessibilityHidden(true)
    }
}
