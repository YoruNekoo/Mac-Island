import SwiftUI

struct AppearanceSettingsView: View {
    let settings: AppSettings
    /// Read once when the view is created. Macs without a battery have nothing to flash for.
    @State private var hasBattery = BatteryService.readCurrent().hasBattery

    var body: some View {
        Form {
            Section("Notch") {
                Picker("Display", selection: Binding(
                    get: { settings.displaySelection }, set: { settings.setDisplaySelection($0) })
                ) {
                    ForEach(DisplaySelection.allCases) { Text($0.title).tag($0) }
                }
                if settings.isHiddenOnNotchedDisplay {
                    Text("Mac Island hides on displays with a camera notch.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Picker("Expand with", selection: Binding(
                    get: { settings.expandTrigger }, set: { settings.setExpandTrigger($0) })
                ) {
                    ForEach(ExpandTrigger.allCases) { Text($0.title).tag($0) }
                }
                Picker("Compact notch shows", selection: Binding(
                    get: { settings.effectiveCompactPreference }, set: { settings.setCompactPreference($0) })
                ) {
                    ForEach(settings.availableCompactPreferences) { Text($0.title).tag($0) }
                }
                Text("Recording dots always stay visible.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Accent color") {
                AccentSwatchRow(settings: settings)
                Text("Used for progress bars, highlights and active controls. The soundwave always follows the album art.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Feel") {
                Toggle("Haptic feedback", isOn: Binding(
                    get: { settings.hapticsEnabled }, set: { settings.setHapticsEnabled($0) }))
                Toggle(isOn: Binding(
                    get: { settings.chargingAnimationEnabled && hasBattery }, set: { settings.setChargingAnimationEnabled($0) })
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Charging animation")
                        Text(hasBattery ? "A brief flash in the compact notch when you plug in the charger."
                                        : "This Mac has no battery.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .disabled(!hasBattery || !settings.isEnabled(.battery))
                Toggle(isOn: Binding(
                    get: { settings.swipeToSkipEnabled }, set: { settings.setSwipeToSkipEnabled($0) })
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Swipe to skip")
                        Text("Swipe left or right with two fingers on the notch to change track.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(
                    get: { settings.playfulAnimationsEnabled }, set: { settings.setPlayfulAnimationsEnabled($0) })
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Playful animations")
                        Text("A small pop for new tracks, finished downloads and upcoming events. Off with Reduce Motion.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One tappable swatch per accent: white, the presets, and "Match album art".
struct AccentSwatchRow: View {
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AccentOption.allCases) { option in
                Button { settings.setAccent(option) } label: { swatch(for: option) }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(settings.accent == option ? .isSelected : [])
            }
            Spacer(minLength: 8)
            Text(settings.accent.title).foregroundStyle(.secondary)
        }
    }

    private func swatch(for option: AccentOption) -> some View {
        ZStack {
            if option == .albumArt {
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                Image(systemName: "music.note").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().fill(AccentPalette.color(for: option).color)
            }
        }
        .frame(width: 22, height: 22)
        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
        .overlay(Circle().stroke(Color.accentColor, lineWidth: settings.accent == option ? 2 : 0).padding(-3))
    }
}
