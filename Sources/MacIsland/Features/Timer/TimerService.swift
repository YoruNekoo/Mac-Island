import AppKit
import Observation
import UserNotifications

/// Pure countdown logic. Remaining time is derived from a monotonic deadline, not from ticks.
struct CountdownModel: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case running(deadline: ContinuousClock.Instant)
        case paused(remaining: Duration)
        case finished
    }

    private(set) var phase: Phase = .idle

    var isActive: Bool { phase != .idle }

    func remaining(at now: ContinuousClock.Instant) -> Duration {
        switch phase {
        case .idle, .finished: .zero
        case .paused(let remaining): remaining
        case .running(let deadline): max(.zero, deadline - now)
        }
    }

    /// Returns `false` (and does nothing) for a zero or negative duration.
    @discardableResult
    mutating func start(total: Duration, at now: ContinuousClock.Instant) -> Bool {
        guard total > .zero else { return false }
        phase = .running(deadline: now + total)
        return true
    }

    mutating func pause(at now: ContinuousClock.Instant) {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining(at: now))
    }

    mutating func resume(at now: ContinuousClock.Instant) {
        guard case .paused(let remaining) = phase, remaining > .zero else { return }
        phase = .running(deadline: now + remaining)
    }

    mutating func reset() { phase = .idle }

    /// Moves to `.finished` once the deadline has passed. Returns whether it just finished.
    @discardableResult
    mutating func finishIfElapsed(at now: ContinuousClock.Instant) -> Bool {
        guard case .running(let deadline) = phase, now >= deadline else { return false }
        phase = .finished
        return true
    }
}

enum TimerUnit: CaseIterable, Sendable {
    case hours, minutes, seconds

    var range: ClosedRange<Int> { self == .hours ? 0...99 : 0...59 }
    /// What VoiceOver calls the field.
    var fullName: String {
        switch self {
        case .hours: "Hours"
        case .minutes: "Minutes"
        case .seconds: "Seconds"
        }
    }
    var label: String {
        switch self {
        case .hours: "hr"
        case .minutes: "min"
        case .seconds: "sec"
        }
    }
}

@MainActor
@Observable
final class TimerService {
    private(set) var model = CountdownModel()
    private(set) var hours = 0
    private(set) var minutes = 5
    private(set) var seconds = 0

    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private let notifier = TimerNotifier()

    var total: Duration { .seconds(hours * 3600 + minutes * 60 + seconds) }
    var canStart: Bool { total > .zero }

    func value(for unit: TimerUnit) -> Int {
        switch unit {
        case .hours: hours
        case .minutes: minutes
        case .seconds: seconds
        }
    }

    /// Clamps to the unit's valid range, so invalid durations cannot be entered.
    func adjust(_ unit: TimerUnit, by delta: Int) {
        guard !model.isActive else { return }
        let value = min(unit.range.upperBound, max(unit.range.lowerBound, self.value(for: unit) + delta))
        switch unit {
        case .hours: hours = value
        case .minutes: minutes = value
        case .seconds: seconds = value
        }
    }

    func start() {
        guard !model.isActive, model.start(total: total, at: .now) else { return }
        scheduleCompletion()
        Task { await notifier.prepare() }
    }

    func pause() {
        model.pause(at: .now)
        completionTask?.cancel()
    }

    func resume() {
        model.resume(at: .now)
        scheduleCompletion()
    }

    func reset() {
        completionTask?.cancel()
        model.reset()
    }

    /// Turning the feature off: cancel the pending completion and clear the countdown.
    func stop() { reset() }

    /// One sleeping task aimed at the monotonic deadline; always replaced, never duplicated.
    private func scheduleCompletion() {
        completionTask?.cancel()
        guard case .running(let deadline) = model.phase else { return }
        completionTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: ContinuousClock())
            guard !Task.isCancelled else { return }
            self?.complete()
        }
    }

    private func complete() {
        if model.finishIfElapsed(at: .now) {
            notifier.notifyFinished()
        } else {
            scheduleCompletion()
        }
    }
}

/// Notification permission is requested only when a timer is first started.
@MainActor
final class TimerNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var didPrepare = false

    private var center: UNUserNotificationCenter? {
        // UserNotifications crashes when run outside an app bundle (e.g. `swift run`).
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func prepare() async {
        guard !didPrepare, let center else { return }
        didPrepare = true
        center.delegate = self
        _ = try? await center.requestAuthorization(options: [.alert])
    }

    func notifyFinished() {
        NSSound(named: "Glass")?.play()
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = "Your countdown has reached zero."
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner]
    }
}
