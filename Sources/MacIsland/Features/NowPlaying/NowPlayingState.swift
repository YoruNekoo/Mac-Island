import Foundation

enum PlaybackStatus: Equatable, Sendable {
    case playing, paused
}

enum PlaybackCommand: Equatable, Sendable {
    case playPause, next, previous
}

struct NowPlayingSnapshot: Equatable, Sendable {
    var providerID: String
    var providerName: String
    var title: String
    var artist: String
    var album: String
    var status: PlaybackStatus
    /// Track length in seconds, when the player reported one.
    var duration: TimeInterval?
    /// Playback position in seconds, when the notification carried one (Spotify does, Music does not).
    var positionHint: TimeInterval?
    /// A streaming advert (Spotify). It has no meaningful progress.
    var isAdvert = false

    /// Identity used to decide when artwork must be reloaded.
    var trackKey: String { "\(providerID)|\(title)|\(artist)|\(album)" }
}

/// Where playback is, as an anchor that can be interpolated locally: position at a moment in time, plus
/// whether it is advancing. No timer is needed to know the current position.
struct PlaybackProgress: Equatable, Sendable {
    var duration: TimeInterval
    var anchorPosition: TimeInterval
    var anchorDate: Date
    var isPlaying: Bool

    func position(at now: Date) -> TimeInterval {
        let raw = isPlaying ? anchorPosition + now.timeIntervalSince(anchorDate) : anchorPosition
        return min(max(raw, 0), duration)
    }

    func fraction(at now: Date) -> Double {
        duration > 0 ? position(at: now) / duration : 0
    }
}

/// Dominant artwork color, already adjusted to read clearly on pure black.
struct ArtworkColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = ArtworkColor(red: 1, green: 1, blue: 1)
}

/// User-facing problems the Now Playing view can explain.
enum NowPlayingNotice: Equatable, Sendable {
    case automationDenied
}

/// Result of parsing a player's distributed notification.
enum ProviderUpdate: Sendable {
    case track(NowPlayingSnapshot)
    case stopped
    case ignored
}
