import AppKit
import Foundation

let arguments = CommandLine.arguments
 guard arguments.count == 2 else {
    fputs("usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(2)
}
let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (pixels, filename) in entries {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: pixels, height: pixels)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    bounds.fill()
    let inset = CGFloat(pixels) * 0.055
    let tile = bounds.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(pixels) * 0.22
    let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.58, blue: 0.98, alpha: 1), NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.78, alpha: 1)])!
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    gradient.draw(in: tilePath, angle: -50)

    let unit = CGFloat(pixels)
    let bubble = CGRect(x: unit * 0.20, y: unit * 0.29, width: unit * 0.60, height: unit * 0.42)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: bubble, xRadius: unit * 0.08, yRadius: unit * 0.08).fill()
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: unit * 0.34, y: unit * 0.30))
    tail.line(to: NSPoint(x: unit * 0.30, y: unit * 0.19))
    tail.line(to: NSPoint(x: unit * 0.47, y: unit * 0.30))
    tail.close()
    tail.fill()

    NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.85, alpha: 1).setFill()
    let widths: [CGFloat] = [0.35, 0.44, 0.27]
    for (index, width) in widths.enumerated() {
        let y = unit * (0.58 - CGFloat(index) * 0.105)
        let line = CGRect(x: unit * 0.32, y: y, width: unit * width, height: max(1, unit * 0.035))
        NSBezierPath(roundedRect: line, xRadius: unit * 0.018, yRadius: unit * 0.018).fill()
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("could not render icon\n", stderr)
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent(filename), options: .atomic)
}
