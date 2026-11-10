import AppKit
import IOKit.ps
import Observation

/// Reads battery info through the public IOKit Power Sources API. Updates are event-driven via a
/// run-loop source that fires when power-source info changes, so there is no polling.
@MainActor
@Observable
final class BatteryService {
    private(set) var state = BatteryState.noBattery

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var bridge: BatteryEventBridge?
    @ObservationIgnored private var estimator = BatteryEstimator()
    @ObservationIgnored private var isVisible = false
    /// Source of raw readings. Injectable so transitions can be scripted in tests; defaults to IOKit.
    @ObservationIgnored var readingProvider: @MainActor @Sendable () -> BatteryReading = { BatteryService.readCurrent() }
    @ObservationIgnored private var sleepWakeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var wakeRefreshTask: Task<Void, Never>?

    /// Called once when the Mac goes from battery power to external power, with the new percentage. Never at
    /// start-up (the first read only records a baseline), never on unplug, never for repeated notifications.
    @ObservationIgnored var onPlugIn: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var hasBaseline = false

    /// Estimates are only re-read this often, and only while the battery view is on screen.
    static let visibleRefreshInterval: Duration = .seconds(30)

    var isRunning: Bool { runLoopSource != nil }

    func start() {
        guard runLoopSource == nil else { return }
        hasBaseline = false      // whatever the power state is now is the starting point, not a plug-in
        refresh()

        // The callback runs on the main run loop (the source is added to it below), so refresh
        // synchronously instead of hopping through a Task, which could reorder back-to-back events.
        let bridge = BatteryEventBridge { [weak self] in
            MainActor.assumeIsolated { self?.handlePowerSourceEvent() }
        }
        self.bridge = bridge
        let context = Unmanaged.passUnretained(bridge).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<BatteryEventBridge>.fromOpaque(context).takeUnretainedValue().fire()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }

        let center = NSWorkspace.shared.notificationCenter
        sleepWakeObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetHistory() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWake() }
            },
        ]
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        bridge = nil
        sleepWakeObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepWakeObservers = []
        refreshTask?.cancel()
        wakeRefreshTask?.cancel()
        hasBaseline = false
    }

    /// While visible: refresh now and keep the *time estimate* fresh. When hidden: no timer at all.
    /// The timer only calls `refresh()`, which derives the status label from the new snapshot alone,
    /// so it can never hold or delay that label.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        restartEstimateRefresh()
        if visible { refresh() }
    }

    private func restartEstimateRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        guard isVisible else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.visibleRefreshInterval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// A Power Sources notification arrived: re-read and publish immediately, and restart the
    /// estimate timer (cancelled on every power-source change).
    func handlePowerSourceEvent() {
        refresh()
        restartEstimateRefresh()
    }

    /// Reads one snapshot and derives *everything* (label, icon, estimate) from it alone.
    func refresh() {
        let reading = readingProvider()
        let power = PowerStatus.from(reading)
        let estimate = estimator.estimate(for: reading, power: power, at: .now)
        let newState = BatteryState(hasBattery: reading.hasBattery, percent: reading.percent,
                                    power: power, estimate: estimate)
        let wasOnBattery = state.power == .onBattery
        if newState != state { state = newState }
        if hasBaseline, wasOnBattery, power.isExternalPowerConnected { onPlugIn?(newState.percent) }
        hasBaseline = true
    }

    private func resetHistory() {
        estimator.reset()
    }

    /// After wake the system recomputes its estimate, so drop history and read again now and shortly after.
    private func handleWake() {
        resetHistory()
        refresh()
        wakeRefreshTask?.cancel()
        wakeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Public Power Sources API only (IOKit.ps).
    static func readCurrent() -> BatteryReading {
        let none = BatteryReading(hasBattery: false, percent: 0, isExternalPower: true, isCharged: false, providesTimeRemaining: false, systemTimeToEmptyMinutes: nil,
                                  descriptionTimeToEmptyMinutes: nil, timeToFullMinutes: nil)
        // One info snapshot feeds every value below, so they are mutually consistent.
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return none }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded()))) : 0

            // IOPSGetTimeRemainingEstimate: seconds, or -1 (unknown) / -2 (unlimited, on AC power).
            let systemSeconds = IOPSGetTimeRemainingEstimate()
            let systemMinutes = systemSeconds > 0 ? Int((systemSeconds / 60).rounded(.up)) : nil

            // "Power Source State" is the only authority for plugged in vs. on battery. "Is Charging" is
            // deliberately not read: it lags the real power state. (The providing-source value is only a
            // fallback if the key is missing.)
            let isExternal: Bool
            if let sourceState = description[kIOPSPowerSourceStateKey] as? String {
                isExternal = sourceState == kIOPSACPowerValue
            } else {
                isExternal = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSACPowerValue
            }

            return BatteryReading(
                hasBattery: true,
                percent: percent,
                isExternalPower: isExternal,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                providesTimeRemaining: description["Battery Provides Time Remaining"] as? Bool ?? true,
                systemTimeToEmptyMinutes: systemMinutes,
                descriptionTimeToEmptyMinutes: description[kIOPSTimeToEmptyKey] as? Int,
                timeToFullMinutes: description[kIOPSTimeToFullChargeKey] as? Int)
        }
        return none
    }
}

/// Lets the C callback reach Swift without capturing context.
private final class BatteryEventBridge: @unchecked Sendable {
    private let handler: @Sendable () -> Void
    init(handler: @escaping @Sendable () -> Void) { self.handler = handler }
    func fire() { handler() }
}
