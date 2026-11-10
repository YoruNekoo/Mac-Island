import Observation
import OSLog

/// What the compact notch can summarize.
enum CompactActivity: Equatable, Sendable {
    case timer, stopwatch, nowPlaying, battery
    /// Only shown when pinned in Settings (otherwise downloads use the small leading glyph).
    case download
    /// Only shown when pinned in Settings (otherwise the calendar has no compact presence).
    case calendar
}

/// Owns every feature service so each keeps its own state independent of which tab is showing.
/// Injected into the view tree through the SwiftUI environment.
@MainActor
@Observable
final class IslandFeatureStore {
    let nowPlaying: NowPlayingService
    let battery: BatteryService
    let timer: TimerService
    let stopwatch: StopwatchService
    let calendar: CalendarService
    let recording: RecordingMonitor
    let downloads: DownloadMonitor
    let settings: AppSettings

    /// Features whose services are currently started. A feature that is off is never in here, so it can
    /// never touch a permission or hold a listener.
    private(set) var runningFeatures: Set<FeatureFlag> = []
    /// Audit trail: `log show --predicate 'subsystem == "com.macisland.app"'` lists every start and stop.
    private static let log = Logger(subsystem: "com.macisland.app", category: "features")
    @ObservationIgnored private var isStarted = false
    /// The notch is hidden (only notched displays connected): background monitors are stopped, while a
    /// running Timer or Stopwatch keeps its state.
    @ObservationIgnored private(set) var isPaused = false
    /// Called after a feature is turned on or off and its service has been started or stopped.
    @ObservationIgnored var onFeatureToggled: (@MainActor (FeatureFlag, Bool) -> Void)?
    /// Something arrived that deserves the compact "pop": a new track, a finished download, an event in 5 min.
    @ObservationIgnored var onArrival: (@MainActor (ArrivalKind) -> Void)?
    /// The charger was just plugged in (battery to external power), with the battery percentage.
    @ObservationIgnored var onPlugIn: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var eventSoon: EventSoonDetector?

    init(nowPlaying: NowPlayingService = NowPlayingService(),
         battery: BatteryService = BatteryService(),
         timer: TimerService = TimerService(),
         stopwatch: StopwatchService = StopwatchService(),
         calendar: CalendarService = CalendarService(),
         recording: RecordingMonitor = RecordingMonitor(),
         downloads: DownloadMonitor = DownloadMonitor(),
         settings: AppSettings = AppSettings()) {
        self.nowPlaying = nowPlaying
        self.battery = battery
        self.timer = timer
        self.stopwatch = stopwatch
        self.calendar = calendar
        self.recording = recording
        self.downloads = downloads
        self.settings = settings
        settings.onFeatureChange = { [weak self] feature, enabled in self?.featureChanged(feature, enabled: enabled) }
        nowPlaying.onTrackChange = { [weak self] in self?.onArrival?(.trackChanged) }
        downloads.onCompletion = { [weak self] in self?.onArrival?(.downloadCompleted) }
        battery.onPlugIn = { [weak self] percent in self?.onPlugIn?(percent) }
        let detector = EventSoonDetector { [weak self] in self?.onArrival?(.eventSoon) }
        eventSoon = detector
        calendar.onNextEventChange = { event in detector.update(event) }
    }

    /// The accent for progress bars, highlights and active-state tints.
    /// "Match album art" follows the current track (already brightness-clamped for black) and is white
    /// when nothing is playing. The soundwave always uses the artwork color regardless.
    var accent: ArtworkColor {
        switch settings.accent {
        case .albumArt:
            isEnabled(.nowPlaying) && nowPlaying.snapshot != nil ? (nowPlaying.artworkColor ?? .white) : .white
        case let preset:
            AccentPalette.color(for: preset)
        }
    }

    func isEnabled(_ feature: FeatureFlag) -> Bool { settings.isEnabled(feature) }

    /// Tabs the expanded notch offers: enabled features only. A feature that lacks its permission keeps its tab
    /// and explains itself there, instead of silently disappearing.
    var visibleTabs: [IslandContent] {
        IslandContent.allCases.filter { isEnabled($0.feature) }
    }

    /// Starts only the enabled features. Disabled ones are never started, so they never prompt.
    func start() {
        isStarted = true
        for feature in FeatureFlag.allCases where isEnabled(feature) { startFeature(feature) }
    }

    func stop() {
        isStarted = false
        isPaused = false
        eventSoon?.cancel()
        for feature in runningFeatures { stopFeature(feature) }
    }

    /// Stops every background monitor (listeners, timers, polling) while the notch is hidden.
    /// Timer and Stopwatch are user-started countdowns, not monitors, so they keep running.
    func pauseMonitors() {
        guard isStarted, !isPaused else { return }
        isPaused = true
        eventSoon?.cancel()
        for feature in runningFeatures where feature.isBackgroundMonitor { stopFeature(feature) }
    }

    /// Restarts the enabled monitors once the notch can show again; each refreshes on start.
    func resumeMonitors() {
        guard isStarted, isPaused else { return }
        isPaused = false
        for feature in FeatureFlag.allCases where feature.isBackgroundMonitor && isEnabled(feature) {
            startFeature(feature)
        }
    }

    private func featureChanged(_ feature: FeatureFlag, enabled: Bool) {
        if isStarted {
            if !enabled { stopFeature(feature) }
            else if !isPaused || !feature.isBackgroundMonitor { startFeature(feature) }
        }
        onFeatureToggled?(feature, enabled)
    }

    private func startFeature(_ feature: FeatureFlag) {
        guard runningFeatures.insert(feature).inserted else { return }
        Self.log.notice("started \(feature.rawValue, privacy: .public)")
        switch feature {
        case .nowPlaying: nowPlaying.start()
        case .battery: battery.start()
        case .timer, .stopwatch: break          // no background source; they only run when used
        case .calendar: calendar.start()
        case .recording: recording.start()
        case .downloads: downloads.start()
        }
    }

    /// Stops the feature completely: listeners removed, timers and tasks cancelled, state cleared.
    private func stopFeature(_ feature: FeatureFlag) {
        guard runningFeatures.remove(feature) != nil else { return }
        Self.log.notice("stopped \(feature.rawValue, privacy: .public)")
        switch feature {
        case .nowPlaying: nowPlaying.stop()
        case .battery: battery.stop()
        case .timer: timer.stop()
        case .stopwatch: stopwatch.stop()
        case .calendar: calendar.stop()
        case .recording: recording.stop()
        case .downloads: downloads.stop()
        }
    }

    /// Compact notch priority: a live countdown, then a stopwatch, then music (playing or paused).
    /// Battery only shows while it is the selected feature, to keep the compact notch uncluttered.
    func compactActivity(selected: IslandContent) -> CompactActivity? {
        if let pinned = pinnedActivity() { return pinned }
        if isEnabled(.timer), timer.model.isActive { return .timer }
        if isEnabled(.stopwatch), stopwatch.model.hasElapsed { return .stopwatch }
        // A paused track keeps its artwork in the compact notch (the soundwave settles); it clears on stop or quit.
        if isEnabled(.nowPlaying), nowPlaying.snapshot != nil { return .nowPlaying }
        if isEnabled(.battery), selected == .battery, battery.state.hasBattery { return .battery }
        return nil
    }

    /// The feature the user prefers in compact, if it has something to show right now. Otherwise the
    /// automatic order applies. Recording dots are drawn separately and are never affected.
    private func pinnedActivity() -> CompactActivity? {
        switch settings.effectiveCompactPreference {
        case .automatic:
            return nil
        case .nowPlaying:
            return nowPlaying.snapshot != nil ? .nowPlaying : nil
        case .downloads:
            return downloads.isAvailable && downloads.primary != nil ? .download : nil
        case .calendar:
            return calendar.access == .authorized && calendar.nextEvent != nil ? .calendar : nil
        case .timerStopwatch:
            if isEnabled(.timer), timer.model.isActive { return .timer }
            if isEnabled(.stopwatch), stopwatch.model.hasElapsed { return .stopwatch }
            return nil
        }
    }
}
