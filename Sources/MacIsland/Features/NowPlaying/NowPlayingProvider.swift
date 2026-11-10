import AppKit

struct PlaybackTiming: Equatable, Sendable {
    var position: TimeInterval
    var duration: TimeInterval?
}

/// A music app Mac Island can read from and control through Apple Events only.
/// Add a new service by conforming to this protocol and registering it in `NowPlayingService`.
protocol NowPlayingProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var bundleIdentifier: String { get }
    /// Distributed notification the app posts when playback changes (needs no permission).
    var playerInfoNotification: Notification.Name { get }

    func parse(userInfo: [AnyHashable: Any]?) -> ProviderUpdate
    /// Asks the app directly (Automation permission required).
    func querySnapshot() async throws -> NowPlayingSnapshot?
    func fetchArtwork() async throws -> Data?
    func fetchTiming() async throws -> PlaybackTiming?
    func send(_ command: PlaybackCommand) async throws
    func seek(to seconds: TimeInterval) async throws
}

extension NowPlayingProvider {
    /// Every Apple Event is guarded by this: addressing an app by name would otherwise launch it.
    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// Apple Music and Spotify share the same AppleScript vocabulary and notification payload shape.
struct ScriptableMusicProvider: NowPlayingProvider {
    enum ArtworkSource: Sendable {
        case embeddedData   // Apple Music returns the image bytes
        case remoteURL      // Spotify returns an https URL
    }

    let id: String
    let displayName: String
    let bundleIdentifier: String
    let scriptApplicationName: String
    let playerInfoNotification: Notification.Name
    let artworkSource: ArtworkSource
    /// Notification key for the track length (milliseconds) and, if present, position (seconds) and track id.
    let durationKey: String
    let positionKey: String?
    let trackIDKey: String?
    /// `duration of current track` is seconds in Music and milliseconds in Spotify.
    let scriptDurationDivisor: Double

    static let appleMusic = ScriptableMusicProvider(
        id: "apple-music", displayName: "Music", bundleIdentifier: "com.apple.Music",
        scriptApplicationName: "Music",
        playerInfoNotification: Notification.Name("com.apple.Music.playerInfo"),
        artworkSource: .embeddedData,
        durationKey: "Total Time", positionKey: nil, trackIDKey: nil, scriptDurationDivisor: 1)

    static let spotify = ScriptableMusicProvider(
        id: "spotify", displayName: "Spotify", bundleIdentifier: "com.spotify.client",
        scriptApplicationName: "Spotify",
        playerInfoNotification: Notification.Name("com.spotify.client.PlaybackStateChanged"),
        artworkSource: .remoteURL,
        durationKey: "Duration", positionKey: "Playback Position", trackIDKey: "Track ID", scriptDurationDivisor: 1000)

    func parse(userInfo: [AnyHashable: Any]?) -> ProviderUpdate {
        guard let userInfo, let rawState = userInfo["Player State"] as? String else { return .ignored }
        let status: PlaybackStatus
        switch rawState.lowercased() {
        case "playing": status = .playing
        case "paused": status = .paused
        default: return .stopped
        }
        let durationMilliseconds = (userInfo[durationKey] as? NSNumber)?.doubleValue
        let trackID = trackIDKey.flatMap { userInfo[$0] as? String }
        return .track(NowPlayingSnapshot(
            providerID: id, providerName: displayName,
            title: userInfo["Name"] as? String ?? "",
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            status: status,
            duration: durationMilliseconds.map { $0 / 1000 }.flatMap { $0 > 0 ? $0 : nil },
            positionHint: positionKey.flatMap { (userInfo[$0] as? NSNumber)?.doubleValue },
            isAdvert: trackID?.hasPrefix("spotify:ad:") == true))
    }

    func querySnapshot() async throws -> NowPlayingSnapshot? {
        guard isRunning else { return nil } // never launch the app just to ask it something
        let source = script("""
        if player state is stopped then return "stopped"
        return (player state as text) & linefeed & (name of current track) & linefeed & \
        (artist of current track) & linefeed & (album of current track)
        """)
        guard let output = try await AppleScriptRunner.shared.runForString(source) else { return nil }
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 4 else { return nil }
        let status: PlaybackStatus
        switch lines[0].lowercased() {
        case "playing": status = .playing
        case "paused": status = .paused
        default: return nil
        }
        return NowPlayingSnapshot(providerID: id, providerName: displayName,
                                  title: lines[1], artist: lines[2], album: lines[3], status: status)
    }

    func fetchTiming() async throws -> PlaybackTiming? {
        guard isRunning else { return nil }
        // Numbers come back as a list so no locale-dependent decimal text is parsed. The duration lookup
        // can fail for radio-style streams, in which case it is reported as 0 (unknown).
        let source = script("""
        if player state is stopped then return {}
        set currentPosition to player position
        set trackLength to 0
        try
        set trackLength to duration of current track
        end try
        return {currentPosition, trackLength}
        """)
        let numbers = try await AppleScriptRunner.shared.runForNumbers(source)
        guard let position = numbers.first else { return nil }
        let length = numbers.count > 1 ? numbers[1] / scriptDurationDivisor : 0
        return PlaybackTiming(position: max(0, position), duration: length > 0 ? length : nil)
    }

    func fetchArtwork() async throws -> Data? {
        guard isRunning else { return nil }
        switch artworkSource {
        case .embeddedData:
            return try await AppleScriptRunner.shared.runForData(script("""
            if (count of artworks of current track) is 0 then return missing value
            return data of artwork 1 of current track
            """))
        case .remoteURL:
            // Only the artwork URL Spotify itself reports is fetched; https only, no cookies or identifiers.
            guard let raw = try await AppleScriptRunner.shared.runForString(script("return artwork url of current track")),
                  let url = URL(string: raw), url.scheme == "https" else { return nil }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpShouldHandleCookies = false
            let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
            return data
        }
    }

    func send(_ command: PlaybackCommand) async throws {
        guard isRunning else { throw AppleScriptError.appNotRunning }
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        _ = try await AppleScriptRunner.commands.runForString(script(verb))
    }

    func seek(to seconds: TimeInterval) async throws {
        guard isRunning else { throw AppleScriptError.appNotRunning }
        // Whole milliseconds divided inside AppleScript, so the number never depends on locale formatting.
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        _ = try await AppleScriptRunner.commands.runForString(script("set player position to (\(milliseconds) / 1000)"))
    }

    private func script(_ body: String) -> String {
        "tell application \"\(scriptApplicationName)\"\n\(body)\nend tell"
    }
}
