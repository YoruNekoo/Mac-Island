import AppKit
import SwiftUI

/// The compact soundwave: five Core Animation bars (see `LayerSoundwaveView`). It uses the artwork color, shows still
/// bars with Reduce Motion or while the compact notch is hidden, and shares the artwork's play/pause spring.
struct LayerSoundwave: NSViewRepresentable {
    let color: Color
    let visual: PlaybackVisual
    let isActive: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> LayerSoundwaveView { LayerSoundwaveView() }

    func updateNSView(_ view: LayerSoundwaveView, context: Context) {
        view.update(color: NSColor(color), isPlaying: visual.isPlaying, changedAt: visual.changedAt,
                    isMoving: isActive && !reduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerSoundwaveView, context: Context) -> CGSize? {
        CGSize(width: SoundwaveView.width, height: SoundwaveView.maxHeight)
    }
}

/// Five `CALayer` bars. While playing, a 0.3 s timer picks new heights and starts one explicit animation per bar;
/// the render server interpolates every frame in between, so the app wakes about 3 times a second instead of 60.
/// Paused (or hidden, or Reduce Motion): no timer and no running animation.
final class LayerSoundwaveView: NSView {
    private var bars: [CALayer] = []
    private var timer: Timer?
    private var lastKey: Key?
    private var color = NSColor.white

    private struct Key: Equatable { var isPlaying: Bool; var changedAt: Date; var isMoving: Bool }

    static let retargetInterval: TimeInterval = 0.3

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: SoundwaveView.width, height: SoundwaveView.maxHeight))
        wantsLayer = true
        layer?.masksToBounds = false
        for index in 0..<SoundwaveModel.barCount {
            let bar = CALayer()
            bar.cornerRadius = SoundwaveView.barWidth / 2
            let x = CGFloat(index) * (SoundwaveView.barWidth + SoundwaveView.barSpacing) + SoundwaveView.barWidth / 2
            bar.position = CGPoint(x: x, y: SoundwaveView.maxHeight / 2)
            bar.bounds = CGRect(x: 0, y: 0, width: SoundwaveView.barWidth, height: Self.stillHeight(index))
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// A timer must never outlive the view: stop it when the view leaves its window, and start fresh on return.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopTimer(); lastKey = nil }
    }

    override var isFlipped: Bool { false }

    func update(color newColor: NSColor, isPlaying: Bool, changedAt: Date, isMoving: Bool) {
        if newColor != color {
            color = newColor
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bars.forEach { $0.backgroundColor = newColor.cgColor }
            CATransaction.commit()
        }
        let key = Key(isPlaying: isPlaying, changedAt: changedAt, isMoving: isMoving)
        guard key != lastKey else { return }
        let firstTime = lastKey == nil
        lastKey = key
        stopTimer()
        if isMoving, isPlaying {
            retarget(spring: !firstTime || changedAt != .distantPast)
            timer = Timer.scheduledTimer(withTimeInterval: Self.retargetInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.retarget(spring: false) }
            }
            timer?.tolerance = 0.05
        } else {
            settleToStill(animated: isMoving && !firstTime && changedAt != .distantPast)
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private static func stillHeight(_ index: Int) -> CGFloat {
        max(SoundwaveView.barWidth, SoundwaveView.maxHeight * CGFloat(SoundwaveModel.heights(at: 0, energy: 0)[index]))
    }

    private func currentHeight(of bar: CALayer) -> CGFloat { bar.presentation()?.bounds.height ?? bar.bounds.height }

    /// The same spring the artwork uses (`IslandAnimations.playbackResponse` / `playbackDamping`).
    private func playPauseSpring(keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        let omega = 2 * Double.pi / IslandAnimations.playbackResponse
        animation.mass = 1
        animation.stiffness = omega * omega
        animation.damping = 2 * IslandAnimations.playbackDamping * omega
        animation.duration = PlaybackMotion.duration
        return animation
    }

    private func retarget(spring: Bool) {
        let time = Date().timeIntervalSinceReferenceDate + Self.retargetInterval
        let heights = SoundwaveModel.heights(at: time, energy: 1)
        for (index, bar) in bars.enumerated() {
            let jitter = Double.random(in: -0.08...0.08)
            let target = max(SoundwaveView.barWidth, SoundwaveView.maxHeight * CGFloat(min(max(heights[index] + jitter, 0.1), 1)))
            animate(bar, to: target, spring: spring)
        }
    }

    private func settleToStill(animated: Bool) {
        for (index, bar) in bars.enumerated() {
            if animated { animate(bar, to: Self.stillHeight(index), spring: true) }
            else {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                bar.removeAllAnimations()
                bar.bounds.size.height = Self.stillHeight(index)
                CATransaction.commit()
            }
        }
    }

    private func animate(_ bar: CALayer, to target: CGFloat, spring: Bool) {
        let from = currentHeight(of: bar)
        let animation: CABasicAnimation = spring ? playPauseSpring(keyPath: "bounds.size.height") : {
            let linear = CABasicAnimation(keyPath: "bounds.size.height")
            linear.duration = Self.retargetInterval
            linear.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return linear
        }()
        animation.fromValue = from
        animation.toValue = target
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bar.bounds.size.height = target                     // the model value; the animation shows the way there
        CATransaction.commit()
        bar.add(animation, forKey: "height")
    }
}
