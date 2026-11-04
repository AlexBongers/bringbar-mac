// Draws the BringBar app icon and writes Icon/AppIcon.icns + Icon/icon.png.
// Run from the BringBar folder: swift Icon/make-icon.swift
import AppKit

let size: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: r, green: g, blue: b, alpha: a)
}

let coral = color(1.00, 0.40, 0.34)
let coralDeep = color(0.86, 0.18, 0.20)
let green = color(0.32, 0.88, 0.48)
let greenDeep = color(0.10, 0.60, 0.30)

func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    // macOS icon grid: 824 pt tile centred in 1024, soft drop shadow underneath.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill()
    tilePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()

    // Dark background, same family as the other menu bar apps.
    let bgTop = color(0.13, 0.14, 0.20), bgBottom = color(0.04, 0.04, 0.08)
    NSGradient(colors: [bgTop, bgBottom])!.draw(in: tile, angle: -90)

    // Warm glow behind the bag.
    let glow = NSGradient(colors: [coral.withAlphaComponent(0.30), coral.withAlphaComponent(0)])!
    glow.draw(fromCenter: NSPoint(x: 500, y: 470), radius: 0, toCenter: NSPoint(x: 500, y: 470), radius: 400, options: [])

    // Shopping bag body.
    let body = NSRect(x: 282, y: 236, width: 436, height: 400)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 64, yRadius: 64)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: coral.withAlphaComponent(0.85).cgColor)
    coral.setFill()
    bodyPath.fill()
    ctx.restoreGState()
    NSGradient(colors: [coral, coralDeep])!.draw(in: bodyPath, angle: -90)

    // Top fold of the bag: a slightly lighter band.
    ctx.saveGState()
    bodyPath.addClip()
    color(1, 1, 1, 0.14).setFill()
    NSRect(x: body.minX, y: body.maxY - 70, width: body.width, height: 70).fill()
    ctx.restoreGState()

    // Handle: an arch above the bag, with glow.
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 392, y: body.maxY - 36))
    handle.curve(to: NSPoint(x: 608, y: body.maxY - 36),
                 controlPoint1: NSPoint(x: 392, y: 800), controlPoint2: NSPoint(x: 608, y: 800))
    handle.lineWidth = 42
    handle.lineCapStyle = .round
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: coral.withAlphaComponent(0.8).cgColor)
    coral.setStroke()
    handle.stroke()
    ctx.restoreGState()

    // Two dots where the handle meets the bag.
    color(0.10, 0.08, 0.12, 0.55).setFill()
    for x in [392.0, 608.0] {
        NSBezierPath(ovalIn: NSRect(x: x - 20, y: body.maxY - 56, width: 40, height: 40)).fill()
    }

    // "+" badge bottom right, cut out of the bag with a ring in the background colour.
    let c = NSPoint(x: 694, y: 298)
    let r: CGFloat = 128
    bgBottom.blended(withFraction: 0.35, of: bgTop)!.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r - 26, y: c.y - r - 26, width: 2 * (r + 26), height: 2 * (r + 26))).fill()
    let badge = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 50, color: green.withAlphaComponent(0.9).cgColor)
    green.setFill()
    badge.fill()
    ctx.restoreGState()
    NSGradient(colors: [green, greenDeep])!.draw(in: badge, angle: -90)

    let plus = NSBezierPath()
    plus.move(to: NSPoint(x: c.x - 62, y: c.y)); plus.line(to: NSPoint(x: c.x + 62, y: c.y))
    plus.move(to: NSPoint(x: c.x, y: c.y - 62)); plus.line(to: NSPoint(x: c.x, y: c.y + 62))
    plus.lineWidth = 34
    plus.lineCapStyle = .round
    NSColor.white.setStroke()
    plus.stroke()

    // Subtle top sheen over the whole tile.
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: NSRect(x: tile.minX, y: tile.midY + 120, width: tile.width, height: tile.height / 2 - 120), angle: -90)

    ctx.restoreGState()

    // Thin rim so the tile reads on light backgrounds.
    NSColor.white.withAlphaComponent(0.10).setStroke()
    tilePath.lineWidth = 3
    tilePath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, pixels: Int) -> Data {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: out)!
    NSGraphicsContext.current = gc
    gc.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "BringBar.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let master = renderMaster()
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try png(master, pixels: px).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
try png(master, pixels: 1024).write(to: URL(fileURLWithPath: "Icon/icon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Icon/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Icon/AppIcon.icns written" : "iconutil failed")
