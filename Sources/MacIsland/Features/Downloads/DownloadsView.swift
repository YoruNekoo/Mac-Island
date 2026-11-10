import AppKit
import SwiftUI

/// Expanded Downloads tab.
struct DownloadsView: View {
    @Environment(IslandFeatureStore.self) private var store

    var body: some View {
        let monitor = store.downloads
        DownloadsContent(item: monitor.primary, moreCount: monitor.moreCount, isAccessDenied: !monitor.isAvailable,
                         onOpenSettings: { SystemSettingsLink.downloads.open() })
    }
}

/// Pure presentation, so each state can be rendered without watching a real folder.
struct DownloadsContent: View {
    @Environment(\.islandPalette) private var palette
    let item: DownloadItem?
    let moreCount: Int
    /// macOS refused access to the Downloads folder. Says so, with a way to fix it.
    var isAccessDenied = false
    var onOpenSettings: () -> Void = {}

    var body: some View {
        if isAccessDenied {
            IslandNotice.accessOff(symbol: "arrow.down.circle", subject: "Downloads", openSettings: onOpenSettings)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item?.state {
        case nil:
            IslandNotice(symbol: "arrow.down.circle", title: "No active downloads", detail: "Browser downloads show up here.")
        case .downloading: if let item { downloading(item) }
        case .completed: if let item { completed(item) }
        }
    }

    private func downloading(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.l) {
            HStack(spacing: IslandSpacing.l) {
                Image(systemName: "arrow.down.circle")
                    .font(IslandType.symbolTitle)
                    .foregroundStyle(palette.secondaryText)
                Text(item.displayName)
                    .font(IslandType.title)
                    .foregroundStyle(IslandTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text(DownloadFormatting.size(item.bytes))
                    .font(IslandType.clockBody)
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 8)
                if moreCount > 0 {
                    Text("+\(moreCount) more")
                        .font(IslandType.labelDigits)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            IndeterminateBar()
        }
        .accessibilityElement(children: .combine)
    }

    private func completed(_ item: DownloadItem) -> some View {
        VStack(spacing: IslandSpacing.s) {
            HStack(spacing: IslandSpacing.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(IslandType.symbolTitle)
                    .foregroundStyle(IslandTheme.primaryText)
                Text("Download complete")
                    .font(IslandType.title)
                    .foregroundStyle(IslandTheme.primaryText)
                    .lineLimit(1)
            }
            Text(item.displayName)
                .font(IslandType.body)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Compact-notch glyph: a pulsing down arrow while downloading, a checkmark on completion.
///
/// The pulse is a Core Animation opacity animation on one layer, so the render server draws it and the app does not
/// wake for it (SwiftUI's `symbolEffect(.pulse)` cost about 6% CPU). With Reduce Motion the arrow is static.
struct DownloadGlyph: View {
    let state: DownloadItem.State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width reserved for the glyph so the compact content can leave room for it.
    static let width: CGFloat = 12

    var body: some View {
        Group {
            if state == .completed {
                Image(systemName: "checkmark").font(IslandType.labelSemibold).foregroundStyle(IslandTheme.primaryText)
            } else {
                PulsingArrow(isPulsing: !reduceMotion)
            }
        }
            .frame(width: Self.width)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            .animation(IslandAnimations.contentSwitch, value: state)
            .accessibilityLabel(state == .completed ? "Download complete" : "Downloading")
    }
}


/// A white `arrow.down` on one layer whose opacity pulses via an explicit, repeating Core Animation animation.
struct PulsingArrow: NSViewRepresentable {
    let isPulsing: Bool

    func makeNSView(context: Context) -> PulsingArrowView { PulsingArrowView() }
    func updateNSView(_ view: PulsingArrowView, context: Context) { view.setPulsing(isPulsing) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PulsingArrowView, context: Context) -> CGSize? {
        CGSize(width: DownloadGlyph.width, height: 14)
    }
}

final class PulsingArrowView: NSView {
    private static let animationKey = "pulse"
    private var wantsPulse = false

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: DownloadGlyph.width, height: 14))
        wantsLayer = true
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            layer?.contents = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil)
            layer?.contentsGravity = .center
            layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setPulsing(_ pulsing: Bool) {
        wantsPulse = pulsing
        guard let layer else { return }
        if pulsing {
            guard layer.animation(forKey: Self.animationKey) == nil else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.35
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: Self.animationKey)
        } else {
            layer.removeAnimation(forKey: Self.animationKey)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Layer animations are dropped when the layer leaves a window; start again on return.
        if window != nil { layer?.removeAnimation(forKey: Self.animationKey); setPulsing(wantsPulse) }
    }
}
