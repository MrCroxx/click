import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

// An abstract switch: a floating blue stem and a single contact line.
// The shallow projection keeps the mark distinct from a top-down keycap.
func cap(offset: CGFloat = 0) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 484, y: 782 + offset))
    path.curve(to: NSPoint(x: 540, y: 782 + offset), controlPoint1: NSPoint(x: 502, y: 793 + offset), controlPoint2: NSPoint(x: 522, y: 793 + offset))
    path.line(to: NSPoint(x: 784, y: 635 + offset))
    path.curve(to: NSPoint(x: 784, y: 585 + offset), controlPoint1: NSPoint(x: 812, y: 619 + offset), controlPoint2: NSPoint(x: 812, y: 601 + offset))
    path.line(to: NSPoint(x: 540, y: 438 + offset))
    path.curve(to: NSPoint(x: 484, y: 438 + offset), controlPoint1: NSPoint(x: 522, y: 427 + offset), controlPoint2: NSPoint(x: 502, y: 427 + offset))
    path.line(to: NSPoint(x: 240, y: 585 + offset))
    path.curve(to: NSPoint(x: 240, y: 635 + offset), controlPoint1: NSPoint(x: 212, y: 601 + offset), controlPoint2: NSPoint(x: 212, y: 619 + offset))
    path.close()
    return path
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (AffineTransform(scale: CGFloat(pixels) / 1024) as NSAffineTransform).concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        NSColor(calibratedRed: 0.075, green: 0.095, blue: 0.13, alpha: 1).setFill(); background.fill()
        let contact = NSBezierPath()
        contact.move(to: NSPoint(x: 242, y: 409))
        contact.line(to: NSPoint(x: 484, y: 264))
        contact.curve(to: NSPoint(x: 540, y: 264), controlPoint1: NSPoint(x: 502, y: 253), controlPoint2: NSPoint(x: 522, y: 253))
        contact.line(to: NSPoint(x: 782, y: 409))
        contact.lineWidth = 30; contact.lineCapStyle = .round; contact.lineJoinStyle = .round
        NSColor(calibratedRed: 0.25, green: 0.54, blue: 0.75, alpha: 1).setStroke(); contact.stroke()
        NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.64, alpha: 1).setFill(); cap(offset: -28).fill()
        NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.57, blue: 0.94, alpha: 1), ending: NSColor(calibratedRed: 0.43, green: 0.79, blue: 1, alpha: 1))!.draw(in: cap(), angle: 90)
        // The small cross slot is the only literal reference to an MX stem.
        let slot = NSBezierPath()
        let h: CGFloat = 102, w: CGFloat = 30
        let points: [(CGFloat, CGFloat)] = [(-w,h),(w,h),(w,w),(h,w),(h,-w),(w,-w),(w,-h),(-w,-h),(-w,-w),(-h,-w),(-h,w),(-w,w)]
        for (i, p) in points.enumerated() {
            let point = NSPoint(x: 512 + (p.0 - p.1), y: 610 + (p.0 + p.1) * 0.60)
            if i == 0 { slot.move(to: point) } else { slot.line(to: point) }
        }
        slot.close(); NSColor(calibratedRed: 0.075, green: 0.20, blue: 0.33, alpha: 1).setFill(); slot.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
