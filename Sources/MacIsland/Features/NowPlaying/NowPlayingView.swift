import SwiftUI

extension ArtworkColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

struct NowPlayingView: View {
    @Environment(\.islandPalette) private var palette
    let isVisible: Bool
    @Environment(IslandFeatureStore.self) private var store
    @Environment(\.islandAccent) private var accent
    @Environment(\.islandArtworkNudge) private var nudge

    var body: some View {
        let service = store.nowPlaying
        Group {
            if let snapshot = service.snapshot {
                VStack(alignment: .leading, spacing: IslandSpacing.l) {
                    HStack(spacing: IslandSpacing.xxl) {
                        artwork(service.artwork, visual: service.visual)
                        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                                Text(snapshot.title.isEmpty ? "Unknown Title" : snapshot.title)
                                    .font(IslandType.bodySemibold)
                                    .foregroundStyle(IslandTheme.primaryText)
                                    .lineLimit(1)
                                Text(snapshot.artist.isEmpty ? snapshot.providerName : snapshot.artist)
                                    .font(IslandType.label)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }
                            // One element: "Title, Artist, Album" with the playback state as its value.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(IslandAccessibility.trackLabel(snapshot))
                            .accessibilityValue(snapshot.status == .playing ? "Playing" : "Paused")
                            if service.notice == .automationDenied {
                                automationNotice
                            } else {
                                controls(service, status: snapshot.status)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    // Hidden when the length is unknown or zero (streams, some podcasts) and for adverts.
                    if let progress = service.progress {
                        PlaybackProgressBar(progress: progress, tint: accent) { service.seek(to: $0) }
                    }
                }
            } else if service.notice == .automationDenied {
                IslandNotice.accessOff(symbol: "music.note", subject: "Automation") { SystemSettingsLink.automation.open() }
            } else {
                IslandNotice(symbol: "music.note", title: "Nothing playing", detail: "Play something in Music or Spotify.")
            }
        }
        .task(id: isVisible) { service.setVisible(isVisible) }
    }

    private func artwork(_ image: CGImage?, visual: PlaybackVisual) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(IslandTheme.surfaceSubtle)
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(IslandType.symbolLarge).foregroundStyle(palette.secondaryText)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .artworkPauseStyle(visual: visual, shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .artworkNudge(nudge)       // swipe feedback (a dim instead of a nudge with Reduce Motion)
        .accessibilityHidden(true)      // the track label already covers it
    }

    private func controls(_ service: NowPlayingService, status: PlaybackStatus) -> some View {
        HStack(spacing: IslandSpacing.m) {
            IslandIconButton(systemName: "backward.fill", label: "Previous track", font: IslandType.labelSemibold) { service.send(.previous) }
            IslandIconButton(systemName: status == .playing ? "pause.fill" : "play.fill",
                             label: status == .playing ? "Pause" : "Play", isProminent: true) { service.send(.playPause) }
            IslandIconButton(systemName: "forward.fill", label: "Next track", font: IslandType.labelSemibold) { service.send(.next) }
        }
        .padding(.top, IslandSpacing.s)
    }

    /// Shown in place of the controls while Automation access is off.
    private var automationNotice: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            Text("Automation access is off")
                .font(IslandType.caption)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            IslandNoticeButton(title: "Open Settings") { SystemSettingsLink.automation.open() }
        }
        .padding(.top, IslandSpacing.xxs)
    }
}
