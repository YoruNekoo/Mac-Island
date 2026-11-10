import AppKit
import SwiftUI

/// Owns the single island panel and all interaction logic.
///
/// The panel never resizes: it is as large as the biggest possible notch, top-centered, and only the
/// SwiftUI shape inside it animates. `PanelClickThrough` makes everything outside the visible shape
/// transparent to the mouse.
@MainActor
final class IslandController {
    let state = IslandState()
    let features: IslandFeatureStore
    private let metrics = IslandMetrics.standard
    private let settings: AppSettings
    private(set) var panel: IslandPanel?
    /// The connected displays. A test seam: tests inject fake screens (notched, external, removed).
    var displayProvider: @MainActor () -> [IslandPositionManager.Display] = IslandPositionManager.connectedDisplays
    private var clickThrough: PanelClickThrough?
    private var screenObserver: NSObjectProtocol?
    private let autoCollapseScheduler = AutoCollapseScheduler()
    private let outsideClickMonitor = OutsideClickMonitor()
    private var lastToggle: ContinuousClock.Instant?
    private var hover: HoverTracker?
    /// Settable so tests can substitute a spy performer.
    var haptics: HapticFeedback?
    private var swipeTracker = SwipeGestureTracker()
    private var nudgeTask: Task<Void, Never>?
    private var chargingFlashTask: Task<Void, Never>?
    private var lastChargingFlash: ContinuousClock.Instant?
    private var currentDisplayID: CGDirectDisplayID?
    private var isStarted = false
    /// No display without a camera notch is connected, so the panel is ordered out.
    private(set) var isHiddenForNotch = false
    private var lastFollowCheck: ContinuousClock.Instant?
    private var lastTransitionAt: ContinuousClock.Instant?
    private var bounceTask: Task<Void, Never>?
    private var coalesceTask: Task<Void, Never>?
    /// How many arrival bounces have actually played (for tests and diagnostics).
    private(set) var bounceCount = 0

    init(settings: AppSettings, features: IslandFeatureStore? = nil) {
        self.settings = settings
        let store = features ?? IslandFeatureStore(settings: settings)
        self.features = store
        // A feature was switched on or off: keep what the notch shows consistent with what is enabled.
        store.onFeatureToggled = { [weak self] feature, enabled in
            self?.reconcileContent()
            if feature == .battery, !enabled { self?.endChargingFlash(animated: true) }
        }
        store.onArrival = { [weak self] _ in self?.requestBounce() }
        store.onPlugIn = { [weak self] percent in self?.handlePlugIn(percent: percent) }
        settings.onAppearanceChange = { [weak self] in self?.appearanceChanged() }
        haptics = HapticFeedback(isEnabled: { [weak self] in self?.settings.hapticsEnabled ?? false })
        hover = HoverTracker { [weak self] in self?.setExpanded(true) }
    }

    func show() {
        guard !isStarted else { return } // never create a second panel or observer
        isStarted = true
        features.start()
        reconcileContent()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionPanel() }
        }
        repositionPanel()
    }

    /// Creates the one panel and its click-through monitors on the first display that can show it.
    private func createPanel(frame: CGRect) {
        let panel = IslandPanel(contentRect: frame)
        let view = IslandView(state: state, metrics: metrics, features: features, actions: makeActions())
        let host = IslandHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        let clickThrough = PanelClickThrough(panel: panel) { [weak self] in self?.visibleShape ?? (.zero, 0) }
        clickThrough.onPointerMove = { [weak self] pointer in self?.handlePointerMove(pointer) }
        clickThrough.onScroll = { [weak self] sample in self?.handleScroll(sample) }
        clickThrough.start()
        self.clickThrough = clickThrough
    }

    /// Only displays with a camera notch are connected: collapse, hide the panel, stop the pointer monitors
    /// and pause the background feature monitors. The menu bar icon stays.
    private func hideForNotchedDisplays() {
        guard !isHiddenForNotch else { return }
        isHiddenForNotch = true
        settings.isHiddenOnNotchedDisplay = true
        setExpanded(false)
        endChargingFlash(animated: false)
        cancelBounce()
        hover?.cancel()
        clickThrough?.stop()
        panel?.orderOut(nil)
        currentDisplayID = nil
        features.pauseMonitors()
    }

    /// A display without a notch is available again: show the panel and resume what was paused.
    private func unhide() {
        guard isHiddenForNotch else { return }
        isHiddenForNotch = false
        settings.isHiddenOnNotchedDisplay = false
        panel?.orderFrontRegardless()
        clickThrough?.start()
        features.resumeMonitors()
        reconcileContent()
    }

    func tearDown() {
        isStarted = false
        endChargingFlash(animated: false)
        nudgeTask?.cancel()
        cancelBounce()
        hover?.cancel()
        autoCollapseScheduler.cancel()
        outsideClickMonitor.stop()
        clickThrough?.stop()
        clickThrough = nil
        features.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Menu bar actions

    var isExpanded: Bool { state.isExpanded }
    /// Expanding needs at least one tab to show; collapsing is always possible.
    var canToggleExpanded: Bool { !isHiddenForNotch && (state.isExpanded || !features.visibleTabs.isEmpty) }
    var canControlPlayback: Bool { features.isEnabled(.nowPlaying) && features.nowPlaying.canControlPlayback }

    func toggleExpandedFromMenu() {
        guard canToggleExpanded else { return }
        setExpanded(!state.isExpanded)
    }

    func sendPlayback(_ command: PlaybackCommand) {
        guard canControlPlayback else { return }
        features.nowPlaying.send(command)
    }

    // MARK: - Public interaction API

    func setExpanded(_ expanded: Bool) {
        guard expanded != state.isExpanded else { return }
        autoCollapseScheduler.cancel()
        lastTransitionAt = ContinuousClock.now
        cancelBounce()      // never bounce while expanded or while the size is changing
        if expanded { endChargingFlash(animated: false) }
        // The panel never resizes, so the state can change immediately and SwiftUI animates the shape.
        state.isExpanded = expanded
        if expanded {
            haptics?.play(.expand)
            hover?.cancel()
            outsideClickMonitor.start { [weak self] in self?.handleOutsideClick() }
            refreshAutoCollapse()
        } else {
            hover?.didCollapse()
            outsideClickMonitor.stop()
        }
        clickThrough?.refresh()
    }

    // MARK: - Interaction

    private func makeActions() -> IslandActions {
        IslandActions(
            toggle: { [weak self] in self?.handleToggleClick() },
            collapse: { [weak self] in self?.setExpanded(false) },
            interact: { [weak self] in self?.refreshAutoCollapse() },
            select: { [weak self] content in
                self?.state.content = content
                self?.refreshAutoCollapse()
            },
            reportContentSize: { [weak self] content, size in self?.applyContentSize(size, from: content) },
            pointerInside: { [weak self] inside in
                self?.state.isPointerInside = inside
                self?.refreshAutoCollapse()
            },
            haptic: { [weak self] kind in self?.haptics?.play(kind) }
        )
    }

    /// The selected feature reported its natural size: clamp it and let the shape animate to it.
    private func applyContentSize(_ size: CGSize, from content: IslandContent) {
        // Ignore a feature that is fading out.
        guard content == state.content, size.width > 0, size.height > 0 else { return }
        let clamped = metrics.clampedExpandedSize(forContent: size)
        guard clamped != state.expandedSize else { return }
        state.expandedSize = clamped
        clickThrough?.refresh()
    }

    /// Debounced so a double-click or click during a transition cannot flip the state back and forth.
    private func handleToggleClick() {
        let now = ContinuousClock.now
        if let lastToggle, now - lastToggle < IslandAnimations.toggleDebounce { return }
        lastToggle = now
        // With every tab feature turned off there is nothing to expand into.
        if !state.isExpanded, features.visibleTabs.isEmpty { return }
        setExpanded(!state.isExpanded)
    }

    /// If the selected feature is no longer enabled, move to the next enabled tab (same cross-fade and size
    /// spring as a manual switch), or collapse when none are left.
    private func reconcileContent() {
        let tabs = features.visibleTabs
        guard !tabs.contains(state.content) else { return }
        let all = IslandContent.allCases
        if let index = all.firstIndex(of: state.content),
           let next = (1..<all.count).lazy.map({ all[(index + $0) % all.count] }).first(where: tabs.contains) {
            state.content = next
            refreshAutoCollapse()
        } else if let first = tabs.first {
            state.content = first
        } else if state.isExpanded {
            setExpanded(false)
        }
    }

    /// A click landed in another app. Collapse, unless it was actually on the visible notch.
    private func handleOutsideClick() {
        guard !isPointerOverVisibleShape else { return }
        setExpanded(false)
    }

    /// (Re)starts the single auto-collapse timer, or cancels it when it should not run.
    private func refreshAutoCollapse() {
        let config = state.autoCollapse
        guard state.isExpanded, config.isEnabled else {
            autoCollapseScheduler.cancel()
            return
        }
        autoCollapseScheduler.restart(after: config.delay) { [weak self] in
            self?.autoCollapseDidFire()
        }
    }

    private func autoCollapseDidFire() {
        // Never collapse under the pointer; wait another full delay instead.
        if isPointerOverIsland {
            refreshAutoCollapse()
        } else {
            setExpanded(false)
        }
    }

    // MARK: - Visible shape

    /// The notch as it should be hit-tested right now (target size, not the panel).
    private var visibleShape: (size: CGSize, bottomRadius: CGFloat) {
        var size = metrics.size(expanded: state.isExpanded, expandedSize: state.expandedSize)
        if state.isBouncing, !state.isExpanded {
            // The click-through region covers the bounce's peak, so the overshoot is never "outside" the notch.
            size.width += ArrivalBounce.peak.width
            size.height += ArrivalBounce.peak.height
        }
        return (size, metrics.bottomRadius(expanded: state.isExpanded))
    }

    private var isPointerOverVisibleShape: Bool {
        clickThrough?.isInsideVisibleShape(NSEvent.mouseLocation) ?? false
    }

    /// `isPointerInside` comes from SwiftUI hover on the shape; the geometry check against the visible
    /// shape (never the panel frame) is a fallback in case hover events are not delivered.
    private var isPointerOverIsland: Bool {
        guard state.isExpanded else { return false }
        return state.isPointerInside || isPointerOverVisibleShape
    }

    // MARK: - Positioning

    private var isTransitioning: Bool {
        if state.isBouncing { return true }
        guard let lastTransitionAt else { return false }
        return ContinuousClock.now - lastTransitionAt < IslandAnimations.settleTime
    }

    /// The display the notch should be on, per the setting. Follow cursor never moves the notch while it
    /// is expanded or animating: it stays on its current display as long as that display is still connected.
    private func targetDisplay() -> IslandPositionManager.Display? {
        let displays = displayProvider()
        if settings.displaySelection == .followCursor, state.isExpanded || isTransitioning,
           let current = displays.first(where: { $0.id == currentDisplayID }) {
            return current
        }
        return IslandPositionManager.resolveDisplay(settings.displaySelection, among: displays,
                                                    cursor: NSEvent.mouseLocation, current: currentDisplayID)
    }

    /// The panel is always the maximum notch size, top-centered on the chosen display.
    private func panelFrame() -> CGRect? {
        guard let display = targetDisplay() else { return nil }
        currentDisplayID = display.id
        return IslandPositionManager.panelFrame(size: metrics.expandedMaxSize, screenFrame: display.frame)
    }

    /// Puts the panel on the right display, creating it on first use, or hides it when every connected
    /// display has a camera notch.
    private func repositionPanel() {
        guard isStarted else { return }
        guard let frame = panelFrame() else {
            hideForNotchedDisplays()
            return
        }
        if let panel {
            if panel.frame != frame { panel.setFrame(frame, display: true) }
        } else {
            createPanel(frame: frame)
        }
        unhide()
        clickThrough?.refresh()
    }

    // MARK: - Pointer: Follow cursor and Hover

    /// Fed by the click-through monitors (event-driven, no Accessibility permission).
    private func handlePointerMove(_ pointer: CGPoint) {
        followCursorIfNeeded()
        updateHover(pointer)
    }

    /// Moves the notch to the display under the cursor, but only while compact and settled, and at most
    /// ten checks a second.
    private func followCursorIfNeeded() {
        guard settings.displaySelection == .followCursor, !state.isExpanded, !isTransitioning else { return }
        let now = ContinuousClock.now
        if let lastFollowCheck, now - lastFollowCheck < .milliseconds(100) { return }
        lastFollowCheck = now
        let displays = displayProvider()
        guard let target = IslandPositionManager.resolveDisplay(.followCursor, among: displays, cursor: NSEvent.mouseLocation,
                                                                current: currentDisplayID),
              IslandPositionManager.shouldFollowCursor(selection: settings.displaySelection, isExpanded: state.isExpanded,
                                                       isTransitioning: isTransitioning, currentDisplayID: currentDisplayID,
                                                       targetDisplayID: target.id) else { return }
        repositionPanel()
    }

    /// Hover mode: resting on the visible shape for 0.25 s opens the notch. Only the shape counts, never
    /// the transparent panel area around it.
    private func updateHover(_ pointer: CGPoint) {
        guard settings.expandTrigger == .hover, !state.isExpanded else {
            hover?.cancel()
            return
        }
        hover?.pointerMoved(insideShape: clickThrough?.isInsideVisibleShape(pointer) ?? false)
    }

    /// A display, hover, compact or feel setting changed: re-apply what the controller owns.
    private func appearanceChanged() {
        if settings.expandTrigger == .click { hover?.cancel() }
        repositionPanel()
        if !settings.playfulAnimationsEnabled { cancelBounce() }
        if !settings.chargingAnimationEnabled { endChargingFlash(animated: true) }
        if !settings.swipeToSkipEnabled { swipeTracker.reset() }
    }

    // MARK: - Arrival bounce

    /// Asks for a bounce. Requests close together become one; the bounce is skipped while expanded, while
    /// the size is changing, when Reduce Motion is on, or when playful animations are off.
    func requestBounce() {
        guard settings.playfulAnimationsEnabled, coalesceTask == nil else { return }
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: ArrivalBounce.coalesceWindow)
            guard !Task.isCancelled, let self else { return }
            self.coalesceTask = nil
            self.performBounce()
        }
    }

    private func performBounce() {
        guard ArrivalBounce.canBounce(playfulEnabled: settings.playfulAnimationsEnabled,
                                      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                      isExpanded: state.isExpanded, isTransitioning: isTransitioning,
                                      isBouncing: state.isBouncing) else { return }
        state.isBouncing = true
        bounceCount += 1
        clickThrough?.refresh()
        withAnimation(IslandAnimations.bounceRise) { state.bounceDelta = ArrivalBounce.peak }
        bounceTask = Task { [weak self] in
            try? await Task.sleep(for: ArrivalBounce.riseDuration)
            guard !Task.isCancelled, let self else { return }
            withAnimation(IslandAnimations.bounceSettle) { self.state.bounceDelta = .zero }
            try? await Task.sleep(for: ArrivalBounce.settleDuration)
            guard !Task.isCancelled else { return }
            self.state.isBouncing = false
            self.clickThrough?.refresh()
        }
    }

    /// Stops any bounce at once and returns to exactly the resting size.
    private func cancelBounce() {
        bounceTask?.cancel()
        bounceTask = nil
        coalesceTask?.cancel()
        coalesceTask = nil
        if state.isBouncing || state.bounceDelta != .zero {
            state.bounceDelta = .zero
            state.isBouncing = false
        }
    }

    // MARK: - Charging flash

    /// The charger was plugged in. Shows the compact flash for 2.5 s, unless the notch is expanded, the
    /// feature is off, or one just played (at most one per 5 s). It never expands the notch.
    func handlePlugIn(percent: Int) {
        guard settings.chargingAnimationEnabled, features.isEnabled(.battery), !state.isExpanded else { return }
        let now = ContinuousClock.now
        if let lastChargingFlash, now - lastChargingFlash < ChargingFlash.minimumInterval { return }
        lastChargingFlash = now
        chargingFlashTask?.cancel()
        withAnimation(IslandAnimations.contentSwitch) { state.chargingFlash = ChargingFlash(percent: percent) }
        requestBounce()     // the existing arrival bounce: honors Playful animations and Reduce Motion
        chargingFlashTask = Task { [weak self] in
            try? await Task.sleep(for: ChargingFlash.duration)
            guard !Task.isCancelled else { return }
            self?.endChargingFlash(animated: true)
        }
    }

    private func endChargingFlash(animated: Bool) {
        chargingFlashTask?.cancel()
        chargingFlashTask = nil
        guard state.chargingFlash != nil else { return }
        if animated {
            withAnimation(IslandAnimations.contentSwitch) { state.chargingFlash = nil }
        } else {
            state.chargingFlash = nil
        }
    }

    // MARK: - Swipe to skip

    /// Now Playing is the feature on screen: its tab when expanded, or its artwork in compact.
    var isNowPlayingOnScreen: Bool {
        if state.isExpanded { return state.content == .nowPlaying }
        return state.chargingFlash == nil && features.compactActivity(selected: state.content) == .nowPlaying
    }

    private var isSwipeEligible: Bool {
        settings.swipeToSkipEnabled && features.isEnabled(.nowPlaying)
            && features.nowPlaying.snapshot != nil && isNowPlayingOnScreen
    }

    /// Fed by the scroll monitor, only for events on the visible shape.
    func handleScroll(_ sample: ScrollSample) {
        guard isSwipeEligible else {
            swipeTracker.reset()
            return
        }
        if let direction = swipeTracker.handle(sample) { performSwipe(direction) }
    }

    /// Skips with the existing 5B commands (which never launch a player), then gives feedback: a haptic
    /// tick and a small nudge of the artwork. The new track arrives through the normal 5B update.
    func performSwipe(_ direction: SwipeDirection) {
        features.nowPlaying.send(direction == .next ? .next : .previous)
        haptics?.play(.skip)
        nudgeArtwork(direction)
        refreshAutoCollapse()
    }

    private func nudgeArtwork(_ direction: SwipeDirection) {
        nudgeTask?.cancel()
        let sign: CGFloat = direction == .next ? -1 : 1       // the artwork moves the way the fingers did
        withAnimation(IslandAnimations.nudgeOut) { state.artworkNudge = sign * SwipeToSkip.nudgeDistance }
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(for: IslandAnimations.nudgeHold)
            guard !Task.isCancelled else { return }
            withAnimation(IslandAnimations.nudgeBack) { self?.state.artworkNudge = 0 }
        }
    }
}
