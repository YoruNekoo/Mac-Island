import SwiftUI

/// Where the tabs and the selection lens sit. Pure geometry, so the drag behavior can be tested.
struct TabLensGeometry: Equatable {
    static let tabWidth: CGFloat = 36
    static let tabHeight: CGFloat = 24
    static let spacing: CGFloat = 4

    let count: Int

    var width: CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * Self.tabWidth + CGFloat(count - 1) * Self.spacing
    }

    /// The tab under a pointer at `x` (0 is the left edge of the row). Clamped, so dragging past either end picks the end tab.
    func index(atX x: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let raw = Int(((x + Self.spacing / 2) / (Self.tabWidth + Self.spacing)).rounded(.down))
        return min(max(raw, 0), count - 1)
    }

    /// Left edge of a tab's slot.
    func originX(ofIndex index: Int) -> CGFloat {
        CGFloat(index) * (Self.tabWidth + Self.spacing)
    }

    /// Left edge of the lens while it follows a pointer at `x`: centered on the pointer, kept inside the row.
    func lensOriginX(followingPointerX x: CGFloat) -> CGFloat {
        min(max(x - Self.tabWidth / 2, 0), max(width - Self.tabWidth, 0))
    }
}

/// The expanded notch's feature switcher.
///
/// The selection indicator is a lens: press it (or anywhere on the row) and drag across the tabs; it follows the
/// pointer, the tab under it lights up, and the selection commits when you let go. A tap is a drag of zero length,
/// so tapping a tab still works.
///
/// On macOS 26 the lens is Liquid Glass (interactive glass, morphing between tabs). On macOS 14-15 it is a soft
/// translucent capsule that moves the same way.
struct IslandTabBar: View {
    @Environment(\.islandPalette) private var palette
    let selected: IslandContent
    @Environment(\.islandActions) private var actions
    @Environment(\.islandAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(IslandFeatureStore.self) private var store
    @Namespace private var lensNamespace
    @State private var dragX: CGFloat?

    /// Set `MACISLAND_TAB_FALLBACK=1` in the environment to run the non-glass lens on macOS 26 (for testing it).
    static let forcesFallback = ProcessInfo.processInfo.environment["MACISLAND_TAB_FALLBACK"] != nil

    var body: some View {
        // Only enabled features get a tab (Downloads also needs macOS folder access).
        let tabs = store.visibleTabs
        let geometry = TabLensGeometry(count: tabs.count)
        let candidate = dragX.map { tabs[geometry.index(atX: $0)] } ?? selected

        ZStack(alignment: .leading) {
            lensLayer(tabs: tabs, geometry: geometry)
            HStack(spacing: TabLensGeometry.spacing) {
                ForEach(tabs) { tab in
                    icon(for: tab, isCandidate: tab == candidate)
                }
            }
        }
        .frame(width: geometry.width, height: TabLensGeometry.tabHeight)
        .contentShape(Rectangle())
        .gesture(dragGesture(tabs: tabs, geometry: geometry))
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Icons

    private func icon(for tab: IslandContent, isCandidate: Bool) -> some View {
        Image(systemName: tab.symbolName)
            .font(IslandType.tabIcon)
            .foregroundStyle(isCandidate ? accent : palette.secondaryText)
            .frame(width: TabLensGeometry.tabWidth, height: TabLensGeometry.tabHeight)
            .accessibilityElement()
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(tab == selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { actions.select(tab) }
    }

    // MARK: - Lens

    /// The lens sits in the selected tab's slot, or floats under the pointer while pressed. Both are the same
    /// view (same identity), so changing between them morphs instead of jumping.
    @ViewBuilder
    private func lensLayer(tabs: [IslandContent], geometry: TabLensGeometry) -> some View {
        // Reduce Transparency: no glass, a solid lens instead.
        if #available(macOS 26.0, *), !Self.forcesFallback, !palette.opaque {
            GlassEffectContainer(spacing: IslandSpacing.l) {
                lensStack(tabs: tabs, geometry: geometry, lens: { glassLens })
            }
        } else {
            lensStack(tabs: tabs, geometry: geometry, lens: { fallbackLens })
        }
    }

    private func lensStack<Lens: View>(tabs: [IslandContent], geometry: TabLensGeometry,
                                       @ViewBuilder lens: () -> Lens) -> some View {
        let lensView = lens()
            .scaleEffect(dragX == nil ? 1 : 1.1)
            .animation(lensAnimation, value: dragX == nil)
        return ZStack(alignment: .leading) {
            HStack(spacing: TabLensGeometry.spacing) {
                ForEach(tabs) { tab in
                    Color.clear
                        .frame(width: TabLensGeometry.tabWidth, height: TabLensGeometry.tabHeight)
                        .overlay { if dragX == nil, tab == selected { lensView } }
                }
            }
            if let dragX {
                lensView.offset(x: geometry.lensOriginX(followingPointerX: dragX))
            }
        }
    }

    @available(macOS 26.0, *)
    private var glassLens: some View {
        Color.clear
            .frame(width: TabLensGeometry.tabWidth, height: TabLensGeometry.tabHeight)
            .glassEffect(.regular.tint(accent.opacity(0.22)).interactive(), in: .capsule)
            .glassEffectID("tabLens", in: lensNamespace)
    }

    private var fallbackLens: some View {
        let opacity = dragX == nil ? IslandTheme.tabLensOpacity : IslandTheme.tabLensPressedOpacity
        return Capsule()
            .fill(palette.opaque ? IslandPalette.solidLens(accent: accent, opacity: opacity) : accent.opacity(opacity))
            .frame(width: TabLensGeometry.tabWidth, height: TabLensGeometry.tabHeight)
            .matchedGeometryEffect(id: "tabLens", in: lensNamespace)
    }

    private var lensAnimation: Animation {
        reduceMotion ? IslandAnimations.tabLensReduced : IslandAnimations.tabLens
    }

    // MARK: - Gesture

    /// Press and drag moves the lens; the selection commits once, on release. A tap is a zero-length drag.
    private func dragGesture(tabs: [IslandContent], geometry: TabLensGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                actions.interact()
                // While the finger is down the lens tracks it directly (no animation); only settling animates.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragX = value.location.x }
            }
            .onEnded { value in
                guard !tabs.isEmpty else {
                    dragX = nil
                    return
                }
                let target = tabs[geometry.index(atX: value.location.x)]
                withAnimation(lensAnimation) {
                    dragX = nil
                    actions.select(target)
                }
            }
    }
}
