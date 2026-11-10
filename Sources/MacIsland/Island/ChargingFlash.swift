import SwiftUI

/// The brief compact "charging" moment shown when the charger is plugged in.
struct ChargingFlash: Equatable, Sendable {
    let percent: Int
    let id = UUID()

    /// How long the flash stays, then the compact notch returns to what it showed before.
    static let duration: Duration = .milliseconds(2500)
    /// At most one flash in this window, so plugging and unplugging quickly does not spam it.
    static let minimumInterval: Duration = .seconds(5)
}

/// Left side of the flash: a bolt.
struct ChargingBoltView: View {
    static let width: CGFloat = 12

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(IslandType.bodySemibold)
            .foregroundStyle(IslandTheme.charging)
            .frame(width: Self.width)
            .accessibilityLabel("Charging")
    }
}

/// Right side of the flash: the percentage and a small battery-shaped bar that fills up to the level.
struct ChargingLevelView: View {
    @Environment(\.islandPalette) private var palette
    let percent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: Double

    static let batteryWidth: CGFloat = 20
    static let batteryHeight: CGFloat = 9
    /// Wide enough for "100%" plus the battery.
    static let textWidth: CGFloat = 31
    static let width: CGFloat = textWidth + 5 + batteryWidth + 2

    /// `startsFilled` skips the fill-up animation (previews and layout checks).
    init(percent: Int, startsFilled: Bool = false) {
        self.percent = percent
        _fill = State(initialValue: startsFilled ? Double(min(max(percent, 0), 100)) / 100 : 0)
    }

    var body: some View {
        HStack(spacing: IslandSpacing.m) {
            Text("\(percent)%")
                .font(IslandType.clockLabel)
                .foregroundStyle(IslandTheme.primaryText)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.textWidth, alignment: .trailing)
            battery
        }
        .onAppear {
            let level = Double(min(max(percent, 0), 100)) / 100
            // Reduce Motion: no fill animation; the whole flash just crossfades in.
            if reduceMotion || fill == level { fill = level } else { withAnimation(IslandAnimations.chargeFill) { fill = level } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Charging, \(percent) percent")
    }

    private var battery: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(palette.outline, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(IslandTheme.charging)
                    .frame(width: max(0, (Self.batteryWidth - 4) * fill), height: Self.batteryHeight - 4)
                    .padding(.leading, IslandSpacing.xxs)
            }
            .frame(width: Self.batteryWidth, height: Self.batteryHeight)
            RoundedRectangle(cornerRadius: 0.5).fill(palette.outline).frame(width: 1, height: 3.5)
        }
    }
}
