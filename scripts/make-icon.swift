// Draws NotchDeck's app icon and writes Resources/AppIcon.icns (via iconutil).
// Run: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = size / 1024
        let inset = rect.insetBy(dx: 100 * s, dy: 100 * s)
        let body = NSBezierPath(roundedRect: inset, xRadius: 185 * s, yRadius: 185 * s)
        // Deep gradient squircle.
        NSGradient(colors: [NSColor(red: 0.16, green: 0.13, blue: 0.32, alpha: 1),
                            NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)])!.draw(in: body, angle: -90)
        // Soft aurora glow.
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        let glow = NSGradient(colors: [NSColor(red: 0.35, green: 0.95, blue: 0.82, alpha: 0.55), .clear])!
        glow.draw(fromCenter: NSPoint(x: inset.midX, y: inset.minY + 120 * s), radius: 0,
                  toCenter: NSPoint(x: inset.midX, y: inset.minY + 120 * s), radius: 520 * s, options: [])
        let pink = NSGradient(colors: [NSColor(red: 1, green: 0.45, blue: 0.75, alpha: 0.45), .clear])!
        pink.draw(fromCenter: NSPoint(x: inset.maxX - 120 * s, y: inset.midY), radius: 0,
                  toCenter: NSPoint(x: inset.maxX - 120 * s, y: inset.midY), radius: 420 * s, options: [])
        NSGraphicsContext.restoreGraphicsState()
        // The expanded notch: a black panel hanging from the top edge.
        let panel = NSRect(x: inset.midX - 270 * s, y: inset.maxY - 330 * s, width: 540 * s, height: 330 * s)
        let panelPath = NSBezierPath()
        let r = 70 * s
        panelPath.move(to: NSPoint(x: panel.minX, y: panel.maxY))
        panelPath.line(to: NSPoint(x: panel.minX, y: panel.minY + r))
        panelPath.curve(to: NSPoint(x: panel.minX + r, y: panel.minY), controlPoint1: NSPoint(x: panel.minX, y: panel.minY),
                        controlPoint2: NSPoint(x: panel.minX, y: panel.minY))
        panelPath.line(to: NSPoint(x: panel.maxX - r, y: panel.minY))
        panelPath.curve(to: NSPoint(x: panel.maxX, y: panel.minY + r), controlPoint1: NSPoint(x: panel.maxX, y: panel.minY),
                        controlPoint2: NSPoint(x: panel.maxX, y: panel.minY))
        panelPath.line(to: NSPoint(x: panel.maxX, y: panel.maxY))
        panelPath.close()
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSColor.black.setFill()
        panelPath.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Album art tile, title lines and progress bar inside the panel.
        NSGradient(colors: [NSColor(red: 1, green: 0.4, blue: 0.65, alpha: 1), NSColor(red: 0.45, green: 0.3, blue: 1, alpha: 1)])!
            .draw(in: NSBezierPath(roundedRect: NSRect(x: panel.minX + 50 * s, y: panel.minY + 60 * s, width: 150 * s, height: 150 * s),
                                   xRadius: 30 * s, yRadius: 30 * s), angle: -45)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: panel.minX + 230 * s, y: panel.minY + 175 * s, width: 230 * s, height: 26 * s),
                     xRadius: 13 * s, yRadius: 13 * s).fill()
        NSColor.white.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: NSRect(x: panel.minX + 230 * s, y: panel.minY + 132 * s, width: 150 * s, height: 20 * s),
                     xRadius: 10 * s, yRadius: 10 * s).fill()
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: panel.minX + 230 * s, y: panel.minY + 75 * s, width: 250 * s, height: 14 * s),
                     xRadius: 7 * s, yRadius: 7 * s).fill()
        NSColor(red: 0.35, green: 0.95, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: panel.minX + 230 * s, y: panel.minY + 75 * s, width: 140 * s, height: 14 * s),
                     xRadius: 7 * s, yRadius: 7 * s).fill()
        return true
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(base * scale)
        let image = draw(size: pixels)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
