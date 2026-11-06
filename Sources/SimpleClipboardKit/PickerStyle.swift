import AppKit

/// The picker's look, taken from noteapp's /import popup (ImportWizardStyle and ImportWizardChrome in
/// noteapp Sources/NoteApp/ImportWizardControls.swift at 617d7221): the monospaced interface font, square
/// corners, a hairline border, a title row with a separator, neutral selection fill and a bottom bar.
enum PickerStyle {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let smallFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
    static var rowHeight: CGFloat { lineHeight + 4 }
    static let gap: CGFloat = 8
    static let boxSize = NSSize(width: 640, height: 420)

    static func width(of text: String, font: NSFont = PickerStyle.font) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Draws one line of text, centered vertically in the rect and cut with an ellipsis at its end.
    static func draw(_ text: String, in rect: NSRect, font: NSFont = PickerStyle.font, color: NSColor = .labelColor,
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

    static func selectionFill(_ rect: NSRect) {
        NSColor.tertiaryLabelColor.withAlphaComponent(0.20).setFill()
        rect.fill()
    }

    static func strokeBorder(_ rect: NSRect, color: NSColor = .separatorColor) {
        color.setStroke()
        NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

/// The picker's frame inside its box: title row at the top, prompt bar at the bottom, content between.
struct PickerChrome {
    let box: NSRect
    var previewOpen = false

    private var gap: CGFloat { PickerStyle.gap }
    var titleHeight: CGFloat { PickerStyle.rowHeight + gap }
    var barHeight: CGFloat { PickerStyle.rowHeight + gap * 2 }
    var titleRect: NSRect { NSRect(x: box.minX + gap, y: box.minY, width: box.width - gap * 2, height: titleHeight) }
    var titleSeparator: NSRect { NSRect(x: box.minX, y: box.minY + titleHeight, width: box.width, height: 1) }
    var barSeparator: NSRect { NSRect(x: box.minX, y: box.maxY - barHeight, width: box.width, height: 1) }
    var barRect: NSRect {
        NSRect(x: box.minX + gap, y: box.maxY - barHeight + gap, width: box.width - gap * 2, height: PickerStyle.rowHeight)
    }

    /// Everything between the title separator and the bar separator, inset by the gap at the top and bottom.
    private var bodyRect: NSRect {
        let top = titleSeparator.maxY + gap
        return NSRect(x: box.minX, y: top, width: box.width, height: max(1, barSeparator.minY - gap - top))
    }

    /// The clip rows. With the preview open they take the top third.
    var listRect: NSRect {
        guard previewOpen else { return bodyRect }
        let rows = max(1, floor(bodyRect.height / 3 / PickerStyle.rowHeight))
        return NSRect(x: bodyRect.minX, y: bodyRect.minY, width: bodyRect.width, height: rows * PickerStyle.rowHeight)
    }

    var previewSeparator: NSRect { NSRect(x: box.minX, y: listRect.maxY + gap, width: box.width, height: 1) }

    var previewRect: NSRect {
        let top = previewSeparator.maxY + gap
        return NSRect(x: box.minX + gap, y: top, width: box.width - gap * 2, height: max(1, bodyRect.maxY - top))
    }

    func draw(title: String, detail: String) {
        NSColor.textBackgroundColor.setFill()
        box.fill()
        PickerStyle.strokeBorder(box, color: .tertiaryLabelColor)
        let titleWidth = min(PickerStyle.width(of: title), titleRect.width / 2)
        let left = NSRect(x: titleRect.minX, y: titleRect.minY, width: titleWidth, height: titleRect.height)
        let right = NSRect(x: left.maxX + gap, y: titleRect.minY,
                           width: max(0, titleRect.maxX - left.maxX - gap), height: titleRect.height)
        PickerStyle.draw(title, in: left)
        PickerStyle.draw(detail, in: right, color: .secondaryLabelColor, alignment: .right)
        NSColor.separatorColor.setFill()
        titleSeparator.fill()
        barSeparator.fill()
        if previewOpen { previewSeparator.fill() }
    }
}
