// Draws the Bambu Bar icon into an .iconset folder: a dark tile holding a printer enclosure, the part
// inside built from coloured layers, the newest layer glowing green under the toolhead.
// Usage: swift scripts/generate-icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    // Tile on Apple's grid: 824/1024 with a soft drop shadow.
    let tile = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let radius = s * 0.18
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()
    color(0.1, 0.1, 0.1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.20, 0.22, 0.23), color(0.07, 0.08, 0.09)])!.draw(in: tilePath, angle: -90)
    // Green bloom from below.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [color(0.10, 0.85, 0.42, 0.45), color(0.10, 0.85, 0.42, 0)])!
        .draw(fromCenter: NSPoint(x: tile.midX, y: tile.minY + tile.height * 0.18), radius: 0,
              toCenter: NSPoint(x: tile.midX, y: tile.minY + tile.height * 0.18), radius: tile.width * 0.62, options: [])
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: s * 0.002, dy: s * 0.002), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, s * 0.004)
    rim.stroke()

    let u = tile.width / 100
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        // y measured from the top of the tile.
        NSRect(x: tile.minX + x * u, y: tile.maxY - (y + h) * u, width: w * u, height: h * u)
    }

    // Enclosure frame.
    let frame = r(17, 15, 66, 72)
    let framePath = NSBezierPath(roundedRect: frame, xRadius: 8 * u, yRadius: 8 * u)
    NSGradient(colors: [color(0.36, 0.38, 0.39), color(0.16, 0.17, 0.18)])!.draw(in: framePath, angle: -90)
    // Chamber window.
    let chamber = r(23, 21, 54, 58)
    let chamberPath = NSBezierPath(roundedRect: chamber, xRadius: 4.5 * u, yRadius: 4.5 * u)
    NSGradient(colors: [color(0.05, 0.06, 0.06), color(0.10, 0.11, 0.11)])!.draw(in: chamberPath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    chamberPath.addClip()
    // Chamber light.
    NSGradient(colors: [color(1, 0.96, 0.88, 0.30), color(1, 0.96, 0.88, 0)])!.draw(in: r(23, 21, 54, 34), angle: -90)
    // Plate.
    let plate = r(28, 69, 44, 3)
    NSGradient(colors: [color(0.55, 0.52, 0.46), color(0.30, 0.29, 0.27)])!.draw(in: NSBezierPath(roundedRect: plate, xRadius: u, yRadius: u), angle: 0)

    // The part: layers stepping from white through orange to green.
    let layers: [(NSColor, CGFloat)] = [
        (color(0.96, 0.94, 0.90), 21), (color(0.96, 0.94, 0.90), 26), (color(0.93, 0.55, 0.26), 29.5),
        (color(0.93, 0.55, 0.26), 30.5), (color(0.14, 0.78, 0.68), 29), (color(0.14, 0.78, 0.68), 25.5),
        (color(0.13, 0.82, 0.42), 21.5), (color(0.13, 0.82, 0.42), 19),
    ]
    let layerH: CGFloat = 4.0
    var top: CGFloat = 69
    for (i, (c, w)) in layers.enumerated() {
        top -= layerH
        let rect = r(50 - w / 2, top, w, layerH - 0.5)
        let p = NSBezierPath(roundedRect: rect, xRadius: 1.6 * u, yRadius: 1.6 * u)
        c.setFill()
        p.fill()
        NSGradient(colors: [color(1, 1, 1, 0.30), color(1, 1, 1, 0), color(0, 0, 0, 0.30)])!.draw(in: p, angle: 0)
        if i == layers.count - 1 {
            // Fresh layer glow.
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = color(0.2, 1, 0.5, 0.9)
            glow.shadowBlurRadius = 3 * u
            glow.set()
            color(0.35, 1, 0.6).setFill()
            NSBezierPath(roundedRect: r(50 - w / 2 + 1, top, w - 2, 1), xRadius: 0.5 * u, yRadius: 0.5 * u).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    // Gantry and toolhead.
    color(0.42, 0.44, 0.45).setFill()
    NSBezierPath(rect: r(23, top - 9.5, 54, 1.6)).fill()
    let head = r(42, top - 12.5, 16, 9)
    NSGradient(colors: [color(0.97, 0.97, 0.97), color(0.72, 0.73, 0.74)])!.draw(in: NSBezierPath(roundedRect: head, xRadius: 2 * u, yRadius: 2 * u), angle: -90)
    color(0.13, 0.82, 0.42).setFill()
    NSBezierPath(roundedRect: r(44, top - 10.5, 6, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
    let nozzle = NSBezierPath()
    nozzle.move(to: NSPoint(x: tile.minX + 47.5 * u, y: tile.maxY - (top - 3.5) * u))
    nozzle.line(to: NSPoint(x: tile.minX + 52.5 * u, y: tile.maxY - (top - 3.5) * u))
    nozzle.line(to: NSPoint(x: tile.minX + 51 * u, y: tile.maxY - (top - 0.6) * u))
    nozzle.line(to: NSPoint(x: tile.minX + 49 * u, y: tile.maxY - (top - 0.6) * u))
    nozzle.close()
    color(1, 0.62, 0.30).setFill()
    nozzle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Glass sheen and rim.
    NSGraphicsContext.saveGraphicsState()
    chamberPath.addClip()
    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: chamber.minX + 14 * u, y: chamber.maxY))
    sheen.line(to: NSPoint(x: chamber.minX + 30 * u, y: chamber.maxY))
    sheen.line(to: NSPoint(x: chamber.minX + 4 * u, y: chamber.minY))
    sheen.line(to: NSPoint(x: chamber.minX - 12 * u, y: chamber.minY))
    sheen.close()
    color(1, 1, 1, 0.07).setFill()
    sheen.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.22).setStroke()
    chamberPath.lineWidth = max(1, 0.7 * u)
    chamberPath.stroke()
    color(1, 1, 1, 0.25).setStroke()
    let frameRim = NSBezierPath(roundedRect: frame.insetBy(dx: 0.3 * u, dy: 0.3 * u), xRadius: 7.8 * u, yRadius: 7.8 * u)
    frameRim.lineWidth = max(1, 0.6 * u)
    frameRim.stroke()
    // Status strip.
    NSGraphicsContext.saveGraphicsState()
    let led = NSShadow()
    led.shadowColor = color(0.2, 1, 0.5, 0.9)
    led.shadowBlurRadius = 2.5 * u
    led.set()
    color(0.25, 0.95, 0.52).setFill()
    NSBezierPath(roundedRect: r(42, 82.2, 16, 1.6), xRadius: 0.8 * u, yRadius: 0.8 * u).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
print(out)
