/// What the battery view shows about time. Never carries a made-up duration.
enum BatteryTimeEstimate: Equatable, Sendable {
    /// Nothing to estimate (no battery, fully charged, or plugged in and not charging).
    case notApplicable
    /// macOS has not produced a usable estimate yet.
    case calculating
    case remaining(minutes: Int)
    case untilFull(minutes: Int)
}

/// The single source of truth for power status, derived from the current IOKit snapshot only.
/// Every label, icon and estimate comes from exactly one of these, so they cannot disagree.
///
/// Product rule: status follows *external power*, not the "Is Charging" flag, which lags the real
/// power state. So "Charging" means "external power connected".
enum PowerStatus: Equatable, Sendable {
    case noBattery
    /// `kIOPSPowerSourceStateKey` is "Battery Power".
    case onBattery
    /// External power connected and the battery is not full.
    case charging
    /// External power connected and (`kIOPSIsChargedKey` or 100%).
    case fullyCharged

    /// Pure function of one snapshot. Carries no state from earlier events.
    static func from(_ reading: BatteryReading) -> PowerStatus {
        guard reading.hasBattery else { return .noBattery }
        guard reading.isExternalPower else { return .onBattery }
        return reading.isCharged || reading.percent >= 100 ? .fullyCharged : .charging
    }

    var isExternalPowerConnected: Bool {
        switch self {
        case .charging, .fullyCharged: true
        case .noBattery, .onBattery: false
        }
    }
}

struct BatteryState: Equatable, Sendable {
    var hasBattery: Bool
    var percent: Int
    var power: PowerStatus
    var estimate: BatteryTimeEstimate

    static let noBattery = BatteryState(hasBattery: false, percent: 0, power: .noBattery, estimate: .notApplicable)

    var isCharging: Bool { power == .charging }
    var isLow: Bool { power == .onBattery && percent <= 20 }

    /// Primary label.
    var statusText: String {
        switch power {
        case .noBattery: "No battery"
        case .onBattery: "On battery"
        case .charging: "Charging"
        case .fullyCharged: "Fully charged"
        }
    }

    /// Secondary label. Derived from the same `power` value as `statusText`.
    var detailText: String {
        switch power {
        case .noBattery: return "This Mac runs on power only"
        case .fullyCharged: return "Connected to power"
        case .onBattery:
            // Only a time-to-empty estimate is valid here. While macOS has none (right after unplugging),
            // show nothing rather than a "Calculating…" placeholder.
            if case .remaining(let minutes) = estimate { return "About \(Self.duration(minutes)) remaining" }
            return ""
        case .charging:
            if case .untilFull(let minutes) = estimate { return "About \(Self.duration(minutes)) until full" }
            return "Calculating…"
        }
    }

    /// "7 hr 16 min", "1 hr", "45 min". No seconds: the system estimate has no such precision.
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, mins = minutes % 60
        if hours == 0 { return "\(mins) min" }
        return mins == 0 ? "\(hours) hr" : "\(hours) hr \(mins) min"
    }

    var symbolName: String {
        guard hasBattery else { return "powerplug.fill" }
        if power == .charging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}
