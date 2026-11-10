import SwiftUI

/// Expanded layout: a tab bar across the top strip (the same height as the compact notch)
/// and the selected feature underneath. Add a case per feature here.
///
/// Each feature reports its natural size and is laid out at the notch's target content width, so it looks
/// exactly as it did in the old fixed frame while the notch itself sizes to the content.
struct IslandContentView: View {
    let content: IslandContent
    let isExpanded: Bool
    let metrics: IslandMetrics
    /// Width the feature is laid out at: the target notch width minus padding.
    let contentWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            IslandTabBar(selected: content)
                .frame(height: metrics.compactSize.height)
            ZStack {
                featureView.id(content).transition(.opacity)
            }
            .animation(IslandAnimations.contentSwitch, value: content)
            .frame(width: contentWidth)
            .padding(.bottom, metrics.contentBottomPadding)
        }
        .overlay(alignment: .bottom) { RecordingStatusRow().padding(.bottom, IslandSpacing.baselineOffset) }
        .environment(\.islandIsExpanded, isExpanded)
    }

    @ViewBuilder
    private var featureView: some View {
        switch content {
        case .nowPlaying: FeatureContainer(id: .nowPlaying, metrics: metrics) { NowPlayingView(isVisible: isExpanded) }
        case .battery: FeatureContainer(id: .battery, metrics: metrics) { BatteryView(isVisible: isExpanded) }
        case .timer: FeatureContainer(id: .timer, metrics: metrics) { TimerView() }
        case .stopwatch: FeatureContainer(id: .stopwatch, metrics: metrics) { StopwatchView() }
        case .calendar: FeatureContainer(id: .calendar, metrics: metrics) { CalendarView(isVisible: isExpanded) }
        case .downloads: FeatureContainer(id: .downloads, metrics: metrics) { DownloadsView() }
        }
    }
}

/// Wraps one feature view: reports its natural size and lays it out at the width it is given.
struct FeatureContainer<Content: View>: View {
    let id: IslandContent
    let metrics: IslandMetrics
    @ViewBuilder let content: Content
    @Environment(\.islandActions) private var actions
    @Environment(IslandFeatureStore.self) private var store
    @State private var sink = IdealSizeSink()

    var body: some View {
        // While a mic or camera is in use the status row needs room of its own below the content.
        FeatureLayout(maxSize: metrics.maxContentSize,
                      bottomReserve: store.recording.isAnyActive ? metrics.recordingRowReserve : 0,
                      publish: { [sink, actions, id] size in
            sink.publish(size) { actions.reportContentSize(id, size) }
        }) { content }
    }
}

/// Delivers a feature's ideal size to the controller once per change, one run-loop turn later. Layout must
/// never mutate observable state directly, and repeated layout passes must not repeat the report.
final class IdealSizeSink: @unchecked Sendable {
    private var last: CGSize?

    @MainActor
    func publish(_ size: CGSize, deliver: @escaping @MainActor @Sendable () -> Void) {
        guard size != last else { return }
        last = size
        DispatchQueue.main.async { MainActor.assumeIsolated { deliver() } }
    }
}

/// Reads the child's ideal size (clamped to the largest area the notch can offer) and reports it, then
/// places the child at whatever width it is offered. Content that is too long truncates or compresses
/// inside the clamp; anything still too big is clipped by the notch shape.
struct FeatureLayout: Layout {
    let maxSize: CGSize
    /// Empty space kept below the child (included in the reported size).
    let bottomReserve: CGFloat
    let publish: @MainActor @Sendable (CGSize) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        let childMaxHeight = max(0, maxSize.height - bottomReserve)
        let natural = CGSize(width: min(ideal.width, maxSize.width),
                             height: min(ideal.height, childMaxHeight) + bottomReserve)
        // SwiftUI runs layout on the main thread.
        MainActor.assumeIsolated { publish(natural) }
        let width = min(proposal.width ?? natural.width, maxSize.width)
        let fitted = child.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: min(fitted, childMaxHeight) + bottomReserve)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: max(0, bounds.height - bottomReserve)))
    }
}
