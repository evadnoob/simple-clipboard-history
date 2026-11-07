import AppKit

/// Shared typography and geometry for the picker and control panel.
enum InterfaceStyle {
    static let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let smallFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let controlFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static var panelBackground: NSColor { .windowBackgroundColor }
    static var sectionBackground: NSColor { .quaternaryLabelColor }
    static var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
    static var rowHeight: CGFloat { lineHeight + 4 }
    static let gap: CGFloat = 8
    static let pickerSize = NSSize(width: 640, height: 420)

    static func width(of text: String, font: NSFont = InterfaceStyle.font) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Draws one line of text, centered vertically in the rect and cut with an ellipsis at its end.
    static func draw(_ text: String, in rect: NSRect, font: NSFont = InterfaceStyle.font, color: NSColor = .labelColor,
                     alignment: NSTextAlignment = .left) {
        guard rect.width > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let height = ceil(font.ascender - font.descender)
        let target = NSRect(x: rect.minX, y: rect.minY + floor((rect.height - height) / 2), width: rect.width, height: height)
        (text as NSString).draw(with: target, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    /// Like `draw`, with the first case-insensitive match of `highlight` in semibold, so typed text shows where it
    /// matched.
    static func draw(_ text: String, highlighting highlight: String, in rect: NSRect, color: NSColor = .labelColor) {
        guard rect.width > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color,
                                                                              .paragraphStyle: style])
        let needle = highlight.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            let range = (text as NSString).range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
            if range.location != NSNotFound {
                attributed.addAttributes([.font: NSFont.systemFont(ofSize: font.pointSize, weight: .bold),
                                          .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            }
        }
        let height = ceil(font.ascender - font.descender)
        let target = NSRect(x: rect.minX, y: rect.minY + floor((rect.height - height) / 2), width: rect.width, height: height)
        attributed.draw(with: target, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor = .labelColor) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    static func selectionFill(_ rect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        rect.fill()
    }

    static func strokeFocus(_ rect: NSRect) {
        NSColor.secondaryLabelColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 2
        path.stroke()
    }

    static func strokeBorder(_ rect: NSRect, color: NSColor = .separatorColor) {
        color.setStroke()
        NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

/// The picker's frame inside its box: the list at the top, a status bar at the bottom. No title row and no
/// input field; typing narrows the list and the bar shows the count and the typed text.
struct PickerChrome {
    let box: NSRect
    var previewOpen = false

    private var gap: CGFloat { InterfaceStyle.gap }
    var barHeight: CGFloat { InterfaceStyle.rowHeight + gap }
    var barSeparator: NSRect { NSRect(x: box.minX, y: box.maxY - barHeight, width: box.width, height: 1) }
    var barRect: NSRect {
        NSRect(x: box.minX + gap, y: box.maxY - barHeight + gap / 2, width: box.width - gap * 2, height: InterfaceStyle.rowHeight)
    }

    /// Everything above the bar separator, inset by half the gap at the top and bottom.
    private var bodyRect: NSRect {
        let top = box.minY + gap / 2
        return NSRect(x: box.minX, y: top, width: box.width, height: max(1, barSeparator.minY - gap / 2 - top))
    }

    /// The rows. With the preview open they take the top third.
    var listRect: NSRect {
        guard previewOpen else { return bodyRect }
        let rows = max(1, floor(bodyRect.height / 3 / InterfaceStyle.rowHeight))
        return NSRect(x: bodyRect.minX, y: bodyRect.minY, width: bodyRect.width, height: rows * InterfaceStyle.rowHeight)
    }

    var previewSeparator: NSRect { NSRect(x: box.minX, y: listRect.maxY + gap / 2, width: box.width, height: 1) }

    var previewRect: NSRect {
        let top = previewSeparator.maxY + gap
        return NSRect(x: box.minX + gap, y: top, width: box.width - gap * 2, height: max(1, bodyRect.maxY - top))
    }

    func draw() {
        InterfaceStyle.panelBackground.setFill()
        box.fill()
        InterfaceStyle.strokeBorder(box, color: .tertiaryLabelColor)
        NSColor.separatorColor.setFill()
        barSeparator.fill()
        if previewOpen { previewSeparator.fill() }
    }
}
