import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.49, blue: 0.41, alpha: 1),
                   ending: NSColor(srgbRed: 0.04, green: 0.23, blue: 0.20, alpha: 1))!.draw(in: background, angle: -70)
        let eye = NSBezierPath()
        eye.move(to: NSPoint(x: 235, y: 512))
        eye.curve(to: NSPoint(x: 789, y: 512), controlPoint1: NSPoint(x: 395, y: 760), controlPoint2: NSPoint(x: 629, y: 760))
        eye.curve(to: NSPoint(x: 235, y: 512), controlPoint1: NSPoint(x: 629, y: 264), controlPoint2: NSPoint(x: 395, y: 264))
        eye.close()
        eye.lineWidth = 38
        eye.lineJoinStyle = .round
        NSColor(srgbRed: 0.76, green: 0.94, blue: 0.82, alpha: 1).setStroke()
        eye.stroke()
        NSColor(srgbRed: 0.76, green: 0.94, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 421, y: 421, width: 182, height: 182)).fill()
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: 448, y: 531, width: 27, height: 27)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
