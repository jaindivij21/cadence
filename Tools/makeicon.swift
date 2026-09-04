// Draws the app icon from scratch so the repo carries no binary artwork.
// Usage: swift Tools/makeicon.swift <output.iconset directory>

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Cadence.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    ctx.setShouldAntialias(true)

    let s = size
    let inset = s * 0.055
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)

    // Body
    ctx.saveGState()
    squircle.addClip()
    let bg = NSGradient(colors: [color(0x1A2130), color(0x0A0C11)])
    bg?.draw(in: rect, angle: -90)

    // Soft teal glow behind the mark
    let glow = NSGradient(colors: [color(0x5AD7C8, 0.16), color(0x5AD7C8, 0)])
    glow?.draw(
        fromCenter: NSPoint(x: rect.midX, y: rect.midY),
        radius: 0,
        toCenter: NSPoint(x: rect.midX, y: rect.midY),
        radius: rect.width * 0.72,
        options: []
    )
    ctx.restoreGState()

    // Rim light
    squircle.lineWidth = s * 0.006
    color(0xFFFFFF, 0.10).setStroke()
    squircle.stroke()

    let center = NSPoint(x: rect.midX, y: rect.midY)
    let ringRadius = rect.width * 0.30
    let ringWidth = rect.width * 0.088

    // Track
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
    track.lineWidth = ringWidth
    color(0xFFFFFF, 0.08).setStroke()
    track.stroke()

    // Progress sweep, drawn as short segments so it can carry a gradient.
    let startAngle: CGFloat = 90
    let sweep: CGFloat = 260
    let steps = 180
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1)
        let a0 = startAngle - sweep * t
        let a1 = startAngle - sweep * (CGFloat(i + 1) / CGFloat(steps))
        let segment = NSBezierPath()
        segment.appendArc(withCenter: center, radius: ringRadius, startAngle: a0, endAngle: a1, clockwise: true)
        segment.lineWidth = ringWidth
        segment.lineCapStyle = .round
        let from = color(0x5AD7C8)
        let to = color(0x4A9BFF)
        let mixed = from.blended(withFraction: t, of: to) ?? from
        mixed.setStroke()
        segment.stroke()
    }

    // Centre dot: the beat.
    let dotRadius = rect.width * 0.105
    let dot = NSBezierPath(ovalIn: NSRect(
        x: center.x - dotRadius,
        y: center.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))
    color(0xF2F4F8).setFill()
    dot.fill()

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let variants: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for variant in variants {
    let image = drawIcon(size: variant.px)
    write(image, to: "\(outputDir)/\(variant.name).png")
}

print("Wrote \(variants.count) icon sizes to \(outputDir)")
