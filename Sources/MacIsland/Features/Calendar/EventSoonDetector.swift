import Foundation

/// Fires once per event when it is five minutes (or less) from starting. Event-driven: it sleeps until
/// the five-minute mark of the next event, so there is no polling.
@MainActor
final class EventSoonDetector {
    private let lead: TimeInterval
    private let onEventSoon: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var firedEventIDs: Set<String> = []

    init(lead: TimeInterval = 5 * 60, onEventSoon: @escaping @MainActor () -> Void) {
        self.lead = lead
        self.onEventSoon = onEventSoon
    }

    /// Call whenever the next event changes (including to nil).
    func update(_ event: UpcomingEvent?, now: Date = Date()) {
        task?.cancel()
        task = nil
        guard let event, !firedEventIDs.contains(event.id), event.start > now else { return }
        let delay = event.start.addingTimeInterval(-lead).timeIntervalSince(now)
        if delay <= 0 {
            fire(event.id)
        } else {
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.fire(event.id)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func fire(_ id: String) {
        guard firedEventIDs.insert(id).inserted else { return }
        onEventSoon()
    }
}
