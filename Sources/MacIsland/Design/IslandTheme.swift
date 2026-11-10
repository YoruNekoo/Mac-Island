import SwiftUI

/// Single source of truth for notch dimensions. Settings (Milestone 5) will feed these.
///
/// The compact size is fixed. The expanded size is dynamic: each feature reports its natural content
/// size and the notch uses it, clamped to `expandedMinSize ... expandedMaxSize`. The panel itself is
/// always `expandedMaxSize`; only the visible shape animates inside it.
struct IslandMetrics: Equatable, Sendable {
    var compactSize = CGSize(width: 150, height: 34)
    var expandedMinSize = CGSize(width: 260, height: 80)
    var expandedMaxSize = CGSize(width: 360, height: 180)
    var compactBottomRadius: CGFloat = 17
    var expandedBottomRadius: CGFloat = 20
    /// Space around a feature's content inside the expanded notch.
    var contentHorizontalPadding: CGFloat = 16
    var contentBottomPadding: CGFloat = 12
    /// Extra height reserved under a feature while the mic/camera status row is showing, so the row never
    /// touches the content.
    var recordingRowReserve: CGFloat = 8

    static let standard = IslandMetrics()

    /// Largest area a feature's content may occupy (below the tab strip, inside the padding).
    var maxContentSize: CGSize {
        CGSize(width: expandedMaxSize.width - 2 * contentHorizontalPadding,
               height: expandedMaxSize.height - compactSize.height - contentBottomPadding)
    }

    /// Expanded notch size for a feature that wants `content` points: content plus tab strip and padding,
    /// clamped to the allowed range.
    func clampedExpandedSize(forContent content: CGSize) -> CGSize {
        CGSize(width: min(expandedMaxSize.width, max(expandedMinSize.width, content.width + 2 * contentHorizontalPadding)),
               height: min(expandedMaxSize.height, max(expandedMinSize.height,
                                                       compactSize.height + content.height + contentBottomPadding)))
    }

    func size(expanded: Bool, expandedSize: CGSize) -> CGSize { expanded ? expandedSize : compactSize }
    func bottomRadius(expanded: Bool) -> CGFloat { expanded ? expandedBottomRadius : compactBottomRadius }
}

enum IslandTheme {
    static let background = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)

    // Surfaces: one set of translucent whites for everything that sits on the black.
    /// Placeholders (artwork without an image).
    static let surfaceSubtle = Color.white.opacity(0.10)
    /// Controls and chips.
    static let surface = Color.white.opacity(0.14)
    /// The empty part of a progress bar.
    static let track = Color.white.opacity(0.18)
    /// Thin outlines (the battery shape).
    static let outline = Color.white.opacity(0.5)

    // Status colors.
    /// Charging and the charging flash. The one green for "power is flowing".
    static let charging = Color(nsColor: .systemGreen)
    /// Low battery.
    static let warning = Color(nsColor: .systemRed)

    /// The tab selection lens without glass (macOS 14-15): resting and while pressed.
    static let tabLensOpacity = 0.16
    static let tabLensPressedOpacity = 0.26
}

/// The type scale. Text uses the default design; numbers that change use a rounded face with fixed-width digits
/// so they never jitter. Add to this scale instead of writing `.system(size:)` in a view.
enum IslandType {
    static let caption = Font.system(size: 10)
    static let captionMedium = Font.system(size: 10, weight: .medium)
    static let captionSemibold = Font.system(size: 10, weight: .semibold)
    static let captionBold = Font.system(size: 10, weight: .bold)
    static let label = Font.system(size: 11)
    static let labelMedium = Font.system(size: 11, weight: .medium)
    static let labelSemibold = Font.system(size: 11, weight: .semibold)
    static let body = Font.system(size: 12)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let bodySemibold = Font.system(size: 12, weight: .semibold)
    static let title = Font.system(size: 14, weight: .semibold)

    /// Sans text whose digits change (minutes, counts): same look, fixed-width digits.
    static let captionDigits = caption.monospacedDigit()
    static let labelDigits = labelMedium.monospacedDigit()
    static let bodyDigits = body.monospacedDigit()

    /// Numerals: rounded, medium, fixed-width digits.
    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }
    static let clockCaption = clock(10)
    static let clockLabel = clock(11)
    static let clockBody = clock(12)
    static let clockLarge = clock(28)
    static let clockDisplay = clock(34)

    /// Symbols (SF Symbols) at their own sizes.
    static func symbol(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static let symbolControl = symbol(13, .semibold)
    static let symbolTitle = symbol(14)
    static let symbolLarge = symbol(18)
    static let symbolHero = symbol(30)
    static let tabIcon = symbol(12, .semibold)
}

/// One spacing scale (even steps), plus the two alignment constants every compact accessory shares.
enum IslandSpacing {
    static let xxs: CGFloat = 2
    static let s: CGFloat = 4
    static let m: CGFloat = 6
    static let l: CGFloat = 8
    static let xl: CGFloat = 10
    static let xxl: CGFloat = 12
    static let gutter: CGFloat = 16
    /// Distance of compact accessories (artwork, glyphs, dots) from the notch's side edges.
    static let accessoryInset: CGFloat = 14
    /// Compact accessories sit this far above the vertical center, which looks centered under the curve.
    static let baselineOffset: CGFloat = 2
}

enum IslandRadius {
    static let control: CGFloat = 8
    static let artworkSmall: CGFloat = 5
    static let bar: CGFloat = 2
}
