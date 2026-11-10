import SwiftUI

struct TimerView: View {
    @Environment(\.islandPalette) private var palette
    @Environment(IslandFeatureStore.self) private var store
    @Environment(\.islandIsExpanded) private var isExpanded

    var body: some View {
        let service = store.timer
        Group {
            switch service.model.phase {
            case .idle: setup(service)
            case .running, .paused: countdown(service, finished: false)
            case .finished: countdown(service, finished: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func setup(_ service: TimerService) -> some View {
        HStack(spacing: IslandSpacing.m) {
            ForEach(TimerUnit.allCases, id: \.self) { unit in
                // One adjustable field per unit for VoiceOver ("Minutes, 5": swipe up or down to change it). The
                // chevrons stay for the pointer; they are not read out as well.
                VStack(spacing: 0) {
                    IslandChevronButton(systemName: "chevron.up", label: "Increase \(unit.label)") {
                        service.adjust(unit, by: 1)
                    }
                    Text(String(format: "%02d", service.value(for: unit)))
                        .font(IslandType.clockLarge)
                        .foregroundStyle(IslandTheme.primaryText)
                    IslandChevronButton(systemName: "chevron.down", label: "Decrease \(unit.label)") {
                        service.adjust(unit, by: -1)
                    }
                    Text(unit.label)
                        .font(IslandType.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(unit.fullName)
                .accessibilityValue("\(service.value(for: unit))")
                .accessibilityAdjustableAction { direction in
                    service.adjust(unit, by: direction == .increment ? 1 : -1)
                }
            }
            IslandIconButton(systemName: "play.fill", label: "Start timer", isProminent: true,
                             isEnabled: service.canStart) { service.start() }
                .padding(.leading, IslandSpacing.l)
        }
    }

    private func countdown(_ service: TimerService, finished: Bool) -> some View {
        let model = service.model
        let isRunning: Bool = { if case .running = model.phase { true } else { false } }()
        return VStack(spacing: IslandSpacing.xl) {
            if finished {
                Text("Time's up")
                    .font(IslandType.clockLarge)
                    .foregroundStyle(IslandTheme.primaryText)
                    .lineLimit(1)
            } else {
                WholeSecondTimeline(anchor: WholeSecondSchedule.anchorForCountdown(
                                        remainingSeconds: TimeFormatting.seconds(model.remaining(at: .now))),
                                    isTicking: isRunning && isExpanded) { _ in
                    Text(TimeFormatting.countdown(model.remaining(at: .now)))
                        .font(IslandType.clockDisplay)
                        .foregroundStyle(IslandTheme.primaryText)
                        .accessibilityLabel("Timer countdown")
                        .accessibilityValue(TimeFormatting.spoken(seconds: Int(TimeFormatting.seconds(model.remaining(at: .now)).rounded(.up)))
                                            + (isRunning ? " remaining" : ", paused"))
                }
            }
            HStack(spacing: IslandSpacing.xl) {
                if !finished {
                    IslandIconButton(systemName: isRunning ? "pause.fill" : "play.fill",
                                     label: isRunning ? "Pause" : "Resume", isProminent: true) {
                        isRunning ? service.pause() : service.resume()
                    }
                }
                IslandIconButton(systemName: "arrow.counterclockwise", label: "Reset timer",
                                 isProminent: finished) { service.reset() }
            }
        }
    }
}
