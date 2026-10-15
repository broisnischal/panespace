// Renders the Panespace app icon: a dark macOS squircle holding an i3-style tiling layout,
// focused pane lit. Usage: swift scripts/make-icon.swift <out.png>   (1024×1024)
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Apple's icon grid: an 824pt body centred on the 1024 canvas, corner radius ≈185.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Drop shadow under the body.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0x000000, 0.35)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
rgb(0x0E1020).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

// Background: deep indigo to near-black, with a soft glow behind the focused pane.
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [rgb(0x262A4A), rgb(0x0D0F1C)])!.draw(in: body, angle: -90)
let glow = NSGradient(colors: [rgb(0x5B6CFF, 0.45), rgb(0x5B6CFF, 0)])!
glow.draw(fromCenter: NSPoint(x: 360, y: 560), radius: 0, toCenter: NSPoint(x: 360, y: 560), radius: 520, options: [])
NSGraphicsContext.restoreGraphicsState()

// Hairline rim so the shape reads on dark backgrounds.
rgb(0xFFFFFF, 0.10).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 183.5, yRadius: 183.5)
rim.lineWidth = 3
rim.stroke()

// Tiles: one focused master pane on the left, a stack of two on the right.
let area = body.insetBy(dx: 132, dy: 132)
let gap: CGFloat = 36, radius: CGFloat = 46
let leftW = (area.width - gap) * 0.54
let master = NSRect(x: area.minX, y: area.minY, width: leftW, height: area.height)
let rightX = master.maxX + gap, rightW = area.maxX - rightX, halfH = (area.height - gap) / 2
let top = NSRect(x: rightX, y: area.minY + halfH + gap, width: rightW, height: halfH)
let bottom = NSRect(x: rightX, y: area.minY, width: rightW, height: halfH)

func pane(_ r: NSRect, fill: NSGradient, stroke: NSColor, highlight: CGFloat) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    fill.draw(in: p, angle: -90)
    // Glassy top edge.
    NSGraphicsContext.saveGraphicsState()
    p.addClip()
    NSGradient(colors: [rgb(0xFFFFFF, highlight), rgb(0xFFFFFF, 0)])!
        .draw(in: NSRect(x: r.minX, y: r.maxY - 90, width: r.width, height: 90), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    stroke.setStroke()
    let edge = NSBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), xRadius: radius - 1.5, yRadius: radius - 1.5)
    edge.lineWidth = 3
    edge.stroke()
}

// Focused pane glows a little beyond its edge.
NSGraphicsContext.saveGraphicsState()
let lift = NSShadow()
lift.shadowColor = rgb(0x4F6BFF, 0.55)
lift.shadowBlurRadius = 40
lift.set()
rgb(0x4F6BFF).setFill()
NSBezierPath(roundedRect: master, xRadius: radius, yRadius: radius).fill()
NSGraphicsContext.restoreGraphicsState()

pane(master, fill: NSGradient(colors: [rgb(0x6FA8FF), rgb(0x5B4BFF)])!, stroke: rgb(0xFFFFFF, 0.28), highlight: 0.22)
let glass = NSGradient(colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0.08)])!
pane(top, fill: glass, stroke: rgb(0xFFFFFF, 0.18), highlight: 0.10)
pane(bottom, fill: glass, stroke: rgb(0xFFFFFF, 0.18), highlight: 0.10)

NSGraphicsContext.current = nil
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
