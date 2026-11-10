import Testing
import EventKit
import ServiceManagement
@testable import MacIsland

@Suite struct StopwatchModelTests {
    let t0 = ContinuousClock.now

    @Test func elapsedComesFromClockDelta() {
        var model = StopwatchModel()
        model.start(at: t0)
        #expect(model.elapsed(at: t0 + .seconds(10)) == .seconds(10))
        model.pause(at: t0 + .seconds(10))
        #expect(model.elapsed(at: t0 + .seconds(500)) == .seconds(10))
        model.start(at: t0 + .seconds(20))
        #expect(model.elapsed(at: t0 + .seconds(25)) == .seconds(15))
    }

    @Test func resetClearsEverything() {
        var model = StopwatchModel()
        model.start(at: t0)
        model.reset()
        #expect(!model.hasElapsed && model.elapsed(at: t0 + .seconds(5)) == .zero)
    }
}

@Suite struct CountdownModelTests {
    let t0 = ContinuousClock.now

    @Test func rejectsZeroDuration() {
        var model = CountdownModel()
        #expect(!model.start(total: .zero, at: t0))
        #expect(model.phase == .idle)
    }

    @Test func pauseResumeAndFinish() {
        var model = CountdownModel()
        model.start(total: .seconds(90), at: t0)
        model.pause(at: t0 + .seconds(30))
        #expect(model.remaining(at: t0 + .seconds(999)) == .seconds(60))
        model.resume(at: t0 + .seconds(100))
        #expect(!model.finishIfElapsed(at: t0 + .seconds(159)))
        #expect(model.finishIfElapsed(at: t0 + .seconds(160)))
        #expect(model.phase == .finished)
    }
}

@Suite struct TimeFormattingTests {
    @Test func countdownFormatsAndRoundsUp() {
        #expect(TimeFormatting.countdown(.seconds(90)) == "01:30")
        #expect(TimeFormatting.countdown(.seconds(3661)) == "1:01:01")
        #expect(TimeFormatting.countdown(.milliseconds(400)) == "00:01")
    }

    @Test func stopwatchFormatsMilliseconds() {
        #expect(TimeFormatting.stopwatch(.milliseconds(12345)) == "00:12.345")
        #expect(TimeFormatting.stopwatch(.seconds(75), showMilliseconds: false) == "01:15")
    }
}

@Suite struct BatteryEstimatorTests {
    let t0 = ContinuousClock.now

    private func reading(percent: Int = 60, external: Bool = false, provides: Bool = true,
                         system: Int? = nil, desc: Int? = nil, full: Int? = nil) -> BatteryReading {
        BatteryReading(hasBattery: true, percent: percent, isExternalPower: external, isCharged: false,
                       providesTimeRemaining: provides, systemTimeToEmptyMinutes: system,
                       descriptionTimeToEmptyMinutes: desc, timeToFullMinutes: full)
    }

    @Test func smoothsSmallJumpsButAdoptsLargeChanges() {
        var estimator = BatteryEstimator()
        _ = estimator.estimate(for: reading(system: 433), power: .onBattery, at: t0)
        #expect(estimator.estimate(for: reading(system: 443), power: .onBattery, at: t0 + .seconds(30)) == .remaining(minutes: 435))
        #expect(estimator.estimate(for: reading(system: 200), power: .onBattery, at: t0 + .seconds(60)) == .remaining(minutes: 200))
    }

    @Test func invalidEstimatesNeverBecomeNumbers() {
        for bad in [nil, -1, 0, 99_999] {
            var estimator = BatteryEstimator()
            #expect(estimator.estimate(for: reading(system: bad, desc: bad), power: .onBattery, at: t0) == .calculating)
        }
    }

    @Test func chargingUsesTimeToFullAndNeverHoldsAStaleValue() {
        var estimator = BatteryEstimator()
        #expect(estimator.estimate(for: reading(external: true, full: 90), power: .charging, at: t0) == .untilFull(minutes: 90))
        #expect(estimator.estimate(for: reading(external: true, full: -1), power: .charging, at: t0 + .seconds(10)) == .calculating)
    }

    @Test func fullyChargedHasNoEstimate() {
        var estimator = BatteryEstimator()
        #expect(estimator.estimate(for: reading(external: true, full: 45), power: .fullyCharged, at: t0) == .notApplicable)
    }

    @Test func formatsDurations() {
        #expect(BatteryState.duration(436) == "7 hr 16 min")
        #expect(BatteryState.duration(120) == "2 hr")
        #expect(BatteryState.duration(45) == "45 min")
    }
}

@Suite struct PowerStatusTests {
    private func snapshot(external: Bool, percent: Int = 55, charged: Bool = false) -> BatteryReading {
        BatteryReading(hasBattery: true, percent: percent, isExternalPower: external, isCharged: charged,
                       providesTimeRemaining: true, systemTimeToEmptyMinutes: 300,
                       descriptionTimeToEmptyMinutes: 300, timeToFullMinutes: 60)
    }

    @Test func externalPowerMeansCharging() {
        #expect(PowerStatus.from(snapshot(external: true)) == .charging)
    }

    @Test func batteryPowerMeansOnBattery() {
        #expect(PowerStatus.from(snapshot(external: false)) == .onBattery)
        #expect(PowerStatus.from(snapshot(external: false, percent: 100)) == .onBattery)
    }

    @Test func fullMeansFullyChargedOnlyWhilePluggedIn() {
        #expect(PowerStatus.from(snapshot(external: true, percent: 100)) == .fullyCharged)
        #expect(PowerStatus.from(snapshot(external: true, percent: 80, charged: true)) == .fullyCharged)
    }

    @Test func noBattery() {
        let none = BatteryReading(hasBattery: false, percent: 0, isExternalPower: true, isCharged: false,
                                  providesTimeRemaining: false, systemTimeToEmptyMinutes: nil,
                                  descriptionTimeToEmptyMinutes: nil, timeToFullMinutes: nil)
        #expect(PowerStatus.from(none) == .noBattery)
    }

    @Test func labelsAlwaysAgreeWithPowerStatus() {
        let estimates: [BatteryTimeEstimate] = [.remaining(minutes: 100), .untilFull(minutes: 100), .calculating, .notApplicable]
        for power in [PowerStatus.onBattery, .charging, .fullyCharged] {
            for estimate in estimates {
                let state = BatteryState(hasBattery: true, percent: 50, power: power, estimate: estimate)
                if power == .onBattery { #expect(!state.detailText.contains("until full") && !state.detailText.contains("Calculating")) }
                if power == .charging { #expect(state.statusText == "Charging" && !state.detailText.contains("remaining")) }
            }
        }
    }
}

@Suite struct CalendarLogicTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, minutes: Double, allDay: Bool = false) -> UpcomingEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return UpcomingEvent(id: id, title: id, start: start, end: start.addingTimeInterval(3600),
                             isAllDay: allDay, color: .fallback)
    }

    @Test func picksSoonestTimedEventWithin24Hours() {
        let events = [event("late", minutes: 300), event("allDay", minutes: 5, allDay: true),
                      event("past", minutes: -20), event("soon", minutes: 20), event("far", minutes: 25 * 60)]
        #expect(UpcomingEventSelector.next(from: events, now: now)?.id == "soon")
        #expect(UpcomingEventSelector.next(from: [], now: now) == nil)
    }

    @Test func formatsStartText() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let locale = Locale(identifier: "en_US")
        let noon = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12)) ?? now
        func text(_ minutes: Double) -> String {
            CalendarFormatting.startText(start: noon.addingTimeInterval(minutes * 60), now: noon,
                                         calendar: calendar, locale: locale)
        }
        #expect(text(12) == "in 12 min")
        #expect(text(0) == "Now")
        #expect(text(14 * 60).hasPrefix("Tomorrow"))
    }

    @Test func mapsAuthorizationStatus() {
        #expect(CalendarService.map(.notDetermined) == .notDetermined)
        #expect(CalendarService.map(.fullAccess) == .authorized)
        #expect(CalendarService.map(.denied) == .denied)
        #expect(CalendarService.map(.writeOnly) == .denied)
    }
}

@Suite struct RecordingIndicatorTests {
    @Test func dotsWidthReservesRoomForActiveIndicatorsOnly() {
        #expect(RecordingDots.width(microphone: false, camera: false) == 0)
        #expect(RecordingDots.width(microphone: true, camera: false) == RecordingDots.dotSize)
        #expect(RecordingDots.width(microphone: true, camera: true) == RecordingDots.dotSize * 2 + RecordingDots.dotSpacing)
    }
}

@Suite struct DownloadScannerTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macisland-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func detectsEveryBrowserPartialExtensionAndStripsIt() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.zip.crdownload", "b.iso.opdownload", "c.mp4.part", "done.txt"] {
            try Data(repeating: 1, count: 10).write(to: folder.appendingPathComponent(name))
        }
        guard case .snapshot(let snapshot) = DownloadScanner.scanSynchronously(directory: folder, watching: []) else {
            Issue.record("expected a snapshot"); return
        }
        #expect(Set(snapshot.partials.map(\.displayName)) == ["a.zip", "b.iso", "c.mp4"])
        #expect(snapshot.finalNames == ["done.txt"])
    }

    @Test func safariPackageSizeIsRecursive() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("x.dmg.download/sub")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: folder.appendingPathComponent("x.dmg.download/Info.plist"))
        try Data(repeating: 1, count: 2000).write(to: package.appendingPathComponent("data"))
        guard case .snapshot(let snapshot) = DownloadScanner.scanSynchronously(directory: folder, watching: []) else {
            Issue.record("expected a snapshot"); return
        }
        #expect(snapshot.partials.first?.bytes == 2100)
        #expect(snapshot.partials.first?.displayName == "x.dmg")
    }

    @Test func formatsSizes() {
        #expect(DownloadFormatting.size(0) == "Starting…")
        #expect(DownloadFormatting.size(420_000_000).hasSuffix("MB"))
    }
}

@Suite struct NowPlayingUpgradeTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func progressInterpolatesWhilePlayingAndFreezesWhenPaused() {
        var progress = PlaybackProgress(duration: 200, anchorPosition: 30, anchorDate: start, isPlaying: true)
        #expect(abs(progress.position(at: start.addingTimeInterval(10)) - 40) < 0.001)
        #expect(progress.position(at: start.addingTimeInterval(1_000)) == 200)
        progress.isPlaying = false
        #expect(progress.position(at: start.addingTimeInterval(99)) == 30)
    }

    @Test func formatsClockAndClampsScrubFraction() {
        #expect(PlaybackFormatting.clock(187.9) == "3:07")
        #expect(PlaybackFormatting.clock(3787) == "1:03:07")
        #expect(PlaybackFormatting.fraction(forX: -5, width: 200) == 0)
        #expect(PlaybackFormatting.fraction(forX: 500, width: 200) == 1)
    }

    @Test func parsesSpotifyDurationPositionAndAdverts() {
        let spotify = ScriptableMusicProvider.spotify
        guard case .track(let track) = spotify.parse(userInfo: [
            "Player State": "Playing", "Name": "N", "Duration": 215_000, "Playback Position": 12.5,
            "Track ID": "spotify:track:abc"]) else { Issue.record("expected a track"); return }
        #expect(track.duration == 215 && track.positionHint == 12.5 && !track.isAdvert)
        guard case .track(let ad) = spotify.parse(userInfo: [
            "Player State": "Playing", "Name": "Ad", "Duration": 30_000, "Track ID": "spotify:ad:x"]) else {
            Issue.record("expected a track"); return
        }
        #expect(ad.isAdvert)
    }

    @Test func soundwaveIsStillWhenEnergyIsZeroAndMovesAtFullEnergy() {
        #expect(SoundwaveModel.heights(at: 0, energy: 0) == SoundwaveModel.heights(at: 9.1, energy: 0))
        #expect(SoundwaveModel.heights(at: 0, energy: 1) != SoundwaveModel.heights(at: 0.7, energy: 1))
        #expect(SoundwaveModel.heights(at: 3, energy: 1).count == SoundwaveModel.barCount)
    }

    @Test func artworkColorIsVisibleOnBlack() {
        let navy = ArtworkProcessor.visibleOnBlack(red: 10 / 255, green: 10 / 255, blue: 60 / 255)
        #expect(max(navy.red, navy.green, navy.blue) >= 0.85)
        let gray = ArtworkProcessor.visibleOnBlack(red: 0.5, green: 0.5, blue: 0.5)
        #expect(gray.red > 0.85 && abs(gray.red - gray.blue) < 0.01)
    }
}

@MainActor
@Suite struct SettingsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "macisland.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test func everyFeatureIsOnByDefault() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(FeatureFlag.allCases.allSatisfy { settings.isEnabled($0) })
    }

    @Test func toggleStatePersistsAcrossInstances() {
        let defaults = freshDefaults()
        AppSettings(defaults: defaults).setEnabled(.calendar, false)
        let relaunched = AppSettings(defaults: defaults)
        #expect(!relaunched.isEnabled(.calendar))
        #expect(relaunched.isEnabled(.battery))
    }

    @Test func onlyEnabledFeaturesStartAndDisablingStopsThem() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.setEnabled(.calendar, false)
        settings.setEnabled(.downloads, false)
        let store = IslandFeatureStore(settings: settings)
        store.start()
        #expect(!store.runningFeatures.contains(.calendar) && !store.runningFeatures.contains(.downloads))
        settings.setEnabled(.recording, false)
        #expect(!store.recording.isRunning)
        settings.setEnabled(.calendar, true)
        #expect(store.calendar.isRunning)
        store.stop()
        #expect(store.runningFeatures.isEmpty)
    }
}

private final class FakeLoginItem: LoginItemService, @unchecked Sendable {
    var status: SMAppService.Status = .notRegistered
    var failRegister = false
    struct Failure: Error {}
    func register() throws { if failRegister { throw Failure() }; status = .enabled }
    func unregister() throws { status = .notRegistered }
}

@MainActor
@Suite struct LaunchAtLoginTests {
    @Test func reflectsRealStatusAndRevertsOnFailure() {
        let service = FakeLoginItem()
        let model = LaunchAtLoginModel(service: service)
        #expect(!model.isOn)
        model.setEnabled(true)
        #expect(model.isOn)
        service.status = .notRegistered
        service.failRegister = true
        model.setEnabled(true)
        #expect(!model.isOn && model.errorMessage != nil)
    }

    @Test func requiresApprovalCountsAsOnAndNeedsTheButton() {
        let service = FakeLoginItem()
        service.status = .requiresApproval
        let model = LaunchAtLoginModel(service: service)
        #expect(model.isOn && model.state == .requiresApproval)
    }
}

@MainActor
@Suite struct AppearanceTests {
    private func freshSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "macisland.tests.\(UUID().uuidString)") ?? .standard)
    }

    @Test func defaultsMatchTodaysBehavior() {
        let settings = freshSettings()
        #expect(settings.displaySelection == .builtIn && settings.expandTrigger == .click)
        #expect(settings.compactPreference == .automatic && settings.accent == .white)
        #expect(settings.hapticsEnabled && settings.playfulAnimationsEnabled)
    }

    @Test func displayResolutionFallsBackToMain() {
        let built = IslandPositionManager.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isBuiltIn: true)
        let external = IslandPositionManager.Display(id: 2, frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440), isBuiltIn: false)
        #expect(IslandPositionManager.resolveDisplay(.builtIn, among: [built, external], cursor: .zero)?.id == 1)
        #expect(IslandPositionManager.resolveDisplay(.builtIn, among: [external], cursor: .zero)?.id == 2)
        #expect(IslandPositionManager.resolveDisplay(.followCursor, among: [built, external], cursor: CGPoint(x: 2000, y: 100))?.id == 2)
        #expect(IslandPositionManager.resolveDisplay(.followCursor, among: [built, external], cursor: CGPoint(x: -5, y: -5))?.id == 1)
    }

    @Test func followCursorNeverMovesWhileExpandedOrAnimating() {
        #expect(IslandPositionManager.shouldFollowCursor(selection: .followCursor, isExpanded: false, isTransitioning: false,
                                                         currentDisplayID: 1, targetDisplayID: 2))
        #expect(!IslandPositionManager.shouldFollowCursor(selection: .followCursor, isExpanded: true, isTransitioning: false,
                                                          currentDisplayID: 1, targetDisplayID: 2))
        #expect(!IslandPositionManager.shouldFollowCursor(selection: .followCursor, isExpanded: false, isTransitioning: true,
                                                          currentDisplayID: 1, targetDisplayID: 2))
    }

    @Test func bounceStaysWithinItsBudgetAndRespectsThePolicy() {
        #expect(ArrivalBounce.peak.width <= 6 && ArrivalBounce.peak.height <= 2)
        #expect(ArrivalBounce.canBounce(playfulEnabled: true, reduceMotion: false, isExpanded: false, isTransitioning: false, isBouncing: false))
        #expect(!ArrivalBounce.canBounce(playfulEnabled: true, reduceMotion: true, isExpanded: false, isTransitioning: false, isBouncing: false))
        #expect(!ArrivalBounce.canBounce(playfulEnabled: true, reduceMotion: false, isExpanded: true, isTransitioning: false, isBouncing: false))
    }

    @Test func pinnedChoicesOnlyOfferEnabledFeatures() {
        let settings = freshSettings()
        settings.setCompactPreference(.calendar)
        settings.setEnabled(.calendar, false)
        #expect(!settings.availableCompactPreferences.contains(.calendar))
        #expect(settings.effectiveCompactPreference == .automatic)
    }

    @Test func accentPresetsAreBrightOnBlack() {
        for option in AccentOption.allCases where option != .albumArt {
            let color = AccentPalette.color(for: option)
            #expect(max(color.red, color.green, color.blue) >= 0.9)
        }
    }
}

@Suite struct ArtworkPauseStyleTests {
    @Test func playingIsFullSizeAndPausedShrinksAndDims() {
        let playing = ArtworkPauseStyle.appearance(pausedProgress: 0, reduceMotion: false)
        #expect(playing.scale == 1 && playing.darkening == 0)
        let paused = ArtworkPauseStyle.appearance(pausedProgress: 1, reduceMotion: false)
        #expect(paused.scale == 0.85 && abs(paused.darkening - 0.45) < 1e-9)
    }

    @Test func reduceMotionDimsWithoutScaling() {
        let paused = ArtworkPauseStyle.appearance(pausedProgress: 1, reduceMotion: true)
        #expect(paused.scale == 1 && abs(paused.darkening - 0.45) < 1e-9)
    }
}

@Suite struct PlaybackMotionTests {
    @Test func springStartsAtOnceAndEndsExactly() {
        #expect(PlaybackMotion.springProgress(0) == 0)
        #expect(PlaybackMotion.springProgress(0.016) > 0.03)
        #expect(PlaybackMotion.springProgress(PlaybackMotion.duration) == 1)
    }

    @Test func aQuickToggleContinuesFromWhereTheVisualsAre() {
        let start = Date(timeIntervalSince1970: 1_000)
        let playing = PlaybackVisual.settled(isPlaying: true)
        let paused = playing.changing(isPlaying: false, at: start)
        let midway = start.addingTimeInterval(0.1)
        let resumed = paused.changing(isPlaying: true, at: midway)
        #expect(abs(resumed.pausedProgress(at: midway) - paused.pausedProgress(at: midway)) < 1e-9)
        #expect(resumed.pausedProgress(at: midway.addingTimeInterval(1)) == 0)
    }

    @Test func scheduleEndsWhenSettledAndNeverEndsWhilePlaying() {
        let now = Date(timeIntervalSince1970: 5_000)
        let settling = PlaybackMotionSchedule(changedAt: now, keepsTicking: false, isActive: true)
        let frames = Array(settling.entries(from: now, mode: .normal))
        #expect(frames.first == now && frames.count > 20 && frames.count < 40)
        #expect(Array(PlaybackMotionSchedule(changedAt: now, keepsTicking: false, isActive: false)
            .entries(from: now, mode: .normal)).count == 1)
        let playing = PlaybackMotionSchedule(changedAt: .distantPast, keepsTicking: true, isActive: true)
        #expect(Array(playing.entries(from: now, mode: .normal).prefix(1_000)).count == 1_000)
    }
}

@Suite struct SwipeGestureTrackerTests {
    private func sample(_ phase: NSEvent.Phase, _ dx: CGFloat, dy: CGFloat = 0, inverted: Bool = true,
                        momentum: NSEvent.Phase = []) -> ScrollSample {
        ScrollSample(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy, isDirectionInvertedFromDevice: inverted)
    }

    private func swipe(_ tracker: inout SwipeGestureTracker, steps: Int, perStep: CGFloat, dy: CGFloat = 0,
                       inverted: Bool = true) -> [SwipeDirection] {
        var results: [SwipeDirection] = []
        for index in 0..<steps {
            if let direction = tracker.handle(sample(index == 0 ? .began : .changed, perStep, dy: dy, inverted: inverted)) {
                results.append(direction)
            }
        }
        if let direction = tracker.handle(sample(.ended, 0, inverted: inverted)) { results.append(direction) }
        return results
    }

    @Test func fingerDirectionDecidesNextOrPreviousForBothScrollSettings() {
        var tracker = SwipeGestureTracker()
        #expect(swipe(&tracker, steps: 10, perStep: -6) == [.next])
        #expect(swipe(&tracker, steps: 10, perStep: 6) == [.previous])
        #expect(swipe(&tracker, steps: 10, perStep: 6, inverted: false) == [.next])
        #expect(swipe(&tracker, steps: 10, perStep: -6, inverted: false) == [.previous])
    }

    @Test func triggersAtTheThresholdAndOncePerGesture() {
        var tracker = SwipeGestureTracker()
        #expect(swipe(&tracker, steps: 6, perStep: -6).isEmpty)
        #expect(swipe(&tracker, steps: 8, perStep: -5) == [.next])
        #expect(swipe(&tracker, steps: 60, perStep: -9) == [.next])
    }

    @Test func ignoresVerticalMomentumAndMouseWheel() {
        var vertical = SwipeGestureTracker()
        #expect(swipe(&vertical, steps: 20, perStep: -1, dy: 14).isEmpty)
        var inertia = SwipeGestureTracker()
        #expect((0..<30).allSatisfy { inertia.handle(sample([], -30, momentum: .changed)) == nil })
        var wheel = SwipeGestureTracker()
        #expect((0..<30).allSatisfy { wheel.handle(sample([], -30)) == nil })
    }
}

@MainActor
@Suite struct ChargingFlashTests {
    private func reading(external: Bool, percent: Int = 60) -> BatteryReading {
        BatteryReading(hasBattery: true, percent: percent, isExternalPower: external, isCharged: false,
                       providesTimeRemaining: true, systemTimeToEmptyMinutes: 300,
                       descriptionTimeToEmptyMinutes: 300, timeToFullMinutes: 60)
    }

    @Test func onlyAPlugInTransitionIsReported() {
        var current = reading(external: true)
        let service = BatteryService()
        service.readingProvider = { current }
        var plugIns: [Int] = []
        service.onPlugIn = { plugIns.append($0) }
        service.start()
        #expect(plugIns.isEmpty)                       // launch while plugged in
        current = reading(external: false); service.refresh()
        #expect(plugIns.isEmpty)                       // unplug
        current = reading(external: true, percent: 61); service.refresh(); service.refresh()
        #expect(plugIns == [61])                       // one plug-in, not repeated
        service.stop()
    }

    @Test func constantsMatchTheSpec() {
        #expect(ChargingFlash.duration == .milliseconds(2500))
        #expect(ChargingFlash.minimumInterval == .seconds(5))
        #expect(SwipeToSkip.threshold == 40)
    }
}
