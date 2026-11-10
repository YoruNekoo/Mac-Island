import Foundation

/// Raw, unprocessed values read from the Power Sources API at one moment.
struct BatteryReading: Equatable, Sendable {
    var hasBattery: Bool
    var percent: Int
    /// External power, from `kIOPSPowerSourceStateKey` (the authority for plugged in vs. on battery).
    var isExternalPower: Bool
    /// Raw "Is Charged".
    var isCharged: Bool
    /// The "Battery Provides Time Remaining" flag. When false, macOS says its estimates are not valid yet.
    var providesTimeRemaining: Bool
    /// `IOPSGetTimeRemainingEstimate()`, the system-wide time-to-empty, converted to minutes.
    var systemTimeToEmptyMinutes: Int?
    /// "Time to Empty" from the power-source description, in minutes.
    var descriptionTimeToEmptyMinutes: Int?
    /// "Time to Full Charge" from the power-source description, in minutes.
    var timeToFullMinutes: Int?
}

/// Turns raw readings into a stable, honest estimate.
///
/// macOS' own estimate steps in coarse jumps (it moved 433 -> 443 min within seconds on the test Mac).
/// This type validates each value, smooths small fluctuations, adopts large changes immediately, and
/// rounds to a precision the data supports. It never invents a value: with no valid system estimate
/// it reports `.calculating`. Time is passed in so the logic is testable.
struct BatteryEstimator: Sendable {
    enum Mode: Equatable, Sendable { case discharging, charging }

    /// Weight of a new reading when blending with the running value.
    static let smoothingWeight = 0.3
    /// A reading this far (relative) from the running value is a real change: adopt it, do not blend.
    static let jumpThreshold = 0.25
    /// A temporarily missing estimate keeps the last value for at most this long.
    static let missingHold: Duration = .seconds(120)
    /// Samples further apart than this are not blended (e.g. after the app was idle).
    static let staleGap: Duration = .seconds(600)
    /// Plausible ranges; anything outside is treated as unavailable.
    static let dischargeRange = 1...(48 * 60)
    static let chargeRange = 1...(24 * 60)

    private var mode: Mode?
    private var smoothedMinutes: Double?
    private var lastValidSample: ContinuousClock.Instant?

    /// Forget history: call on sleep/wake and whenever the power state changes.
    mutating func reset() {
        mode = nil
        smoothedMinutes = nil
        lastValidSample = nil
    }

    mutating func estimate(for reading: BatteryReading, power: PowerStatus,
                           at now: ContinuousClock.Instant) -> BatteryTimeEstimate {
        let newMode: Mode
        switch power {
        case .charging:
            newMode = .charging
        case .onBattery:
            newMode = .discharging
        case .noBattery, .fullyCharged:
            // Nothing to estimate (no battery, or already full).
            reset()
            return .notApplicable
        }
        if newMode != mode {
            reset()          // never blend a time-to-empty history into a time-to-full one
            mode = newMode
        }

        guard let raw = validMinutes(from: reading, mode: newMode) else {
            // A brief dropout keeps the last value only while discharging. While charging, an unknown
            // time-to-full always shows "Calculating…" instead of a held (possibly stale) number.
            if newMode == .discharging, let smoothedMinutes, let lastValidSample,
               now - lastValidSample < Self.missingHold {
                return display(smoothedMinutes, mode: newMode)
            }
            smoothedMinutes = nil
            return .calculating
        }

        if let lastValidSample, now - lastValidSample > Self.staleGap { smoothedMinutes = nil }

        if let current = smoothedMinutes, abs(raw - current) / current <= Self.jumpThreshold {
            smoothedMinutes = current + Self.smoothingWeight * (raw - current)
        } else {
            smoothedMinutes = raw
        }
        lastValidSample = now
        return display(smoothedMinutes ?? raw, mode: newMode)
    }

    private func validMinutes(from reading: BatteryReading, mode: Mode) -> Double? {
        guard reading.providesTimeRemaining else { return nil }
        switch mode {
        case .discharging:
            // Prefer the system-wide estimate; fall back to the description value.
            let candidates = [reading.systemTimeToEmptyMinutes, reading.descriptionTimeToEmptyMinutes]
            return candidates.compactMap { $0 }.first { Self.dischargeRange.contains($0) }.map(Double.init)
        case .charging:
            return reading.timeToFullMinutes.flatMap { Self.chargeRange.contains($0) ? Double($0) : nil }
        }
    }

    private func display(_ minutes: Double, mode: Mode) -> BatteryTimeEstimate {
        let rounded = Self.roundedForDisplay(minutes)
        return mode == .discharging ? .remaining(minutes: rounded) : .untilFull(minutes: rounded)
    }

    /// Nearest 5 minutes from 10 minutes up (the data is not more precise than that); 1-minute steps below.
    static func roundedForDisplay(_ minutes: Double) -> Int {
        if minutes >= 10 { return max(5, Int((minutes / 5).rounded()) * 5) }
        return max(1, Int(minutes.rounded()))
    }
}
