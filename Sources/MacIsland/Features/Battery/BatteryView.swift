import SwiftUI

struct BatteryView: View {
    let isVisible: Bool
    @Environment(IslandFeatureStore.self) private var store

    var body: some View {
        BatteryContent(state: store.battery.state)
            .task(id: isVisible) { store.battery.setVisible(isVisible) }
    }
}

/// Pure presentation of a `BatteryState`, so layout can be rendered and checked without live hardware.
struct BatteryContent: View {
    @Environment(\.islandPalette) private var palette
    let state: BatteryState

    var body: some View {
        HStack(spacing: IslandSpacing.xxl) {
            Image(systemName: state.symbolName)
                .font(IslandType.symbolHero)
                .foregroundStyle(tint)
                .frame(width: 40)
                .layoutPriority(1)
            // Fills the remaining width and lets text wrap instead of truncating.
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                if state.hasBattery {
                    Text("\(state.percent)%")
                        .font(IslandType.clockLarge)
                        .foregroundStyle(IslandTheme.primaryText)
                        .lineLimit(1)
                }
                Text(state.statusText)
                    .font(IslandType.bodyMedium)
                    .foregroundStyle(IslandTheme.primaryText)
                    .lineLimit(1)
                Text(state.detailText)
                    .font(IslandType.captionDigits)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        if state.isCharging { return IslandTheme.charging }
        if state.isLow { return IslandTheme.warning }
        return IslandTheme.primaryText
    }
}
