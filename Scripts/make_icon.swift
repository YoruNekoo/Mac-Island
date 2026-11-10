// Generates Resources/AppIcon.icns: a dark macOS-style rounded square with a black notch at the top.
// Re-run with Scripts/make_icon.sh (uses only CoreGraphics, ImageIO and iconutil).
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // macOS icon grid: the artwork fills 824/1024 of the canvas, corner radius about 22.5%.
    let side = s * 824 / 1024
    let rect = CGRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
    let radius = side * 0.225
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.025,
                  color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(body); ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Base: dark graphite gradient, lighter toward the top.
    let base = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1),
                                                       CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])

    // Notch: square top corners (flush with the top edge), rounded bottom corners.
    let notchW = side * 0.46, notchH = side * 0.17, nr = notchH * 0.5
    let nx = rect.midX - notchW / 2, ny = rect.maxY - notchH
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: nx, y: rect.maxY + 2))
    notch.addLine(to: CGPoint(x: nx, y: ny + nr))
    notch.addArc(tangent1End: CGPoint(x: nx, y: ny), tangent2End: CGPoint(x: nx + nr, y: ny), radius: nr)
    notch.addLine(to: CGPoint(x: nx + notchW - nr, y: ny))
    notch.addArc(tangent1End: CGPoint(x: nx + notchW, y: ny), tangent2End: CGPoint(x: nx + notchW, y: ny + nr), radius: nr)
    notch.addLine(to: CGPoint(x: nx + notchW, y: rect.maxY + 2))
    notch.closeSubpath()
    ctx.addPath(notch); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()

    // Subtle highlight: a faint white glow fading from the top edge.
    let glow = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(notch); ctx.addRect(rect); ctx.clip(using: .evenOdd)   // keep the notch pure black
    ctx.drawLinearGradient(glow, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.maxY - side * 0.5), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    // Hairline inner edge.
    ctx.addPath(body); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(max(1, s / 512)); ctx.strokePath()
    return ctx.makeImage()
}

let args = CommandLine.arguments
guard args.count == 2 else { FileHandle.standardError.write(Data("usage: make_icon <out.iconset>\n".utf8)); exit(2) }
let dir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        guard let image = render(size: base * scale),
              let dest = CGImageDestinationCreateWithURL(
                dir.appendingPathComponent("icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png") as CFURL,
                UTType.png.identifier as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { exit(1) }
    }
}
