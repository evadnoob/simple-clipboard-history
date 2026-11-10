import AppKit

/// One picker-wide family. Raw values are stable user-defaults values.
enum ClipIconStyle: String, CaseIterable {
    case current, openOutlines, compactSilhouettes, framedSymbols, editorialContentMarks

    var title: String {
        switch self {
        case .current: return "Current"
        case .editorialContentMarks: return "Editorial content marks"
        case .openOutlines: return "Open outlines"
        case .compactSilhouettes: return "Compact silhouettes"
        case .framedSymbols: return "Framed symbols"
        }
    }
}

/// Artwork vocabulary, independent of what can reliably be inferred from a stored summary.
/// Folder, code, terminal, structured data, email, color, sensitive and mixed are renderer-only:
/// summaries do not carry explicit metadata for these categories. Sensitive is never detected from text.
/// A real thumbnail is drawn by PickerView before this image-fallback renderer is consulted.
enum ClipIconCategory: String, CaseIterable {
    case text, formatted, link, image, file, files, folder, code, terminal, structuredData, email, color, sensitive, unknown, mixed
}

enum ClipIconClassifier {
    /// Preserve the original family's classification as well as its artwork for existing users.
    static func currentCategory(for clip: ClipSummary) -> ClipIconCategory {
        if clip.kind == "image" { return .image }
        if clip.kind == "files" { return .files }
        let firstLine = (clip.contentPreview.isEmpty ? clip.preview : clip.contentPreview).prefix(2048)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if let url = URL(string: firstLine.trimmingCharacters(in: .whitespaces)),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link }
        return .text
    }

    static func category(for clip: ClipSummary) -> ClipIconCategory {
        if clip.kind == "image" { return .image }
        if clip.kind == "file" { return .file }
        if clip.kind == "files" { return .files }
        let parts = clip.kind.split(separator: " ")
        if parts.count == 2, let count = Int(parts[0]), count > 1, parts[1] == "files" { return .files }
        guard clip.kind == "text" || clip.hasFormattedText else { return .unknown }
        if clip.hasFormattedText { return .formatted }
        let first = String((clip.contentPreview.isEmpty ? clip.preview : clip.contentPreview).prefix(2048))
            .components(separatedBy: .newlines)[0].trimmingCharacters(in: .whitespaces)
        if !first.contains(where: { $0.isWhitespace }), let url = URL(string: first),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty {
            return .link
        }
        return .text
    }
}

/// Picker artwork, including the approved custom Editorial marks and existing symbol families.
enum ClipTypeIcon {
    static func symbolName(category: ClipIconCategory, style: ClipIconStyle) -> String {
        switch style {
        case .editorialContentMarks:
            preconditionFailure("Editorial content marks use custom artwork, not SF Symbols")
        case .current:
            switch category {
            case .image: return "photo"
            case .files: return "doc.on.doc"
            case .link: return "link"
            default: return "doc.text"
            }
        case .openOutlines:
            switch category {
            case .text: return "text.quote"
            case .formatted: return "textformat"
            case .link: return "link"
            case .image: return "photo"
            case .file: return "doc"
            case .files: return "doc.on.doc"
            case .folder: return "folder"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .terminal: return "terminal"
            case .structuredData: return "tablecells"
            case .email: return "envelope"
            case .color: return "square.lefthalf.filled"
            case .sensitive: return "key.horizontal"
            case .unknown: return "questionmark.square"
            case .mixed: return "square.on.circle"
            }
        case .compactSilhouettes:
            switch category {
            case .text: return "quote.opening"
            case .formatted: return "pencil.tip.crop.circle.fill"
            case .link: return "link"
            case .image: return "photo.fill"
            case .file: return "doc.fill"
            case .files: return "doc.on.doc.fill"
            case .folder: return "folder.fill"
            case .code: return "curlybraces"
            case .terminal: return "terminal.fill"
            case .structuredData: return "square.grid.3x3.fill"
            case .email: return "envelope.fill"
            case .color: return "circle.fill"
            case .sensitive: return "key.horizontal.fill"
            case .unknown: return "questionmark.square.fill"
            case .mixed: return "square.on.circle.fill"
            }
        case .framedSymbols:
            switch category {
            case .text: return "text.quote"
            case .formatted: return "italic"
            case .link: return "link"
            case .image: return "photo"
            case .file: return "doc"
            case .files: return "doc.on.doc"
            case .folder: return "folder"
            case .code: return "curlybraces"
            case .terminal: return "chevron.right"
            case .structuredData: return "tablecells"
            case .email: return "at"
            case .color: return "square.fill"
            case .sensitive: return "ellipsis"
            case .unknown: return "minus"
            case .mixed: return "square.on.circle"
            }
        }
    }

    static func draw(category: ClipIconCategory, style: ClipIconStyle, in rect: NSRect, color: NSColor,
                     colorSwatch: NSColor? = nil) {
        if style == .editorialContentMarks {
            drawEditorial(category: category, in: rect, color: color, colorSwatch: colorSwatch)
            return
        }
        var symbolRect = rect
        if style == .framedSymbols {
            color.withAlphaComponent(0.7).setStroke()
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 1, yRadius: 1)
            frame.lineWidth = 1
            frame.stroke()
            symbolRect = rect.insetBy(dx: rect.width * 0.23, dy: rect.height * 0.23)
        } else if style == .compactSilhouettes {
            symbolRect = rect.insetBy(dx: 2, dy: 2)
        }
        let name = symbolName(category: category, style: style)
        let shortOutline = style == .openOutlines && (category == .text || category == .image)
        // Short, wide marks need more ink at compact size, not a larger gutter or taller proportions.
        let weight: NSFont.Weight = style == .compactSilhouettes ? .semibold
            : shortOutline && rect.height <= 26 ? .medium : .regular
        let base = NSImage(systemSymbolName: name, accessibilityDescription: category.rawValue)
            ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: "Unknown content")
        if let base, let image = base.withSymbolConfiguration(.init(pointSize: symbolRect.height, weight: weight)) {
            let tinted = NSImage(size: image.size, flipped: false) { bounds in
                image.draw(in: bounds)
                color.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
            var source = NSRect(origin: .zero, size: image.size)
            if shortOutline {
                // Trim only transparent SF Symbol margins; preserve each glyph's native aspect ratio.
                let inset: CGFloat = category == .text ? 0.045 : 0.07
                source = source.insetBy(dx: source.width * inset, dy: source.height * inset)
            }
            tinted.draw(in: PickerView.aspectFitRect(for: source.size, in: symbolRect), from: source,
                        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        // Only explicit color metadata can provide a swatch; never infer a color from arbitrary clipboard text.
        if category == .color, let colorSwatch {
            colorSwatch.setFill()
            rect.insetBy(dx: rect.width * 0.37, dy: rect.height * 0.37).fill()
        }
    }
}

// Geometry and native glyphs transcribed from round-two/render.swift, family 1.
// Center the gallery's native 22-point artwork; only smaller destinations shrink it.
private extension ClipTypeIcon {
    static func drawEditorial(category: ClipIconCategory, in rect: NSRect, color: NSColor,
                              colorSwatch: NSColor?) {
        // Supplementary renderer-only entries absent from the approved sheet retain their
        // existing unframed outline concepts. They are not newly approved gallery artwork.
        if [.folder, .email, .color, .mixed].contains(category) {
            draw(category: category, style: .openOutlines, in: rect, color: color, colorSwatch: colorSwatch)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = min(1, min(rect.width, rect.height) / 22)
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - 11 * scale, yBy: rect.midY - 11 * scale)
        transform.scaleX(by: scale, yBy: scale)
        transform.concat()
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            color.setFill(); NSRect(x: x, y: y, width: w, height: h).fill()
        }
        func stroke(_ points: [NSPoint]) {
            let path = NSBezierPath(); path.lineWidth = 1.2
            path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            color.setStroke(); path.stroke()
        }
        func mark(_ glyph: String, _ x: CGFloat = 0, _ y: CGFloat = 0,
                  _ size: CGFloat = 14, _ mono: Bool = false) {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                : NSFont.systemFont(ofSize: size, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let extent = (glyph as NSString).size(withAttributes: attributes)
            (glyph as NSString).draw(at: NSPoint(x: x + (22 - extent.width) / 2,
                y: y + (22 - extent.height) / 2), withAttributes: attributes)
        }
        switch category {
        case .text:
            for (y, width): (CGFloat, CGFloat) in [(5, 18), (11, 14), (17, 18)] { box(2, y, width, 1.2) }
        case .formatted:
            mark("a", -4, -2, 19); box(4, 20, 14, 1)
            stroke([NSPoint(x: 16, y: 5), NSPoint(x: 19, y: 5), NSPoint(x: 16, y: 15), NSPoint(x: 19, y: 15)])
        case .link:
            mark("↗", 0, -2, 21); box(3, 20, 16, 1)
        case .image: mark("▧", 0, 0, 22)
        case .file, .files:
            if category == .files { stroke([NSPoint(x: 3, y: 4), NSPoint(x: 3, y: 20), NSPoint(x: 15, y: 20)]) }
            stroke([NSPoint(x: 7, y: 2), NSPoint(x: 15, y: 2), NSPoint(x: 20, y: 7),
                    NSPoint(x: 20, y: 18), NSPoint(x: 7, y: 18), NSPoint(x: 7, y: 2)])
            stroke([NSPoint(x: 15, y: 2), NSPoint(x: 15, y: 7), NSPoint(x: 20, y: 7)])
        case .code: mark("</>", 0, 0, 12, true)
        case .terminal: mark(">_", 0, 0, 15, true)
        case .structuredData:
            mark(":", -7, 0, 16, true)
            for y: CGFloat in [6, 14] { box(10, y, 10, 1.2) }
        case .sensitive: mark("•••")
        case .unknown: mark("?", 0, 0, 17)
        case .folder, .email, .color, .mixed: break // Handled above without transforming.
        }
    }
}
