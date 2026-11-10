import SwiftUI

/// Frames for text that only changes once per second (countdowns, elapsed times, playback positions).
///
/// The first frame is "now"; after that there is one frame per whole second, aligned to the moment the displayed
/// second actually changes (`anchor` is any such moment), so the text never lags or skips. When `isTicking` is
/// false it yields the single "now" frame and nothing else.
///
/// Measured: a sub-second `TimelineView` keeps the process at about 60 wakeups/s and 4–8% CPU, while a 1 Hz one
/// costs 0.4% and about 5 wakeups/s.
struct WholeSecondSchedule: TimelineSchedule {
    let anchor: Date
    let isTicking: Bool

    /// A little after the boundary, so the clock has certainly crossed it when the frame is drawn.
    static let slack: TimeInterval = 0.03

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(next: startDate, anchor: anchor.addingTimeInterval(Self.slack), isTicking: isTicking)
    }

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?
        let anchor: Date
        let isTicking: Bool
        init(next: Date, anchor: Date, isTicking: Bool) {
            self.upcoming = next
            self.anchor = anchor
            self.isTicking = isTicking
        }

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            upcoming = isTicking ? Self.boundary(after: current, anchor: anchor) : nil
            return current
        }

        /// The first `anchor + n` seconds that lies after `date`.
        static func boundary(after date: Date, anchor: Date) -> Date {
            let n = ((date.timeIntervalSince(anchor)) + 0.001).rounded(.down) + 1
            return anchor.addingTimeInterval(n)
        }
    }

    /// When the whole-second reading of a value that counts *down* next changes: after its fractional part.
    static func anchorForCountdown(remainingSeconds: Double, now: Date = .now) -> Date {
        now.addingTimeInterval(remainingSeconds - remainingSeconds.rounded(.down))
    }

    /// When the whole-second reading of a value that counts *up* next changes: after the rest of the second.
    static func anchorForCountUp(elapsedSeconds: Double, now: Date = .now) -> Date {
        now.addingTimeInterval(1 - (elapsedSeconds - elapsedSeconds.rounded(.down)))
    }
}

/// A `TimelineView` that redraws once per whole second while `isTicking`. It keeps its identity when ticking
/// starts or stops, which matters: a drag gesture inside the content (the progress scrub) would otherwise be
/// cancelled the moment it starts. Measured: stopping a one-second schedule leaves no display link behind.
struct WholeSecondTimeline<Content: View>: View {
    let anchor: Date
    let isTicking: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(WholeSecondSchedule(anchor: anchor, isTicking: isTicking)) { context in content(context.date) }
    }
}
