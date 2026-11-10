import AppKit

enum HapticKind: Sendable {
    /// The notch opened.
    case expand
    /// The music scrubber reached the start or the end.
    case scrubLimit
    /// A swipe skipped a track.
    case skip

    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .expand: .alignment      // the lightest tick
        case .scrubLimit: .levelChange
        case .skip: .alignment
        }
    }
}

@MainActor
protocol HapticPerforming {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern)
}

/// The system performer. On a Mac without a Force Touch trackpad this does nothing, silently.
struct SystemHapticPerformer: HapticPerforming {
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

@MainActor
struct HapticFeedback {
    var isEnabled: @MainActor () -> Bool
    var performer: HapticPerforming = SystemHapticPerformer()

    func play(_ kind: HapticKind) {
        guard isEnabled() else { return }
        performer.perform(kind.pattern)
    }
}
