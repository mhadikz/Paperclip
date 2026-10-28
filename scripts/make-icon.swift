// Renders the app icon (navy squircle, gold paperclip) into an .iconset, then `iconutil`
// turns it into AppIcon.icns. Pure CoreGraphics — no SF Symbols (their license forbids
// use in app icons) and no design-tool dependency.
//
//   swift scripts/make-icon.swift <output-directory>
import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconset = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Continuous-corner squircle used by macOS icons.
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let r = rect.width * 0.2237
    let k: CGFloat = 0.552 * 0.8 // rounder than a circle arc, close to Apple's continuous corners
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    path.move(to: CGPoint(x: minX + r, y: minY))
    path.addLine(to: CGPoint(x: maxX - r, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + r), control1: CGPoint(x: maxX - r + r * (1 - k) * 1.2, y: minY), control2: CGPoint(x: maxX, y: minY + r - r * (1 - k) * 1.2))
    path.addLine(to: CGPoint(x: maxX, y: maxY - r))
    path.addCurve(to: CGPoint(x: maxX - r, y: maxY), control1: CGPoint(x: maxX, y: maxY - r + r * (1 - k) * 1.2), control2: CGPoint(x: maxX - r + r * (1 - k) * 1.2, y: maxY))
    path.addLine(to: CGPoint(x: minX + r, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - r), control1: CGPoint(x: minX + r - r * (1 - k) * 1.2, y: maxY), control2: CGPoint(x: minX, y: maxY - r + r * (1 - k) * 1.2))
    path.addLine(to: CGPoint(x: minX, y: minY + r))
    path.addCurve(to: CGPoint(x: minX + r, y: minY), control1: CGPoint(x: minX, y: minY + r - r * (1 - k) * 1.2), control2: CGPoint(x: minX + r - r * (1 - k) * 1.2, y: minY))
    path.closeSubpath()
    return path
}

/// The classic clip silhouette: three nested U-turns (radii 6 : 4 : 2 on a 24-unit grid)
/// joined by straight runs, tilted like the familiar glyph. Built in a y-up space.
func paperclipPath(center: CGPoint, height: CGFloat) -> CGPath {
    let u = height / 23            // the un-tilted shape is 12 wide × 23 tall
    let x0: CGFloat = 6 * u        // start so the bounding box is centered on the origin
    let y0: CGFloat = 7.5 * u
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: y0))
    path.addLine(to: CGPoint(x: x0, y: y0 - 13 * u))
    path.addArc(center: CGPoint(x: x0 - 6 * u, y: y0 - 13 * u), radius: 6 * u, startAngle: 0, endAngle: .pi, clockwise: true)
    path.addLine(to: CGPoint(x: x0 - 12 * u, y: y0))
    path.addArc(center: CGPoint(x: x0 - 8 * u, y: y0), radius: 4 * u, startAngle: .pi, endAngle: 0, clockwise: false)
    path.addLine(to: CGPoint(x: x0 - 4 * u, y: y0 - 13 * u))
    path.addArc(center: CGPoint(x: x0 - 6 * u, y: y0 - 13 * u), radius: 2 * u, startAngle: 0, endAngle: .pi, clockwise: true)
    path.addLine(to: CGPoint(x: x0 - 8 * u, y: y0 - 1 * u))
    var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -.pi / 4 * 0.85)
    return path.copy(using: &transform) ?? path
}

func render(size: Int, scale: Int) -> Data {
    let pixels = size * scale
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    let s = CGFloat(pixels)
    // macOS icons leave ~10% transparent margin around the squircle.
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = squirclePath(in: rect)

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000814, alpha: 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x001D3D))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient (navy → midnight)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x0A4A86), color(0x003566), color(0x001D3D), color(0x000814)] as CFArray,
        locations: [0, 0.35, 0.8, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Soft highlight sweep
    let glow = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF, alpha: 0.16), color(0xFFFFFF, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: rect.midX - rect.width * 0.25, y: rect.maxY - rect.height * 0.1), startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.9, options: [])
    ctx.restoreGState()

    // Paperclip: soft shadow stroke for depth, then a gold gradient stroke.
    let clip = paperclipPath(center: CGPoint(x: rect.midX, y: rect.midY), height: rect.height * 0.66)
    let lineWidth = rect.height * 0.66 / 23 * 2.05
    let stroked = clip.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

    ctx.saveGState()
    ctx.translateBy(x: 0, y: -rect.height * 0.014)
    ctx.addPath(stroked)
    ctx.setFillColor(color(0x000814, alpha: 0.5))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let gold = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFD60A), color(0xFFC300), color(0xE6AC00)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gold, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try render(size: size, scale: scale).write(to: iconset.appendingPathComponent(name))
    }
}
print(iconset.path)
