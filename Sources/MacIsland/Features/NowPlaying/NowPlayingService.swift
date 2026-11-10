import AppKit
import Observation

/// Tracks playback across Apple Music and Spotify.
///
/// - Track and play-state changes arrive as distributed notifications. Nothing polls for them.
/// - Position is an anchor (position + timestamp) interpolated locally. It is re-read from the player on every
///   notification, on expand, and, only while the Now Playing tab is visible and playing, every 5 s.
/// - Artwork is fetched once per track change and cached; its color is computed once per track.
/// - Every Apple Event is guarded by "is the app running" inside the provider, so a closed player is never launched.
@MainActor
@Observable
final class NowPlayingService {
    private(set) var snapshot: NowPlayingSnapshot?
    /// nil when the duration is unknown or zero (streams, some podcasts) or the track is an advert.
    private(set) var progress: PlaybackProgress?
    private(set) var artwork: CGImage?
    private(set) var artworkColor: ArtworkColor?
    private(set) var notice: NowPlayingNotice?
    /// How playing or paused the artwork and soundwave look. One value drives both.
    private(set) var visual = PlaybackVisual.initial

    @ObservationIgnored private let providers: [any NowPlayingProvider]
    @ObservationIgnored private var snapshotsByProvider: [String: NowPlayingSnapshot] = [:]
    @ObservationIgnored private var lastUpdatedProviderID: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?  // re-reads the position after sleep
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var resyncTask: Task<Void, Never>?
    @ObservationIgnored private var loadedArtworkKey: String?
    @ObservationIgnored private var artworkCache: [String: ProcessedArtwork] = [:]
    @ObservationIgnored private var artworkCacheOrder: [String] = []
    /// Providers whose Automation permission was refused. They get no Apple Events until the user opens the
    /// tab again, so a denial neither spams scripts nor re-prompts.
    @ObservationIgnored private var deniedProviderIDs: Set<String> = []

    /// Called when a different track starts playing (not for pause/resume of the same track).
    @ObservationIgnored var onTrackChange: (@MainActor () -> Void)?

    /// True between `start()` and `stop()`: observers are registered.
    var isRunning: Bool { !observers.isEmpty }
    /// Set by `stop()` so results of Apple Events still in flight cannot repopulate a stopped service.
    @ObservationIgnored private var isStopped = false

    /// How long Mac Island waits for the player to confirm its own play/pause before re-reading the player.
    static let optimisticConfirmationTimeout: Duration = .milliseconds(1500)
    var confirmationTimeout = NowPlayingService.optimisticConfirmationTimeout

    /// A play/pause Mac Island sent, shown immediately and not yet confirmed by the player.
    private struct PendingToggle {
        let id = UUID()
        let providerID: String
        let trackKey: String
        let expected: PlaybackStatus
        /// What the player last really told us, to fall back to.
        var confirmed: NowPlayingSnapshot
    }
    /// Commands are sent one after another, in the order they were issued.
    @ObservationIgnored private var lastCommand: Task<Void, Never>?
    @ObservationIgnored private var pending: PendingToggle?
    @ObservationIgnored private var pendingTimeout: Task<Void, Never>?

    /// While the tab is visible and music is playing, re-read the position at most this often.
    var resyncInterval: Duration = .seconds(5)
    static let artworkCacheLimit = 8

    init(providers: [any NowPlayingProvider] = [ScriptableMusicProvider.appleMusic, ScriptableMusicProvider.spotify]) {
        self.providers = providers
    }

    func start() {
        guard observers.isEmpty else { return }
        isStopped = false
        for provider in providers {
            let providerID = provider.id
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: provider.playerInfoNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let update = provider.parse(userInfo: notification.userInfo)
                MainActor.assumeIsolated { self?.apply(update, providerID: providerID) }
            }
            observers.append(observer)
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated { self?.applicationTerminated(bundleID: bundleID) }
        }
        // The position was extrapolated across sleep; read the real one from the player once.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resyncPosition() }
        }
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        isStopped = true
        clearPending()
        lastCommand = nil
        // Forget everything, so the compact and expanded views have nothing left to show.
        snapshotsByProvider.removeAll()
        lastUpdatedProviderID = nil
        deniedProviderIDs.removeAll()
        notice = nil
        isVisible = false
        recomputeSnapshot()                 // clears snapshot, progress and artwork and cancels their tasks
        artworkTask?.cancel()
        resyncTask?.cancel()
        resyncTask = nil
    }

    /// Called by the Now Playing view when the expanded tab appears or disappears.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            deniedProviderIDs.removeAll()      // one fresh attempt: a granted permission is picked up here
            if snapshot == nil {
                discoverRunningPlayers()
            } else {
                resyncPosition()
            }
        }
        updateResyncLoop()
    }

    /// Sends a command to the player. Play/pause is shown at once (optimistic) and reconciled with the player's
    /// own notification; if none confirms it within `confirmationTimeout`, the player is re-read once and the
    /// UI follows what it says. Next and previous have nothing to show early: the new track arrives normally.
    func send(_ command: PlaybackCommand) {
        guard let provider = activeProvider, !deniedProviderIDs.contains(provider.id) else { return }
        if command == .playPause { applyOptimisticToggle(for: provider) }
        let previous = lastCommand
        lastCommand = Task { [weak self] in
            await previous?.value
            do {
                try await provider.send(command)
                self?.succeeded(provider.id)
            } catch {
                self?.handle(error, providerID: provider.id)
                if command == .playPause { self?.revertOptimisticToggle(providerID: provider.id) }
            }
        }
    }

    /// One seek command, sent when a scrub ends or the bar is tapped. The bar updates immediately; the real
    /// position is read back shortly after.
    func seek(to seconds: TimeInterval) {
        guard var current = progress, let provider = activeProvider, !deniedProviderIDs.contains(provider.id) else { return }
        let target = min(max(seconds, 0), current.duration)
        current.anchorPosition = target
        current.anchorDate = Date()
        progress = current
        Task { [weak self] in
            do {
                try await provider.seek(to: target)
                self?.succeeded(provider.id)
                try? await Task.sleep(for: .milliseconds(400))
                self?.resyncPosition()
            } catch {
                self?.handle(error, providerID: provider.id)
            }
        }
    }

    // MARK: - Updates

    func apply(_ update: ProviderUpdate, providerID: String) {
        guard !isStopped else { return }
        if let pendingToggle = pending, pendingToggle.providerID == providerID {
            switch update {
            case .ignored:
                return
            case .stopped:
                clearPending()
            case .track(let incoming):
                if incoming.trackKey == pendingToggle.trackKey, incoming.status != pendingToggle.expected {
                    // Same track, opposite state: a stale or unrelated notification (a position update, say).
                    // Keep showing the optimistic state, but remember it as the real state to fall back to.
                    pending?.confirmed = incoming
                    return
                }
                clearPending()      // confirmed, or the player moved on to another track: the player's word wins
            }
        }
        switch update {
        case .ignored:
            return
        case .stopped:
            snapshotsByProvider[providerID] = nil
        case .track(let newSnapshot):
            snapshotsByProvider[providerID] = newSnapshot
            lastUpdatedProviderID = providerID
        }
        recomputeSnapshot()
    }

    // MARK: - Optimistic play/pause

    private func applyOptimisticToggle(for provider: any NowPlayingProvider) {
        guard let shown = snapshotsByProvider[provider.id] else { return }
        let expected: PlaybackStatus = shown.status == .playing ? .paused : .playing
        let confirmed = pending?.providerID == provider.id ? (pending?.confirmed ?? shown) : shown
        pendingTimeout?.cancel()
        let toggle = PendingToggle(providerID: provider.id, trackKey: shown.trackKey, expected: expected, confirmed: confirmed)
        pending = toggle

        var optimistic = shown
        optimistic.status = expected
        optimistic.positionHint = nil          // the old hint is stale; the local clock carries the position
        snapshotsByProvider[provider.id] = optimistic
        lastUpdatedProviderID = provider.id
        recomputeSnapshot()

        pendingTimeout = Task { [weak self, id = toggle.id] in
            try? await Task.sleep(for: self?.confirmationTimeout ?? NowPlayingService.optimisticConfirmationTimeout)
            guard !Task.isCancelled else { return }
            await self?.confirmationTimedOut(id: id, provider: provider)
        }
    }

    /// No confirming notification arrived in time: re-read the player once and follow it.
    private func confirmationTimedOut(id: UUID, provider: any NowPlayingProvider) async {
        guard let toggle = pending, toggle.id == id else { return }
        let reread: NowPlayingSnapshot?
        do { reread = try await provider.querySnapshot() } catch {
            handle(error, providerID: provider.id)
            reread = nil
        }
        guard let current = pending, current.id == id else { return }   // a notification settled it meanwhile
        clearPending()
        apply(.track(reread ?? current.confirmed), providerID: provider.id)
    }

    /// The command itself failed: go back to the last real state at once.
    private func revertOptimisticToggle(providerID: String) {
        guard let toggle = pending, toggle.providerID == providerID else { return }
        clearPending()
        apply(.track(toggle.confirmed), providerID: providerID)
    }

    private func clearPending() {
        pending = nil
        pendingTimeout?.cancel()
        pendingTimeout = nil
    }

    private func applicationTerminated(bundleID: String?) {
        guard let provider = providers.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        snapshotsByProvider[provider.id] = nil
        recomputeSnapshot()
    }

    /// If both players are running, show the one that is playing; if both are playing (or neither), the one
    /// that changed most recently.
    private func recomputeSnapshot() {
        let playing = snapshotsByProvider.values.filter { $0.status == .playing }
        let recent = lastUpdatedProviderID.flatMap { snapshotsByProvider[$0] }
        let next: NowPlayingSnapshot?
        if playing.count > 1 {
            next = recent.flatMap { $0.status == .playing ? $0 : nil } ?? playing.first
        } else {
            next = playing.first ?? recent ?? snapshotsByProvider.values.first
        }
        let previous = snapshot
        if next != snapshot { snapshot = next }
        if let next, next.status == .playing, next.trackKey != previous?.trackKey { onTrackChange?() }

        updateVisual(next: next, previous: previous)
        updateProgress(from: next, previous: previous)
        if next?.trackKey != loadedArtworkKey {
            artworkTask?.cancel()
            artwork = nil
            artworkColor = nil
            loadedArtworkKey = nil
        }
        if let next { loadArtworkIfNeeded(for: next) }
        updateResyncLoop()
    }

    /// Keeps the shared playback visual in step with the status. Music appearing for the first time starts settled
    /// (nothing to animate); a new track while paused changes nothing, so it shows paused at once.
    private func updateVisual(next: NowPlayingSnapshot?, previous: NowPlayingSnapshot?) {
        guard let next else {
            visual = .initial
            return
        }
        let isPlaying = next.status == .playing
        if previous == nil {
            visual = .settled(isPlaying: isPlaying)
        } else if isPlaying != visual.isPlaying {
            visual = visual.changing(isPlaying: isPlaying, at: Date())
        }
    }

    // MARK: - Progress

    private func updateProgress(from next: NowPlayingSnapshot?, previous: NowPlayingSnapshot?) {
        guard let next, !next.isAdvert, let duration = next.duration, duration > 0 else {
            progress = nil
            if next != nil { resyncPosition() }    // the player may still report a length
            return
        }
        let now = Date()
        let sameTrack = previous?.trackKey == next.trackKey
        let estimate = next.positionHint ?? (sameTrack ? progress?.position(at: now) : nil) ?? 0
        progress = PlaybackProgress(duration: duration, anchorPosition: estimate, anchorDate: now,
                                    isPlaying: next.status == .playing)
        resyncPosition()
    }

    /// Reads the real position (and length) from the player once.
    func resyncPosition() {
        guard let snapshot, !snapshot.isAdvert,
              let provider = providers.first(where: { $0.id == snapshot.providerID }),
              !deniedProviderIDs.contains(provider.id) else { return }
        let key = snapshot.trackKey
        let requestedAt = Date()
        Task { [weak self] in
            do {
                guard let timing = try await provider.fetchTiming() else { return }
                self?.applyTiming(timing, trackKey: key, requestedAt: requestedAt)
                self?.succeeded(provider.id)
            } catch {
                self?.handle(error, providerID: provider.id)
            }
        }
    }

    private func applyTiming(_ timing: PlaybackTiming, trackKey: String, requestedAt: Date) {
        guard let snapshot, snapshot.trackKey == trackKey, !snapshot.isAdvert else { return }
        let duration = timing.duration ?? progress?.duration ?? snapshot.duration
        guard let duration, duration > 0 else { progress = nil; return }
        // The player answered roughly halfway through the round trip.
        let anchor = Date(timeIntervalSince1970: (requestedAt.timeIntervalSince1970 + Date().timeIntervalSince1970) / 2)
        let updated = PlaybackProgress(duration: duration, anchorPosition: min(timing.position, duration),
                                       anchorDate: anchor, isPlaying: snapshot.status == .playing)
        if updated != progress { progress = updated }
    }

    /// The 5 s resync loop exists only while the tab is visible and music is playing. Paused, compact, or
    /// nothing playing: no timer at all.
    private func updateResyncLoop() {
        let shouldRun = isVisible && snapshot?.status == .playing && progress != nil
        if shouldRun, resyncTask == nil {
            resyncTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let interval = self?.resyncInterval else { return }
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    self?.resyncPosition()
                }
            }
        } else if !shouldRun {
            resyncTask?.cancel()
            resyncTask = nil
        }
    }

    // MARK: - Discovery and artwork

    private func discoverRunningPlayers() {
        Task { [weak self, providers] in
            for provider in providers where provider.isRunning {
                guard self?.deniedProviderIDs.contains(provider.id) == false else { continue }
                do {
                    if let found = try await provider.querySnapshot() {
                        self?.apply(.track(found), providerID: provider.id)
                    }
                    self?.succeeded(provider.id)
                } catch {
                    self?.handle(error, providerID: provider.id)
                }
            }
        }
    }

    /// Once per track change (cached afterwards). Runs whether or not the tab is visible, because the compact
    /// notch shows the artwork.
    private func loadArtworkIfNeeded(for snapshot: NowPlayingSnapshot) {
        let key = snapshot.trackKey
        guard key != loadedArtworkKey else { return }
        if let cached = artworkCache[key] {
            show(cached, key: key)
            return
        }
        guard let provider = providers.first(where: { $0.id == snapshot.providerID }),
              !deniedProviderIDs.contains(provider.id) else { return }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            // Music can need a moment to have the artwork ready, so try once more after a second.
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
                guard !Task.isCancelled, self?.snapshot?.trackKey == key else { return }
                do {
                    if let data = try await provider.fetchArtwork(), let processed = await ArtworkProcessor.process(data) {
                        guard !Task.isCancelled, self?.snapshot?.trackKey == key else { return }
                        self?.remember(processed, key: key)
                        self?.show(processed, key: key)
                        self?.succeeded(provider.id)
                        return
                    }
                } catch {
                    self?.handle(error, providerID: provider.id)
                    return
                }
            }
        }
    }

    private func show(_ processed: ProcessedArtwork, key: String) {
        artwork = processed.image
        artworkColor = processed.color
        loadedArtworkKey = key
    }

    private func remember(_ processed: ProcessedArtwork, key: String) {
        artworkCache[key] = processed
        artworkCacheOrder.removeAll { $0 == key }
        artworkCacheOrder.append(key)
        while artworkCacheOrder.count > Self.artworkCacheLimit {
            artworkCache[artworkCacheOrder.removeFirst()] = nil
        }
    }

    /// Whether a play/pause/next/previous command can reach a running player right now: a track is known, its
    /// player is still running, and its Automation permission was not refused.
    var canControlPlayback: Bool {
        guard let provider = activeProvider else { return false }
        return provider.isRunning && !deniedProviderIDs.contains(provider.id)
    }

    private var activeProvider: (any NowPlayingProvider)? {
        guard let id = snapshot?.providerID else { return nil }
        return providers.first { $0.id == id }
    }

    private func succeeded(_ providerID: String) {
        deniedProviderIDs.remove(providerID)
        if deniedProviderIDs.isEmpty, notice != nil { notice = nil }
    }

    private func handle(_ error: Error, providerID: String) {
        if let scriptError = error as? AppleScriptError, scriptError == .notAuthorized {
            deniedProviderIDs.insert(providerID)
            notice = .automationDenied
        }
        // Other failures (app quit mid-request, missing artwork) are expected and non-fatal.
    }
}
