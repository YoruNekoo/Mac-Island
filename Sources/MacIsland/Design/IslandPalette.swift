import SwiftUI

/// The few colors and values that change with the system's accessibility display settings.
///
/// - Increase Contrast: secondary text becomes full white, the progress track and battery outline get much
///   stronger, and a paused item dims less.
/// - Reduce Transparency: the tab lens is a solid fill (no glass, no translucent tint).
///
/// Views read it from the environment (`@Environment(\.islandPalette)`); `IslandView` resolves it once from the
/// system settings.
struct IslandPalette: Equatable {
    var secondaryText: Color
    var track: Color
    var outline: Color
    /// Opacity of the compact timer/stopwatch while paused.
    var pausedOpacity: Double
    /// Reduce Transparency: use solid fills instead of glass and translucent tints.
    var opaque: Bool

    static let standard = IslandPalette(secondaryText: IslandTheme.secondaryText, track: IslandTheme.track,
                                        outline: IslandTheme.outline, pausedOpacity: 0.55, opaque: false)

    static func resolved(increaseContrast: Bool, reduceTransparency: Bool) -> IslandPalette {
        var palette = standard
        if increaseContrast {
            palette.secondaryText = IslandTheme.primaryText
            palette.track = Color.white.opacity(0.42)
            palette.outline = Color.white
            palette.pausedOpacity = 0.8
        }
        palette.opaque = reduceTransparency
        return palette
    }

    /// The tab lens as a solid color: `accent` at `opacity` over the pure black behind it, with no transparency left.
    static func solidLens(accent: Color, opacity: Double) -> Color {
        let base = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor.white
        return Color(.sRGB, red: Double(base.redComponent) * opacity, green: Double(base.greenComponent) * opacity,
                     blue: Double(base.blueComponent) * opacity)
    }
}

private struct IslandPaletteKey: EnvironmentKey {
    static let defaultValue = IslandPalette.standard
}

extension EnvironmentValues {
    var islandPalette: IslandPalette {
        get { self[IslandPaletteKey.self] }
        set { self[IslandPaletteKey.self] = newValue }
    }
}
