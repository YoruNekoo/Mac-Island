import SwiftUI

/// What the compact notch shows. Nothing when no feature is active, so the idle notch stays plain black.
struct CompactActivityView: View {
    let selected: IslandContent
    /// While set, the compact notch shows the charging flash in place of its usual content (recording dots stay).
    var chargingFlash: ChargingFlash?
    @Environment(IslandFeatureStore.self) private var store
    @Environment(\.islandPalette) private var palette

    var body: some View {
        let recording = store.recording
        let recordingEnabled = store.isEnabled(.recording)
        let micInUse = recordingEnabled && recording.isMicrophoneInUse
        let cameraInUse = recordingEnabled && recording.isCameraInUse
        let dotsWidth = RecordingDots.width(microphone: micInUse, camera: cameraInUse)
        let flashing = chargingFlash != nil
        let download = !flashing && store.isEnabled(.downloads) && store.downloads.isAvailable ? store.downloads.primary?.state : nil
        let music = !flashing && store.compactActivity(selected: selected) == .nowPlaying ? store.nowPlaying : nil

        // Left group: download glyph, then album artwork. Right group: soundwave, then recording dots.
        // Together they fit the 150 pt notch with room to spare (14..54 and 93..136), so none ever overlap.
        let leadingWidth = flashing ? ChargingBoltView.width : (download == nil ? 0 : DownloadGlyph.width)
            + (music == nil ? 0 : CompactArtworkView.size)
            + (download != nil && music != nil ? Self.clusterSpacing : 0)
        let trailingWidth = (flashing ? ChargingLevelView.width : (music == nil ? 0 : SoundwaveView.width))
            + dotsWidth
            + ((flashing || music != nil) && dotsWidth > 0 ? Self.clusterSpacing : 0)

        let leadingKey = ClusterKey(flashing: flashing, download: download, hasMusic: music != nil, dotsWidth: 0)
        let trailingKey = ClusterKey(flashing: flashing, download: nil, hasMusic: music != nil, dotsWidth: dotsWidth)

        activity
            // Leave room for the accessories so centered content never overlaps them.
            .padding(.leading, leadingWidth == 0 ? 0 : leadingWidth + IslandSpacing.s)
            .padding(.trailing, trailingWidth == 0 ? 0 : trailingWidth + IslandSpacing.s)
            .animation(IslandAnimations.contentSwitch, value: [leadingWidth, trailingWidth])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                HStack(spacing: Self.clusterSpacing) {
                    if flashing { ChargingBoltView().transition(.opacity) }
                    if let download { DownloadGlyph(state: download) }
                    if let music { CompactArtworkView(image: music.artwork, visual: music.visual) }
                }
                .animation(IslandAnimations.contentSwitch, value: leadingKey)
                .padding(.leading, IslandSpacing.accessoryInset).padding(.bottom, IslandSpacing.baselineOffset)
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: Self.clusterSpacing) {
                    if let chargingFlash { ChargingLevelView(percent: chargingFlash.percent).id(chargingFlash.id).transition(.opacity) }
                    if let music {
                        SoundwaveView(color: (music.artworkColor ?? .white).color, visual: music.visual)
                    }
                    RecordingDots(isMicrophoneInUse: micInUse, isCameraInUse: cameraInUse)
                }
                .animation(IslandAnimations.contentSwitch, value: trailingKey)
                .padding(.trailing, IslandSpacing.accessoryInset).padding(.bottom, IslandSpacing.baselineOffset)
            }
    }

    /// What one side's accessories depend on. Each side animates only when its own key changes.
    private struct ClusterKey: Equatable {
        var flashing: Bool
        var download: DownloadItem.State?
        var hasMusic: Bool
        var dotsWidth: CGFloat
    }

    private static let clusterSpacing = IslandSpacing.m

    /// Center content for the single-value activities. Music has no center content: artwork and soundwave
    /// sit at the edges, and the track title is not shown in the compact notch.
    private var activity: some View {
        Group {
            switch chargingFlash == nil ? store.compactActivity(selected: selected) : nil {
            case .timer: timer
            case .stopwatch: stopwatch
            case .battery: battery
            case .download: downloadActivity
            case .calendar: calendarActivity
            case .nowPlaying, nil: Color.clear
            }
        }
        .font(IslandType.clockBody)
        .foregroundStyle(IslandTheme.primaryText)
        .padding(.horizontal, IslandSpacing.gutter)
        .padding(.bottom, IslandSpacing.baselineOffset)
    }

    /// Shown only when Downloads is pinned: the size so far, or "Done". The leading arrow glyph stays.
    private var downloadActivity: some View {
        Group {
            if let item = store.downloads.primary {
                Text(item.state == .completed ? "Done" : DownloadFormatting.size(item.bytes))
                    .font(IslandType.clockLabel)
            }
        }
    }

    /// Shown only when Calendar is pinned: the event's color dot and when it starts.
    private var calendarActivity: some View {
        Group {
            if let event = store.calendar.nextEvent {
                HStack(spacing: IslandSpacing.m) {
                    Circle()
                        .fill(Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue))
                        .frame(width: 7, height: 7)
                    TimelineView(.everyMinute) { context in
                        Text(CalendarFormatting.startText(start: event.start, now: context.date))
                            .font(IslandType.clockLabel)
                    }
                }
            }
        }
    }

    private var timer: some View {
        let model = store.timer.model
        let isRunning: Bool = { if case .running = model.phase { true } else { false } }()
        return HStack(spacing: IslandSpacing.m) {
            Image(systemName: "timer").font(IslandType.captionSemibold)
            if model.phase == .finished {
                Text("Done")
            } else {
                WholeSecondTimeline(anchor: WholeSecondSchedule.anchorForCountdown(
                                        remainingSeconds: TimeFormatting.seconds(model.remaining(at: .now))),
                                    isTicking: isRunning) { _ in
                    Text(TimeFormatting.countdown(model.remaining(at: .now)))
                }
                .opacity(isRunning ? 1 : palette.pausedOpacity)
            }
        }
    }

    private var stopwatch: some View {
        let model = store.stopwatch.model
        return HStack(spacing: IslandSpacing.m) {
            Image(systemName: "stopwatch").font(IslandType.captionSemibold)
            WholeSecondTimeline(anchor: WholeSecondSchedule.anchorForCountUp(
                                    elapsedSeconds: TimeFormatting.seconds(model.elapsed(at: .now))),
                                isTicking: model.isRunning) { _ in
                Text(TimeFormatting.stopwatch(model.elapsed(at: .now), showMilliseconds: false))
            }
            .opacity(model.isRunning ? 1 : palette.pausedOpacity)
        }
    }

    private var battery: some View {
        let state = store.battery.state
        return HStack(spacing: IslandSpacing.m) {
            Image(systemName: state.symbolName).font(IslandType.label)
                .foregroundStyle(state.isCharging ? IslandTheme.charging : IslandTheme.primaryText)
            Text("\(state.percent)%")
        }
    }
}

/// Small rounded album artwork for the compact notch.
struct CompactArtworkView: View {
    @Environment(\.islandPalette) private var palette
    @Environment(\.islandArtworkNudge) private var nudge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let image: CGImage?
    /// Paused music shrinks and dims the artwork inside its fixed slot.
    var visual = PlaybackVisual.initial
    static let size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(IslandTheme.surface)
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(IslandType.captionSemibold).foregroundStyle(palette.secondaryText)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .artworkPauseStyle(visual: visual, shape: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .artworkNudge(nudge)       // swipe feedback (a dim instead of a nudge with Reduce Motion)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        .accessibilityHidden(true)
    }
}
