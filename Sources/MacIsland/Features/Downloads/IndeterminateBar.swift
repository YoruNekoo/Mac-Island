import AppKit
import SwiftUI

/// Indeterminate download bar: a segment sweeping across a track.
///
/// The sweep is one explicit, repeating Core Animation animation on one layer, so the render server draws it and the
/// app does not wake for it (a SwiftUI `TimelineView` cost about 6% CPU). It runs only while the island is expanded;
/// with Reduce Motion the segment rests in the middle.
struct IndeterminateBar: View {
    @Environment(\.islandIsExpanded) private var isExpanded
    @Environment(\.islandAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LayerIndeterminateBar(trackColor: NSColor(IslandTheme.surface), segmentColor: NSColor(accent),
                              isAnimating: isExpanded && !reduceMotion)
            .frame(height: IndeterminateBarMetrics.height)
            .accessibilityHidden(true)
    }
}

enum IndeterminateBarMetrics {
    static let height: CGFloat = 3
    static let cornerRadius: CGFloat = 2
    /// Segment width as a fraction of the track.
    static let segmentFraction: CGFloat = 0.3
    /// Seconds for one sweep.
    static let period: CFTimeInterval = 1.4
}

struct LayerIndeterminateBar: NSViewRepresentable {
    let trackColor: NSColor
    let segmentColor: NSColor
    let isAnimating: Bool

    func makeNSView(context: Context) -> LayerIndeterminateBarView { LayerIndeterminateBarView() }

    func updateNSView(_ view: LayerIndeterminateBarView, context: Context) {
        view.update(trackColor: trackColor, segmentColor: segmentColor, isAnimating: isAnimating)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerIndeterminateBarView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: IndeterminateBarMetrics.height)
    }
}

final class LayerIndeterminateBarView: NSView {
    private static let animationKey = "sweep"
    private let segment = CALayer()
    private var wantsAnimation = false
    private var laidOutWidth: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = IndeterminateBarMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.addSublayer(segment)
        segment.anchorPoint = .zero
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    func update(trackColor: NSColor, segmentColor: NSColor, isAnimating: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = trackColor.cgColor
            segment.backgroundColor = segmentColor.cgColor
        }
        wantsAnimation = isAnimating
        applyMotion()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        segment.frame = CGRect(x: 0, y: 0, width: width * IndeterminateBarMetrics.segmentFraction, height: bounds.height)
        let changed = width != laidOutWidth
        laidOutWidth = width
        applyMotion(restart: changed)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Layer animations are dropped when the layer leaves a window; start again on return.
        if window != nil { applyMotion(restart: true) }
    }

    private func applyMotion(restart: Bool = false) {
        let width = bounds.width
        let segmentWidth = width * IndeterminateBarMetrics.segmentFraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if restart { segment.removeAnimation(forKey: Self.animationKey) }
        if wantsAnimation, window != nil, width > 0 {
            guard segment.animation(forKey: Self.animationKey) == nil else { return }
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = -segmentWidth
            sweep.toValue = width
            sweep.duration = IndeterminateBarMetrics.period
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .linear)
            segment.add(sweep, forKey: Self.animationKey)
        } else {
            segment.removeAnimation(forKey: Self.animationKey)
            // At rest the segment sits in the middle.
            segment.position = CGPoint(x: (width - segmentWidth) / 2, y: 0)
        }
    }
}
