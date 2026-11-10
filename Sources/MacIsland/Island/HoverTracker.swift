import Foundation

/// Decides when resting on the notch should open it (Hover mode).
///
/// The pointer must stay on the visible shape for `dwell`; leaving cancels. After the notch closes it must be
/// left once before it can open again, so closing it while the pointer is still on it does not reopen it.
@MainActor
final class HoverTracker {
    private let dwell: Duration
    private let onTrigger: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var isArmed = true
    private var pointerIsInside = false

    static let defaultDwell: Duration = .milliseconds(250)

    init(dwell: Duration = HoverTracker.defaultDwell, onTrigger: @escaping @MainActor () -> Void) {
        self.dwell = dwell
        self.onTrigger = onTrigger
    }

    var isWaiting: Bool { task != nil }

    /// Call on every pointer move with whether it is on the visible shape.
    func pointerMoved(insideShape: Bool) {
        pointerIsInside = insideShape
        guard insideShape else {
            isArmed = true
            cancel()
            return
        }
        guard isArmed, task == nil else { return }
        task = Task { [weak self, dwell] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled, let self else { return }
            self.task = nil
            guard self.pointerIsInside, self.isArmed else { return }
            self.isArmed = false
            self.onTrigger()
        }
    }

    /// The notch closed: stay quiet until the pointer has left the shape.
    func didCollapse() {
        isArmed = false
        cancel()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
