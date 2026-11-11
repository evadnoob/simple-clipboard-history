import AppKit

/// Shared empty clipboard outline for the panel and menu bar.
enum ClipboardIcon {
    static let aspectRatio: CGFloat = 24.0 / 26.0

    static func strokeWidth(for rect: NSRect) -> CGFloat {
        max(1.2, rect.width * 0.08)
    }

    static func image(size: NSSize, accessibilityDescription: String?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            let path = outline(in: rect)
            context.saveGraphicsState()
            context.cgContext.setLineWidth(strokeWidth(for: rect))
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            NSColor.labelColor.setStroke()
            path.stroke()
            context.restoreGraphicsState()
            return true
        }
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    static func outline(in rect: NSRect) -> NSBezierPath {
        let sx = rect.width / 24
        let sy = rect.height / 26
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * sx, y: rect.minY + (26 - y) * sy)
        }
        let path = NSBezierPath()
        path.lineWidth = strokeWidth(for: rect)
        path.move(to: p(8, 4.5)); path.line(to: p(6, 4.5))
        path.curve(to: p(3.5, 7), controlPoint1: p(3.5, 4.5), controlPoint2: p(3.5, 5.5))
        path.line(to: p(3.5, 22)); path.curve(to: p(6, 24.5), controlPoint1: p(3.5, 23.5), controlPoint2: p(4.5, 24.5))
        path.line(to: p(18, 24.5)); path.curve(to: p(20.5, 22), controlPoint1: p(19.5, 24.5), controlPoint2: p(20.5, 23.5))
        path.line(to: p(20.5, 7)); path.curve(to: p(18, 4.5), controlPoint1: p(20.5, 5.5), controlPoint2: p(19.5, 4.5))
        path.line(to: p(16, 4.5))
        // The tab is a separate rounded rectangular stroke, matching the native empty clipboard glyph.
        let tab = NSBezierPath(roundedRect: NSRect(x: rect.minX + 8*sx, y: rect.minY + 19.5*sy, width: 8*sx, height: 4*sy), xRadius: 1.5*sx, yRadius: 1.5*sy)
        path.append(tab)
        return path
    }
}
