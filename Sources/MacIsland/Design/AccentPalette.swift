import SwiftUI

/// The accent presets, in one place. Chosen to read as calm and premium on pure black: bright enough to
/// show clearly, soft enough not to glow.
enum AccentPalette {
    static let white = ArtworkColor.white
    static let sky = ArtworkColor(red: 0.40, green: 0.72, blue: 1.00)
    static let mint = ArtworkColor(red: 0.42, green: 0.90, blue: 0.72)
    static let amber = ArtworkColor(red: 1.00, green: 0.78, blue: 0.36)
    static let coral = ArtworkColor(red: 1.00, green: 0.52, blue: 0.48)
    static let violet = ArtworkColor(red: 0.72, green: 0.60, blue: 1.00)

    /// The fixed color for a preset. `.albumArt` has none (it follows the music), so it returns white.
    static func color(for option: AccentOption) -> ArtworkColor {
        switch option {
        case .white, .albumArt: white
        case .sky: sky
        case .mint: mint
        case .amber: amber
        case .coral: coral
        case .violet: violet
        }
    }
}

private struct IslandAccentKey: EnvironmentKey {
    static let defaultValue = Color.white
}

extension EnvironmentValues {
    /// The current accent. Views use it for progress bars, highlights and active-state tints.
    var islandAccent: Color {
        get { self[IslandAccentKey.self] }
        set { self[IslandAccentKey.self] = newValue }
    }
}
