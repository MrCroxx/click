import AppKit

/// A monochrome switch housing and cross-shaped stem for small UI surfaces.
enum SwitchSymbol {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let housing = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 13, height: 13), xRadius: 3, yRadius: 3)
            housing.lineWidth = 1.5; housing.stroke()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 6, y: 9)); stem.line(to: NSPoint(x: 12, y: 9))
            stem.move(to: NSPoint(x: 9, y: 6)); stem.line(to: NSPoint(x: 9, y: 12))
            stem.lineWidth = 2; stem.lineCapStyle = .square; stem.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
