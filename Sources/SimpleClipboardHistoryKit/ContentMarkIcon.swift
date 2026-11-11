import AppKit

/// Custom artwork from the side-by-side comparison. Unclassified content keeps a neutral fallback.
enum ContentMarkIcon {
    static func draw(category: ClipIconCategory, style: ClipIconStyle, in rect: NSRect,
                     color: NSColor, colorSwatch: NSColor?, selected: Bool) {
        guard [.text, .formatted, .link, .image, .file, .files].contains(category) else {
            ClipTypeIcon.draw(category: category, style: .openOutlines, in: rect,
                              color: color, colorSwatch: colorSwatch)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = min(rect.width, rect.height) / 24
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - 12 * scale, yBy: rect.midY - 12 * scale)
        transform.scale(by: scale)
        transform.concat()
        let ink = accent(style: style, color: color, selected: selected)
        func stroke(_ points: [(CGFloat, CGFloat)], color strokeColor: NSColor? = nil) {
            let path = NSBezierPath(); path.lineWidth = 1.2
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: NSPoint(x: points[0].0, y: points[0].1))
            for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
            (strokeColor ?? color).setStroke(); path.stroke()
        }
        func glyph(_ value: String, size: CGFloat = 20) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: ink
            ]
            let extent = (value as NSString).size(withAttributes: attributes)
            (value as NSString).draw(at: NSPoint(x: (24 - extent.width) / 2, y: (24 - extent.height) / 2),
                                    withAttributes: attributes)
        }
        if style == .contentGlyphs {
            switch category {
            case .text: glyph("“", size: 28)
            case .formatted: glyph("a", size: 22); stroke([(6, 22), (18, 22)])
            case .link: glyph("↗", size: 24)
            case .image: glyph("▧", size: 23)
            case .file: glyph("1", size: 18); stroke([(5, 22), (19, 22)])
            case .files: glyph("+", size: 24); stroke([(5, 22), (19, 22)])
            default: break
            }
            return
        }
        switch category {
        case .text:
            stroke([(4, 6), (20, 6)], color: ink)
            stroke([(4, 12), (16, 12)])
            stroke([(4, 18), (19, 18)])
        case .formatted:
            stroke([(5, 6), (19, 6)], color: ink)
            stroke([(12, 6), (12, 19)], color: ink)
            stroke([(7, 20), (17, 20)])
        case .link:
            for (x, y): (CGFloat, CGFloat) in [(3, 11), (11, 3)] {
                let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 10, height: 10), xRadius: 4, yRadius: 4)
                path.lineWidth = 1.2
                (x == 11 ? ink : color).setStroke(); path.stroke()
            }
            stroke([(9, 15), (15, 9)], color: ink)
        case .image:
            stroke([(3, 8), (3, 3), (21, 3), (21, 21), (3, 21), (3, 16)])
            stroke([(4, 18), (10, 11), (14, 15), (18, 10), (21, 14)], color: ink)
            ink.setFill(); NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 3, height: 3)).fill()
        case .file, .files:
            if category == .files { stroke([(3, 7), (3, 22), (16, 22)], color: ink) }
            stroke([(6, 20), (6, 2), (15, 2), (21, 8), (21, 20), (6, 20)])
            stroke([(15, 2), (15, 8), (21, 8)], color: ink)
            if style == .twoTone {
                stroke([(10, 13), (17, 13)], color: ink)
                stroke([(10, 16), (15, 16)], color: ink)
            }
        default: break
        }
    }

    /// Selection uses the supplied foreground so the accent does not disappear into the blue row.
    static func accent(style: ClipIconStyle, color: NSColor, selected: Bool) -> NSColor {
        guard style == .twoTone, !selected else { return color }
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedRed: dark ? 0.42 : 0.15, green: dark ? 0.69 : 0.41,
                       blue: dark ? 1 : 0.76, alpha: 1)
    }
}
