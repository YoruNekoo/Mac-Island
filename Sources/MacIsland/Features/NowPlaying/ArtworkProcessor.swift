import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Downsampled artwork plus its dominant color. `CGImage` is immutable, so sharing it is safe.
struct ProcessedArtwork: @unchecked Sendable {
    let image: CGImage
    let color: ArtworkColor
}

enum ArtworkProcessor {
    /// Largest side kept, in pixels: the biggest display size is about 60 pt, so 2x with headroom.
    static let maxPixelSize = 128

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Decodes straight to a thumbnail (never the full-size image) and extracts the color. Runs off the main actor.
    @concurrent
    static func process(_ data: Data) async -> ProcessedArtwork? {
        processSynchronously(data)
    }

    static func processSynchronously(_ data: Data) -> ProcessedArtwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return ProcessedArtwork(image: thumbnail, color: dominantColor(of: thumbnail) ?? .white)
    }

    /// Average color over the whole image (CIAreaAverage), then made clearly visible on black.
    static func dominantColor(of image: CGImage) -> ArtworkColor? {
        let filter = CIFilter.areaAverage()
        let input = CIImage(cgImage: image)
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return visibleOnBlack(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    /// Keeps the hue, but lifts saturation and brightness so the tint reads on pure black. Near-gray artwork
    /// has no meaningful hue, so it becomes a soft white.
    static func visibleOnBlack(red: Double, green: Double, blue: Double) -> ArtworkColor {
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation >= 0.12 else { return ArtworkColor(red: 0.92, green: 0.92, blue: 0.92) }
        let adjusted = NSColor(hue: hue, saturation: min(1, max(saturation, 0.55)),
                               brightness: min(1, max(brightness, 0.85)), alpha: 1)
        guard let rgb = adjusted.usingColorSpace(.sRGB) else { return .white }
        return ArtworkColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}
