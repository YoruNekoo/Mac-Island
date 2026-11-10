import SwiftUI

extension Color {
    static let microphoneIndicator = Color.orange
    static let cameraIndicator = Color.green
}

/// Compact-notch indicator: an orange microphone glyph and a green camera glyph.
///
/// The colors keep the macOS convention (orange for the microphone, green for the camera). The glyph is what tells
/// them apart without color, and VoiceOver reads the same words as the expanded status row.
struct RecordingDots: View {
    let isMicrophoneInUse: Bool
    let isCameraInUse: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Each glyph is drawn inside a square this size.
    static let dotSize: CGFloat = 9
    static let dotSpacing = IslandSpacing.m

    /// Width taken by the dots, so the compact content can leave room for them.
    static func width(microphone: Bool, camera: Bool) -> CGFloat {
        let count = (microphone ? 1 : 0) + (camera ? 1 : 0)
        return count == 0 ? 0 : CGFloat(count) * dotSize + CGFloat(count - 1) * dotSpacing
    }

    var body: some View {
        HStack(spacing: Self.dotSpacing) {
            if isMicrophoneInUse { dot(.microphoneIndicator, symbol: "mic.fill", label: "Microphone in use") }
            if isCameraInUse { dot(.cameraIndicator, symbol: "video.fill", label: "Camera in use") }
        }
        .animation(IslandAnimations.contentSwitch, value: isMicrophoneInUse)
        .animation(IslandAnimations.contentSwitch, value: isCameraInUse)
    }

    private func dot(_ color: Color, symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: Self.dotSize, height: Self.dotSize)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            .accessibilityLabel(label)
    }
}

/// Expanded-notch status line. Sits in the otherwise empty bottom padding, so it never changes the
/// height available to the feature views. Shows nothing when neither device is in use.
struct RecordingStatusRow: View {
    @Environment(\.islandPalette) private var palette
    @Environment(IslandFeatureStore.self) private var store

    var body: some View {
        let recording = store.recording
        HStack(spacing: IslandSpacing.xxl) {
            if recording.isMicrophoneInUse { item("Microphone in use", symbol: "mic.fill", color: .microphoneIndicator) }
            if recording.isCameraInUse { item("Camera in use", symbol: "video.fill", color: .cameraIndicator) }
        }
        .animation(IslandAnimations.contentSwitch, value: recording.isMicrophoneInUse)
        .animation(IslandAnimations.contentSwitch, value: recording.isCameraInUse)
        .allowsHitTesting(false)
    }

    private func item(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: IslandSpacing.s) {
            Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(color).frame(width: 8, height: 8)
            Text(text)
                .font(IslandType.captionMedium)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}
