import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

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
        // A shallow three-quarter view exposes the front and side of the switch.
        func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> NSPoint {
            NSPoint(x: 512 + (x - y) * 0.82, y: 350 + (x + y) * 0.38 + z)
        }
        func face(_ points: [(CGFloat, CGFloat, CGFloat)], _ color: NSColor) {
            let path = NSBezierPath()
            for (i, p) in points.enumerated() {
                let point = project(p.0, p.1, p.2)
                if i == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            path.close(); color.setFill(); path.fill()
            path.lineWidth = 2; path.lineJoinStyle = .round; color.setStroke(); path.stroke()
        }
        func box(_ half: CGFloat, bottom: CGFloat, top: CGFloat, topColor: NSColor, left: NSColor, right: NSColor) {
            face([(-half,-half,bottom),(-half,half,bottom),(-half,half,top),(-half,-half,top)], left)
            face([(-half,-half,bottom),(half,-half,bottom),(half,-half,top),(-half,-half,top)], right)
            face([(-half,-half,top),(half,-half,top),(half,half,top),(-half,half,top)], topColor)
        }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -18); shadow.set()
        face([(-230,-230,0),(230,-230,0),(230,230,0),(-230,230,0)], NSColor.black.withAlphaComponent(0.35))
        NSGraphicsContext.restoreGraphicsState()
        box(218, bottom: 8, top: 76,
            topColor: NSColor(white: 0.28, alpha: 1), left: NSColor(white: 0.16, alpha: 1), right: NSColor(white: 0.22, alpha: 1))
        box(232, bottom: 76, top: 208,
            topColor: NSColor(white: 0.88, alpha: 1), left: NSColor(white: 0.59, alpha: 1), right: NSColor(white: 0.73, alpha: 1))
        // Retaining clips on the two visible walls.
        face([(-233,-115,96),(-233,-40,96),(-233,-40,194),(-233,-115,194)], NSColor(white: 0.76, alpha: 1))
        face([(-115,-233,96),(-40,-233,96),(-40,-233,194),(-115,-233,194)], NSColor(white: 0.89, alpha: 1))
        box(164, bottom: 208, top: 224,
            topColor: NSColor(white: 0.22, alpha: 1), left: NSColor(white: 0.40, alpha: 1), right: NSColor(white: 0.50, alpha: 1))
        box(104, bottom: 224, top: 370,
            topColor: NSColor(calibratedRed: 0.36, green: 0.73, blue: 1, alpha: 1),
            left: NSColor(calibratedRed: 0.10, green: 0.39, blue: 0.73, alpha: 1),
            right: NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.91, alpha: 1))
        let h: CGFloat = 74, w: CGFloat = 24
        let socket: [(CGFloat, CGFloat)] = [(-w,h),(w,h),(w,w),(h,w),(h,-w),(w,-w),(w,-h),(-w,-h),(-w,-w),(-h,-w),(-h,w),(-w,w)]
        face(socket.map { ($0.0, $0.1, 371) }, NSColor(calibratedRed: 0.05, green: 0.23, blue: 0.43, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
