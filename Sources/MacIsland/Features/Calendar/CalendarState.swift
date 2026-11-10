import Foundation

enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    /// Denied, restricted, or write-only (which cannot read events).
    case denied
}

struct EventColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let fallback = EventColor(red: 0.6, green: 0.6, blue: 0.62)
}

/// Sendable copy of the parts of an `EKEvent` the UI needs. `EKEvent` itself is not Sendable.
struct UpcomingEvent: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: EventColor
}

/// Pure selection logic, kept separate from EventKit so it can be tested.
enum UpcomingEventSelector {
    static let horizon: TimeInterval = 24 * 60 * 60

    /// The soonest non-all-day event that starts from `now` up to 24 hours ahead.
    static func next(from events: [UpcomingEvent], now: Date) -> UpcomingEvent? {
        let limit = now.addingTimeInterval(horizon)
        return events
            .filter { !$0.isAllDay && $0.start >= now && $0.start <= limit }
            .min { $0.start < $1.start }
    }
}

enum CalendarFormatting {
    /// "in 12 min" within the hour, otherwise the start time ("3:30 PM", or "Tomorrow, 9:00 AM").
    static func startText(start: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return "Now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes <= 60 { return "in \(minutes) min" }
        let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        return calendar.isDate(start, inSameDayAs: now) ? time : "Tomorrow, \(time)"
    }
}
