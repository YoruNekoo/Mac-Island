import Foundation

/// Which display the notch lives on.
enum DisplaySelection: String, CaseIterable, Identifiable, Sendable {
    case builtIn, main, followCursor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtIn: "Built-in display"
        case .main: "Main display"
        case .followCursor: "Follow cursor"
        }
    }
}

/// How the notch opens.
enum ExpandTrigger: String, CaseIterable, Identifiable, Sendable {
    case click, hover
    var id: String { rawValue }
    var title: String {
        switch self {
        case .click: "Click"
        case .hover: "Hover"
        }
    }
}

/// Which feature wins the compact notch when several are active. Recording dots are never affected.
enum CompactPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic, nowPlaying, downloads, calendar, timerStopwatch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .nowPlaying: "Now Playing"
        case .downloads: "Downloads"
        case .calendar: "Calendar"
        case .timerStopwatch: "Timer / Stopwatch"
        }
    }

    /// Features that must be enabled for this choice to be offered; `nil` means always available.
    var requiredFeatures: [FeatureFlag]? {
        switch self {
        case .automatic: nil
        case .nowPlaying: [.nowPlaying]
        case .downloads: [.downloads]
        case .calendar: [.calendar]
        case .timerStopwatch: [.timer, .stopwatch]      // either one is enough
        }
    }
}

/// Accent for progress bars, highlights and active-state tints. The soundwave is not affected.
enum AccentOption: String, CaseIterable, Identifiable, Sendable {
    case white, sky, mint, amber, coral, violet, albumArt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .white: "White"
        case .sky: "Sky"
        case .mint: "Mint"
        case .amber: "Amber"
        case .coral: "Coral"
        case .violet: "Violet"
        case .albumArt: "Match album art"
        }
    }
}
