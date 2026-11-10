import Foundation

/// Pure time formatting helpers (unit-testable, no UI).
enum TimeFormatting {
    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    /// A length of time for VoiceOver: "1 hour 5 minutes 3 seconds", "45 seconds". Zero parts are left out.
    static func spoken(seconds total: Int) -> String {
        let total = max(0, total)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        if s > 0 || parts.isEmpty { parts.append(s == 1 ? "1 second" : "\(s) seconds") }
        return parts.joined(separator: " ")
    }

    /// Countdown display. Rounds *up* so the clock reads 00:01 until it truly hits zero.
    /// Shows hours only when needed: `MM:SS` or `H:MM:SS`.
    static func countdown(_ remaining: Duration) -> String {
        let total = Int(max(0, seconds(remaining)).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Stopwatch display with milliseconds: `MM:SS.mmm`, or `H:MM:SS.mmm` after an hour.
    static func stopwatch(_ elapsed: Duration, showMilliseconds: Bool = true) -> String {
        let totalMilliseconds = Int((max(0, seconds(elapsed)) * 1000).rounded(.down))
        let h = totalMilliseconds / 3_600_000
        let m = (totalMilliseconds / 60_000) % 60
        let s = (totalMilliseconds / 1000) % 60
        let ms = totalMilliseconds % 1000
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        return showMilliseconds ? base + String(format: ".%03d", ms) : base
    }
}
