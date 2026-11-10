import Observation

/// Pure stopwatch logic. Time is always passed in, so elapsed time derives from a monotonic clock
/// reading (`ContinuousClock`, which keeps counting through system sleep) and never from accumulated ticks.
struct StopwatchModel: Equatable, Sendable {
    private(set) var accumulated: Duration = .zero
    private(set) var runningSince: ContinuousClock.Instant?

    var isRunning: Bool { runningSince != nil }
    var hasElapsed: Bool { isRunning || accumulated > .zero }

    func elapsed(at now: ContinuousClock.Instant) -> Duration {
        guard let runningSince else { return accumulated }
        return accumulated + (now - runningSince)
    }

    mutating func start(at now: ContinuousClock.Instant) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    mutating func pause(at now: ContinuousClock.Instant) {
        guard runningSince != nil else { return }
        accumulated = elapsed(at: now)
        runningSince = nil
    }

    mutating func reset() {
        accumulated = .zero
        runningSince = nil
    }
}

@MainActor
@Observable
final class StopwatchService {
    private(set) var model = StopwatchModel()

    func start() { model.start(at: .now) }
    func pause() { model.pause(at: .now) }
    func reset() { model.reset() }
    /// Turning the feature off clears the stopwatch.
    func stop() { reset() }
    func toggle() { model.isRunning ? pause() : start() }
}
