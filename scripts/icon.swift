import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func cross(_ center: NSPoint, span: CGFloat, width: CGFloat, color: NSColor) {
    let h = span / 2, w = width / 2
    let points: [(CGFloat, CGFloat)] = [(-w,h),(w,h),(w,w),(h,w),(h,-w),(w,-w),(w,-h),(-w,-h),(-w,-w),(-h,-w),(-h,w),(-w,w)]
    let path = NSBezierPath()
    for (i, p) in points.enumerated() {
        let point = NSPoint(x: center.x + p.0, y: center.y + p.1)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close(); color.setFill(); path.fill()
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 1), ending: NSColor(calibratedRed: 0.18, green: 0.23, blue: 0.30, alpha: 1))!.draw(in: background, angle: 90)
        // Top view of an MX-style blue switch: housing, retaining tabs and stem.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -22); shadow.set()
        rounded(NSRect(x: 224, y: 218, width: 576, height: 576), 84, NSColor(calibratedWhite: 0.61, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        rounded(NSRect(x: 224, y: 242, width: 576, height: 552), 84, NSColor(calibratedWhite: 0.89, alpha: 1))
        rounded(NSRect(x: 278, y: 296, width: 468, height: 444), 52, NSColor(calibratedWhite: 0.75, alpha: 1))
        rounded(NSRect(x: 298, y: 316, width: 428, height: 404), 40, NSColor(calibratedRed: 0.17, green: 0.22, blue: 0.29, alpha: 1))
        for x: CGFloat in [204, 760] {
            rounded(NSRect(x: x, y: 446, width: 60, height: 136), 18, NSColor(calibratedWhite: 0.85, alpha: 1))
        }
        rounded(NSRect(x: 354, y: 350, width: 316, height: 316), 38, NSColor(calibratedRed: 0.08, green: 0.37, blue: 0.70, alpha: 1))
        let stem = NSBezierPath(roundedRect: NSRect(x: 354, y: 374, width: 316, height: 304), xRadius: 38, yRadius: 38)
        NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.56, blue: 0.92, alpha: 1), ending: NSColor(calibratedRed: 0.38, green: 0.74, blue: 1, alpha: 1))!.draw(in: stem, angle: 90)
        cross(NSPoint(x: 512, y: 526), span: 196, width: 62, color: NSColor(calibratedRed: 0.06, green: 0.24, blue: 0.44, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
