import Foundation

struct AutoCollapseConfig: Equatable, Sendable {
    var isEnabled: Bool
    var delay: Duration

    static let standard = AutoCollapseConfig(isEnabled: true, delay: .seconds(5))
}

/// Owns at most one pending auto-collapse task. Restarting always cancels the previous one,
/// so duplicate timers cannot exist.
@MainActor
final class AutoCollapseScheduler {
    private var task: Task<Void, Never>?

    func restart(after delay: Duration, action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
