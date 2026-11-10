/// What the expanded island is showing. Each case has a view in `IslandContentView` and a service in
/// `IslandFeatureStore`; the panel and positioning code never change when a feature is added.
enum IslandContent: String, CaseIterable, Hashable, Sendable, Identifiable {
    case nowPlaying, battery, timer, stopwatch, calendar, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .battery: "Battery"
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        case .calendar: "Calendar"
        case .downloads: "Downloads"
        }
    }

    var symbolName: String {
        switch self {
        case .nowPlaying: "music.note"
        case .battery: "battery.75"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .calendar: "calendar"
        case .downloads: "arrow.down.circle"
        }
    }
}
