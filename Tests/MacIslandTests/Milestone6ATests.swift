import Testing
import CoreServices
import SwiftUI
@testable import MacIsland

@Suite struct WholeSecondScheduleTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func countdownAnchorIsTheFractionalPart() {
        #expect(abs(WholeSecondSchedule.anchorForCountdown(remainingSeconds: 125.4, now: now).timeIntervalSince(now) - 0.4) < 1e-9)
    }

    @Test func countUpAnchorIsTheRestOfTheSecond() {
        #expect(abs(WholeSecondSchedule.anchorForCountUp(elapsedSeconds: 10.3, now: now).timeIntervalSince(now) - 0.7) < 1e-9)
    }

    @Test func tickingYieldsNowThenOneFramePerSecond() {
        let anchor = WholeSecondSchedule.anchorForCountdown(remainingSeconds: 125.4, now: now)
        var entries = WholeSecondSchedule(anchor: anchor, isTicking: true).entries(from: now, mode: .normal)
        let offsets = (0..<4).compactMap { _ in entries.next() }.map { $0.timeIntervalSince(now) }
        #expect(offsets[0] == 0)
        #expect(abs(offsets[1] - (0.4 + WholeSecondSchedule.slack)) < 0.001)
        #expect(abs(offsets[3] - (2.4 + WholeSecondSchedule.slack)) < 0.001)
    }

    @Test func notTickingYieldsOneFrame() {
        var entries = WholeSecondSchedule(anchor: now, isTicking: false).entries(from: now, mode: .normal)
        #expect(entries.next() == now)
        #expect(entries.next() == nil)
    }

    @Test func startingMidSecondWaitsForTheNextBoundary() {
        let anchor = WholeSecondSchedule.anchorForCountdown(remainingSeconds: 125.4, now: now)
        let start = now.addingTimeInterval(7.9)
        var entries = WholeSecondSchedule(anchor: anchor, isTicking: true).entries(from: start, mode: .normal)
        #expect(entries.next() == start)
        #expect(abs((entries.next()?.timeIntervalSince(now) ?? 0) - (8.4 + WholeSecondSchedule.slack)) < 0.001)
    }
}

@Suite struct SpokenTimeTests {
    @Test func speaksLengthsInWords() {
        #expect(TimeFormatting.spoken(seconds: 0) == "0 seconds")
        #expect(TimeFormatting.spoken(seconds: 1) == "1 second")
        #expect(TimeFormatting.spoken(seconds: 61) == "1 minute 1 second")
        #expect(TimeFormatting.spoken(seconds: 3600) == "1 hour")
        #expect(TimeFormatting.spoken(seconds: 7384) == "2 hours 3 minutes 4 seconds")
        #expect(TimeFormatting.spoken(seconds: -5) == "0 seconds")
    }
}

@Suite struct IslandAccessibilityTextTests {
    private func snapshot(title: String, artist: String, album: String) -> NowPlayingSnapshot {
        NowPlayingSnapshot(providerID: "p", providerName: "Spotify", title: title, artist: artist, album: album,
                           status: .playing, duration: nil, positionHint: nil)
    }

    @Test func trackLabelJoinsTitleArtistAlbum() {
        #expect(IslandAccessibility.trackLabel(snapshot(title: "Song", artist: "Band", album: "Record")) == "Song, Band, Record")
    }

    @Test func trackLabelFallsBackForEmptyParts() {
        #expect(IslandAccessibility.trackLabel(snapshot(title: "", artist: "", album: "")) == "Unknown title, Spotify")
        #expect(IslandAccessibility.trackLabel(snapshot(title: "Song", artist: "Band", album: "")) == "Song, Band")
    }
}

@Suite struct IslandPaletteTests {
    @Test func standardMatchesTheTheme() {
        let palette = IslandPalette.resolved(increaseContrast: false, reduceTransparency: false)
        #expect(palette == IslandPalette.standard)
        #expect(!palette.opaque && palette.pausedOpacity == 0.55)
    }

    @Test func increaseContrastStrengthensSecondaryTextTrackAndOutline() {
        let palette = IslandPalette.resolved(increaseContrast: true, reduceTransparency: false)
        #expect(palette.secondaryText == IslandTheme.primaryText)
        #expect(palette.track != IslandTheme.track && palette.outline != IslandTheme.outline)
        #expect(palette.pausedOpacity > IslandPalette.standard.pausedOpacity)
    }

    @Test func reduceTransparencyOnlyMakesLensesOpaque() {
        let palette = IslandPalette.resolved(increaseContrast: false, reduceTransparency: true)
        #expect(palette.opaque)
        #expect(palette.secondaryText == IslandPalette.standard.secondaryText)
    }
}

@Suite struct DownloadSamplingTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macisland-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func measuresOnlyTheNamedPartials() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(repeating: 1, count: 300).write(to: folder.appendingPathComponent("a.zip.crdownload"))
        try Data(repeating: 1, count: 999).write(to: folder.appendingPathComponent("other.txt"))
        let sizes = DownloadScanner.measure(directory: folder, partialNames: ["a.zip.crdownload", "gone.zip.crdownload"])
        #expect(sizes["a.zip.crdownload"] == .some(300))
        #expect(sizes["gone.zip.crdownload"] == .some(nil))
        #expect(sizes.count == 2)
    }

    @Test func packageSizeIsRecursive() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("x.dmg.download")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 700).write(to: package.appendingPathComponent("data"))
        #expect(DownloadScanner.measure(directory: folder, partialNames: ["x.dmg.download"])["x.dmg.download"] == .some(700))
    }

    @Test func structuralFlagsExcludePlainModification() {
        let modifiedOnly = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod)
        #expect(modifiedOnly & DirectoryEventWatcher.structuralFlags == 0)
        for flag in [kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemRenamed] {
            #expect(FSEventStreamEventFlags(flag) & DirectoryEventWatcher.structuralFlags != 0)
        }
    }
}

@Suite struct PlaybackTimelineScheduleTests {
    @Test func settledScheduleYieldsOneFrame() {
        var entries = PlaybackMotionSchedule(changedAt: .distantPast, keepsTicking: true, isActive: false)
            .entries(from: .now, mode: .normal)
        #expect(entries.next() != nil)
        #expect(entries.next() == nil)
    }

    @Test func pausedAtRestYieldsOneFrame() {
        var entries = PlaybackMotionSchedule(changedAt: .distantPast, keepsTicking: false, isActive: true)
            .entries(from: .now, mode: .normal)
        #expect(entries.next() != nil)
        #expect(entries.next() == nil)
    }
}
