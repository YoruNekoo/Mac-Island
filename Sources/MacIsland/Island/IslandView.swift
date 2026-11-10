import SwiftUI

struct IslandView: View {
    let state: IslandState
    let metrics: IslandMetrics
    let features: IslandFeatureStore
    let actions: IslandActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let expanded = state.isExpanded
        let baseSize = metrics.size(expanded: expanded, expandedSize: state.expandedSize)
        // The arrival bounce only ever applies to the compact shape, and grows it by at most 6 x 2 pt.
        let bounce = expanded ? CGSize.zero : state.bounceDelta
        let size = CGSize(width: baseSize.width + bounce.width, height: baseSize.height + bounce.height)
        let shape = IslandShape(bottomRadius: metrics.bottomRadius(expanded: expanded))

        ZStack(alignment: .top) {
            shape.fill(IslandTheme.background)
            CompactActivityView(selected: state.content, chargingFlash: state.chargingFlash)
                .environment(\.islandIsExpanded, expanded)
                .frame(width: metrics.compactSize.width, height: metrics.compactSize.height)
                // The compact content swells slightly with the bounce.
                .scaleEffect(1 + bounce.width / metrics.compactSize.width, anchor: .top)
                .opacity(expanded ? 0 : 1)
                .animation(expanded ? IslandAnimations.contentFadeOut : IslandAnimations.contentFadeIn, value: expanded)
                .allowsHitTesting(false)
                // For VoiceOver the collapsed notch is one button: it says what it shows and expands on activation.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(IslandAccessibility.collapsedLabel)
                .accessibilityValue(features.compactAccessibilitySummary(selected: state.content,
                                                                         chargingPercent: state.chargingFlash?.percent))
                .accessibilityHint(IslandAccessibility.collapsedHint)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { actions.toggle() }
                .accessibilityHidden(expanded)
            // Laid out at the target size (not the animating one) so text never reflows mid-animation;
            // the animating shape clips it. The snap below keeps this frame out of the morph spring.
            IslandContentView(content: state.content, isExpanded: expanded, metrics: metrics,
                              contentWidth: state.expandedSize.width - 2 * metrics.contentHorizontalPadding)
                .frame(width: state.expandedSize.width, alignment: .top)
                .transaction(value: state.expandedSize) { $0.animation = nil }
                .opacity(expanded ? 1 : 0)
                .animation(expanded ? IslandAnimations.contentFadeIn : IslandAnimations.contentFadeOut, value: expanded)
                .allowsHitTesting(expanded)
                // Expanded, the notch is a group that VoiceOver can close (Collapse action, or the escape gesture).
                .accessibilityElement(children: .contain)
                .accessibilityLabel(IslandAccessibility.collapsedLabel)
                .accessibilityAction(named: "Collapse") { actions.collapse() }
                .accessibilityAction(.escape) { actions.collapse() }
                .accessibilityHidden(!expanded)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        // Child controls (Buttons) take priority over this gesture, so they never trigger a toggle.
        .onTapGesture { actions.toggle() }
        .onHover { actions.pointerInside($0) }
        // Pin to the top edge of the window; only width/height change.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // One spring for every size change: compact <-> expanded and switching features while expanded.
        .animation(reduceMotion ? IslandAnimations.morphReduced : IslandAnimations.morph, value: baseSize)
        .environment(\.islandPalette, .resolved(increaseContrast: contrast == .increased, reduceTransparency: reduceTransparency))
        .environment(\.islandActions, actions)
        .environment(\.islandAccent, features.accent.color)
        .environment(\.islandArtworkNudge, state.artworkNudge)
        .animation(IslandAnimations.accentChange, value: features.accent)
        .environment(features)
        .ignoresSafeArea()
    }
}
