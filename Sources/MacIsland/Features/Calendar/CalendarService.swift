import AppKit
import EventKit
import Observation

/// Reads the next upcoming event through EventKit. Authorization is requested only when the user
/// presses the button in the Calendar tab. Refreshes are event-driven (store changes, wake); the
/// 60 s timer runs only while the Calendar tab is on screen.
@MainActor
@Observable
final class CalendarService {
    private(set) var access: CalendarAccess
    private(set) var nextEvent: UpcomingEvent?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isVisible = false

    /// Called whenever the next upcoming event changes (including to none).
    @ObservationIgnored var onNextEventChange: (@MainActor (UpcomingEvent?) -> Void)?

    static let refreshInterval: Duration = .seconds(60)

    init() {
        access = Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    /// Fixed state for previews and layout checks. Starts nothing.
    static func preview(event: UpcomingEvent?) -> CalendarService {
        let service = CalendarService()
        service.access = .authorized
        service.nextEvent = event
        return service
    }

    static func map(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .authorized
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    var isRunning: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
        refresh()
    }

    func stop() {
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        refreshTask?.cancel()
        refreshTask = nil
        nextEvent = nil
        onNextEventChange?(nil)
    }

    /// While visible: refresh now and once a minute. When hidden: no timer.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        refreshTask?.cancel()
        refreshTask = nil
        guard visible else { return }
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// Shows the system permission prompt (only possible while the status is not determined).
    func requestAccess() {
        guard access == .notDetermined else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.store.requestFullAccessToEvents()
            self.refresh()
        }
    }

    func refresh() {
        let newAccess = Self.map(EKEventStore.authorizationStatus(for: .event))
        if newAccess != access { access = newAccess }
        guard newAccess == .authorized else {
            if nextEvent != nil { nextEvent = nil }
            return
        }

        let now = Date()
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(UpcomingEventSelector.horizon),
                                                 calendars: nil)
        let snapshots = store.events(matching: predicate).map(Self.snapshot(of:))
        let next = UpcomingEventSelector.next(from: snapshots, now: now)
        if next != nextEvent {
            nextEvent = next
            onNextEventChange?(next)
        }
    }

    private static func snapshot(of event: EKEvent) -> UpcomingEvent {
        let rgb = event.calendar.flatMap { $0.cgColor }
            .flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
            .map { EventColor(red: Double($0.redComponent), green: Double($0.greenComponent), blue: Double($0.blueComponent)) }
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return UpcomingEvent(id: event.eventIdentifier ?? UUID().uuidString,
                             title: title.isEmpty ? "Untitled event" : title,
                             start: event.startDate, end: event.endDate,
                             isAllDay: event.isAllDay, color: rgb ?? .fallback)
    }
}
