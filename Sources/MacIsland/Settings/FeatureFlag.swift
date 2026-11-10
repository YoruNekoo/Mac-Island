/// The features that can be switched on and off in Settings.
enum FeatureFlag: String, CaseIterable, Identifiable, Sendable {
    case nowPlaying, battery, timer, stopwatch, calendar, recording, downloads

    var id: String { rawValue }

    /// Runs a background source (listeners, polling). Timer and Stopwatch only run when the user starts them.
    var isBackgroundMonitor: Bool { self != .timer && self != .stopwatch }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .battery: "Battery"
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        case .calendar: "Calendar"
        case .recording: "Recording indicator"
        case .downloads: "Downloads"
        }
    }

    /// One short line shown under the toggle. Features that ask for a permission say so.
    var summary: String {
        switch self {
        case .nowPlaying: "Track, artwork and controls for Music and Spotify."
        case .battery: "Charge level, power source and time remaining."
        case .timer: "Countdown timer with a notification when it ends."
        case .stopwatch: "Stopwatch with millisecond precision."
        case .calendar: "Your next event within 24 hours. Asks for Calendar access."
        case .recording: "A dot while the microphone or camera is in use."
        case .downloads: "Browser downloads in progress. Asks for Downloads access."
        }
    }

    /// The expanded-notch tab this feature owns. The recording indicator has none (compact dots and a status row).
    var content: IslandContent? {
        switch self {
        case .nowPlaying: .nowPlaying
        case .battery: .battery
        case .timer: .timer
        case .stopwatch: .stopwatch
        case .calendar: .calendar
        case .downloads: .downloads
        case .recording: nil
        }
    }
}

extension IslandContent {
    var feature: FeatureFlag {
        switch self {
        case .nowPlaying: .nowPlaying
        case .battery: .battery
        case .timer: .timer
        case .stopwatch: .stopwatch
        case .calendar: .calendar
        case .downloads: .downloads
        }
    }
}
