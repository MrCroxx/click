import AppKit

/// A small, monochrome version of the floating switch mark.
enum SwitchSymbol {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let cap = NSBezierPath()
            cap.move(to: NSPoint(x: 9, y: 16))
            cap.line(to: NSPoint(x: 16, y: 11.5))
            cap.line(to: NSPoint(x: 9, y: 7))
            cap.line(to: NSPoint(x: 2, y: 11.5)); cap.close()
            cap.lineWidth = 1.5; cap.lineJoinStyle = .round; cap.stroke()
            let contact = NSBezierPath()
            contact.move(to: NSPoint(x: 2, y: 6.5))
            contact.line(to: NSPoint(x: 9, y: 2))
            contact.line(to: NSPoint(x: 16, y: 6.5))
            contact.lineWidth = 1.5; contact.lineCapStyle = .round; contact.lineJoinStyle = .round; contact.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
