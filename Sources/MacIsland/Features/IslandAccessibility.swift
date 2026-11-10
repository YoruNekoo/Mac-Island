import Foundation

/// Text for VoiceOver. Pure functions, so they can be tested without any UI.
enum IslandAccessibility {
    /// "Title, Artist, Album". Parts that are empty are left out.
    static func trackLabel(_ snapshot: NowPlayingSnapshot) -> String {
        let title = snapshot.title.isEmpty ? "Unknown title" : snapshot.title
        let artist = snapshot.artist.isEmpty ? snapshot.providerName : snapshot.artist
        return [title, artist, snapshot.album].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static let collapsedLabel = "Mac Island"
    static let collapsedHint = "Expands the notch."
    static let panelLabel = "Mac Island notch"
}

extension IslandFeatureStore {
    /// What the collapsed notch is showing, in words, for VoiceOver. Covers everything the compact notch can show,
    /// including the recording dots, so nothing is conveyed by color or shape alone.
    func compactAccessibilitySummary(selected: IslandContent, chargingPercent: Int?) -> String {
        var parts: [String] = []
        if let chargingPercent {
            parts.append("Charging, \(chargingPercent) percent")
        } else if let activity = compactActivity(selected: selected) {
            switch activity {
            case .timer:
                let model = timer.model
                if model.phase == .finished { parts.append("Timer finished") }
                else {
                    let seconds = Int(TimeFormatting.seconds(model.remaining(at: .now)).rounded(.up))
                    var isRunning = false
                    if case .running = model.phase { isRunning = true }
                    parts.append("Timer, \(TimeFormatting.spoken(seconds: seconds)) \(isRunning ? "remaining" : "remaining, paused")")
                }
            case .stopwatch:
                let model = stopwatch.model
                parts.append("Stopwatch, \(TimeFormatting.spoken(seconds: Int(TimeFormatting.seconds(model.elapsed(at: .now)))))"
                             + (model.isRunning ? "" : ", paused"))
            case .nowPlaying:
                if let snapshot = nowPlaying.snapshot {
                    parts.append("\(snapshot.status == .playing ? "Playing" : "Paused"): \(IslandAccessibility.trackLabel(snapshot))")
                }
            case .battery:
                parts.append(battery.state.hasBattery ? "Battery, \(battery.state.statusText)" : "No battery")
            case .download:
                if let item = downloads.primary { parts.append(Self.downloadSentence(item)) }
            case .calendar:
                if let event = calendar.nextEvent {
                    parts.append("Next event, \(event.title), \(CalendarFormatting.startText(start: event.start, now: .now))")
                }
            }
        }
        // The small download glyph shows next to music even when downloads are not the main activity.
        if chargingPercent == nil, isEnabled(.downloads), downloads.isAvailable, let item = downloads.primary,
           compactActivity(selected: selected) != .download {
            parts.append(Self.downloadSentence(item))
        }
        if isEnabled(.recording) {
            if recording.isMicrophoneInUse { parts.append("Microphone in use") }
            if recording.isCameraInUse { parts.append("Camera in use") }
        }
        return parts.isEmpty ? "Nothing active" : parts.joined(separator: ". ")
    }

    private static func downloadSentence(_ item: DownloadItem) -> String {
        item.state == .completed ? "Download complete, \(item.displayName)" : "Downloading \(item.displayName)"
    }
}
