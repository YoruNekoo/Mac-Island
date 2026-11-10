import Testing
import CoreGraphics
@testable import MacIsland

@Suite struct PositionTests {
    @Test func topCenteredOnPrimaryScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = IslandPositionManager.panelFrame(size: CGSize(width: 150, height: 34), screenFrame: screen)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.midX == screen.midX)
    }

    @Test func topEdgeIdenticalAcrossStatesOnOffsetScreen() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let m = IslandMetrics.standard
        let a = IslandPositionManager.panelFrame(size: m.compactSize, screenFrame: screen)
        let b = IslandPositionManager.panelFrame(size: m.expandedMaxSize, screenFrame: screen)
        #expect(a.maxY == b.maxY)
        #expect(a.midX == b.midX)
        #expect(a.maxY == screen.maxY)
    }
}

@Suite struct DynamicSizeTests {
    private let m = IslandMetrics.standard

    @Test func clampsContentToMinAndMax() {
        #expect(m.clampedExpandedSize(forContent: CGSize(width: 10, height: 10)) == m.expandedMinSize)
        #expect(m.clampedExpandedSize(forContent: CGSize(width: 900, height: 900)) == m.expandedMaxSize)
        // 188 x 65 content + 16 pt side padding + 34 pt tab strip + 12 pt bottom padding.
        #expect(m.clampedExpandedSize(forContent: CGSize(width: 188, height: 65)) == CGSize(width: 260, height: 111))
    }

    @Test func compactSizeIsFixed() {
        #expect(m.compactSize == CGSize(width: 150, height: 34))
        #expect(m.size(expanded: false, expandedSize: m.expandedMaxSize) == m.compactSize)
    }

    @Test func shapeStaysTopCenteredInTheStablePanel() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = IslandPositionManager.panelFrame(size: m.expandedMaxSize, screenFrame: screen)
        for size in [m.compactSize, m.expandedMinSize, CGSize(width: 300, height: 120), m.expandedMaxSize] {
            let shape = IslandPositionManager.shapeFrame(size: size, panelFrame: panel)
            #expect(shape.maxY == panel.maxY)
            #expect(abs(shape.midX - panel.midX) < 0.001)
        }
    }

    @Test func hitRegionHasSquareTopAndRoundedBottomCorners() {
        let shape = CGRect(x: 100, y: 100, width: 150, height: 34)   // AppKit: bottom edge is minY
        #expect(IslandPositionManager.shapeContains(CGPoint(x: 101, y: 133), shape: shape, bottomRadius: 17))
        #expect(!IslandPositionManager.shapeContains(CGPoint(x: 101, y: 101), shape: shape, bottomRadius: 17))
        #expect(!IslandPositionManager.shapeContains(CGPoint(x: 99, y: 120), shape: shape, bottomRadius: 17))
    }
}

/// Milestone 6B: Mac Island never shows on a display with a camera notch.
@Suite struct NotchedDisplayTests {
    typealias Display = IslandPositionManager.Display
    let notchedBuiltIn = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isBuiltIn: true, hasNotch: true)
    let plainBuiltIn = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isBuiltIn: true)
    let external = Display(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), isBuiltIn: false)
    let cursorOnBuiltIn = CGPoint(x: 700, y: 500)
    let cursorOnExternal = CGPoint(x: 2500, y: 700)

    @Test func notchedOnlyHidesForEverySelection() {
        for selection in DisplaySelection.allCases {
            #expect(IslandPositionManager.resolveDisplay(selection, among: [notchedBuiltIn], cursor: cursorOnBuiltIn) == nil)
        }
    }

    @Test func notchedPlusExternalAlwaysUsesExternal() {
        for main in [[notchedBuiltIn, external], [external, notchedBuiltIn]] {
            for selection in DisplaySelection.allCases {
                #expect(IslandPositionManager.resolveDisplay(selection, among: main, cursor: cursorOnBuiltIn)?.id == 2)
            }
        }
    }

    @Test func followCursorStaysOnLastValidDisplay() {
        let third = Display(id: 3, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), isBuiltIn: false)
        let all = [notchedBuiltIn, external, third]
        #expect(IslandPositionManager.resolveDisplay(.followCursor, among: all, cursor: cursorOnBuiltIn, current: 3)?.id == 3)
        #expect(IslandPositionManager.resolveDisplay(.followCursor, among: all, cursor: cursorOnExternal, current: 3)?.id == 2)
        #expect(IslandPositionManager.shouldFollowCursor(selection: .followCursor, isExpanded: false, isTransitioning: false,
                                                         currentDisplayID: 3, targetDisplayID: 3) == false)
    }

    @Test func nonNotchedBuiltInBehavesAsBefore() {
        let all = [plainBuiltIn, external]
        #expect(IslandPositionManager.resolveDisplay(.builtIn, among: all, cursor: .zero)?.id == 1)
        #expect(IslandPositionManager.resolveDisplay(.main, among: all, cursor: .zero)?.id == 1)
        #expect(IslandPositionManager.resolveDisplay(.main, among: [external, plainBuiltIn], cursor: .zero)?.id == 2)
        #expect(IslandPositionManager.resolveDisplay(.followCursor, among: all, cursor: cursorOnExternal)?.id == 2)
        #expect(IslandPositionManager.resolveDisplay(.followCursor, among: all, cursor: CGPoint(x: -50, y: -50))?.id == 1)
    }

    @Test func unpluggingExternalWhileShownThere() {
        // Shown on the external display, then it is removed.
        for selection in DisplaySelection.allCases {
            #expect(IslandPositionManager.resolveDisplay(selection, among: [notchedBuiltIn], cursor: cursorOnBuiltIn, current: 2) == nil)
            #expect(IslandPositionManager.resolveDisplay(selection, among: [plainBuiltIn], cursor: cursorOnBuiltIn, current: 2)?.id == 1)
        }
    }
}
