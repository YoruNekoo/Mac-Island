import SwiftUI

struct StopwatchView: View {
    @Environment(IslandFeatureStore.self) private var store
    @Environment(\.islandIsExpanded) private var isExpanded

    var body: some View {
        let service = store.stopwatch
        let model = service.model
        VStack(spacing: IslandSpacing.xl) {
            // Ticks only while running; elapsed time is computed from the clock, never accumulated.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(model.isRunning && isExpanded))) { _ in
                Text(TimeFormatting.stopwatch(model.elapsed(at: .now)))
                    .font(IslandType.clockDisplay)
                    .foregroundStyle(IslandTheme.primaryText)
                    .accessibilityLabel("Stopwatch time")
                    .accessibilityValue(TimeFormatting.spoken(seconds: Int(TimeFormatting.seconds(model.elapsed(at: .now))))
                                        + (model.isRunning ? "" : (model.hasElapsed ? ", paused" : "")))
            }
            HStack(spacing: IslandSpacing.xl) {
                IslandIconButton(systemName: model.isRunning ? "pause.fill" : "play.fill",
                                 label: model.isRunning ? "Pause" : (model.hasElapsed ? "Resume" : "Start"),
                                 isProminent: true) { service.toggle() }
                IslandIconButton(systemName: "arrow.counterclockwise", label: "Reset",
                                 isEnabled: model.hasElapsed) { service.reset() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
