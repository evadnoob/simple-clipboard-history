import AppKit
@testable import SimpleClipboardKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}
func summary(_ kind: String, _ text: String = "", formatted: Bool = false) -> ClipSummary {
    ClipSummary(id: 1, kind: kind, preview: text, byteSize: 0, firstCopiedAt: .distantPast,
                lastCopiedAt: .distantPast, copyCount: 1, contentPreview: text, hasFormattedText: formatted)
}
for (clip, expected) in [
    (summary("text", "Notes"), ClipIconCategory.text),
    (summary("text", "https://example.org/guide"), .link),
    (summary("text", "  HTTPS://example.org/guide  \nnotes"), .link),
    (summary("text", "https://example.org/path with spaces"), .text),
    (summary("text", "Notes\nhttps://example.org"), .text),
    (summary("text", "https://"), .text),
    (summary("text", "file:///synthetic.txt"), .text),
    (summary("text", "mailto:hello@example.org"), .text),
    (summary("text", "https://example.org", formatted: true), .formatted),
    (summary("public.rtf", formatted: true), .formatted),
    (summary("file"), .file), (summary("2 files"), .files), (summary("files"), .files),
    (summary("0 files"), .unknown), (summary("image"), .image),
    (summary("unrecognized", "https://example.org"), .unknown),
    (summary("empty"), .unknown)
] {
    check(ClipIconClassifier.category(for: clip) == expected, "bounded summary maps to \(expected.rawValue)")
}
for text in ["let value = 1", "printf hello", "{\"ready\":true}", "hello@example.org", "#507A95", "password: synthetic"] {
    check(ClipIconClassifier.category(for: summary("text", text)) == .text, "no speculative classification: \(text)")
}

check(ClipIconStyle.editorialContentMarks.rawValue == "editorialContentMarks", "editorial stable persistence raw value")
check(ClipIconStyle.editorialContentMarks.title == "Editorial content marks", "editorial approved dropdown title")
check(ClipIconStyle.allCases.first == .current, "Current remains fresh-config default and first choice")
check(Array(ClipIconStyle.allCases.suffix(3)) == [.fineLine, .contentGlyphs, .twoTone],
      "new artwork is appended without changing existing selection indices")
for (style, title, rawValue) in [(ClipIconStyle.fineLine, "Fine line", "fineLine"),
                               (.contentGlyphs, "Content glyphs", "contentGlyphs"),
                               (.twoTone, "Two-tone", "twoTone")] {
    check(style.title == title && style.rawValue == rawValue && style.usesCustomArtwork,
          "new family has stable title, persistence value and custom artwork: \(title)")
}
for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
        check(ContentMarkIcon.accent(style: .twoTone, color: .white, selected: true) == .white,
              "selected two-tone artwork preserves foreground in \(appearance.rawValue)")
        check(ContentMarkIcon.accent(style: .fineLine, color: .labelColor, selected: false) == .labelColor,
              "fine line preserves monochrome foreground in \(appearance.rawValue)")
        let accent = ContentMarkIcon.accent(style: .twoTone, color: .labelColor, selected: false).usingColorSpace(.deviceRGB)!
        check(accent.blueComponent > accent.redComponent && accent.blueComponent > accent.greenComponent,
              "unselected two-tone artwork has blue accent in \(appearance.rawValue)")
    }
}

// Source gallery order, excluding the real-thumbnail slot which bypasses glyph rendering.
let expectedGallerySymbols: [(ClipIconStyle, [String])] = [
    (.openOutlines, ["text.quote", "textformat", "link", "photo", "doc", "doc.on.doc", "folder",
        "chevron.left.forwardslash.chevron.right", "terminal", "tablecells", "envelope",
        "square.lefthalf.filled", "key.horizontal", "questionmark.square", "square.on.circle"]),
    (.compactSilhouettes, ["quote.opening", "pencil.tip.crop.circle.fill", "link", "photo.fill", "doc.fill",
        "doc.on.doc.fill", "folder.fill", "curlybraces", "terminal.fill", "square.grid.3x3.fill", "envelope.fill",
        "circle.fill", "key.horizontal.fill", "questionmark.square.fill", "square.on.circle.fill"]),
    (.framedSymbols, ["text.quote", "italic", "link", "photo", "doc", "doc.on.doc", "folder", "curlybraces",
        "chevron.right", "tablecells", "at", "square.fill", "ellipsis", "minus", "square.on.circle"])
]
for (style, expected) in expectedGallerySymbols {
    check(ClipIconCategory.allCases.map { ClipTypeIcon.symbolName(category: $0, style: style) } == expected,
          "all artwork choices match gallery for \(style.rawValue)")
}

final class IconSheet: NSView {
    let style: ClipIconStyle
    init(style: ClipIconStyle, appearanceName: NSAppearance.Name = .aqua) {
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: CGFloat(ClipIconCategory.allCases.count * 50)))
        appearance = NSAppearance(named: appearanceName)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        InterfaceStyle.panelBackground.setFill(); bounds.fill()
        for (index, category) in ClipIconCategory.allCases.enumerated() {
            let y = CGFloat(index * 50)
            InterfaceStyle.draw(category.rawValue, in: NSRect(x: 8, y: y, width: 140, height: 50))
            for (column, size) in [CGFloat(22), 26, 30].enumerated() {
                for selected in [false, true] {
                    let x = CGFloat(150 + column * 100 + (selected ? 45 : 0))
                    let slot = NSRect(x: x, y: y, width: 42, height: 48)
                    if selected { InterfaceStyle.selectionFill(slot) }
                    ClipTypeIcon.draw(category: category, style: style,
                        in: NSRect(x: slot.midX - size / 2, y: slot.midY - size / 2, width: size, height: size),
                        color: PickerView.rowForeground(selected: selected),
                        colorSwatch: NSColor(calibratedRed: 0.31, green: 0.48, blue: 0.58, alpha: 1), selected: selected)
                }
            }
        }
    }
}
for (style, appearanceName) in ClipIconStyle.allCases.flatMap({ style in
    [NSAppearance.Name.aqua, .darkAqua].map { (style, $0) }
}) {
    let sheet = IconSheet(style: style, appearanceName: appearanceName)
    let bitmap = sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds)!
    sheet.cacheDisplay(in: sheet.bounds, to: bitmap)
    for (index, category) in ClipIconCategory.allCases.enumerated() {
        if !style.usesCustomArtwork {
            let symbol = ClipTypeIcon.symbolName(category: category, style: style)
            check(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                  "gallery symbol available: \(style.rawValue)/\(category.rawValue)/\(symbol)")
        }
        for (column, size) in [22, 26, 30].enumerated() {
            for selected in [false, true] {
                let x = 150 + column * 100 + (selected ? 45 : 0)
                let scale = CGFloat(bitmap.pixelsWide) / sheet.bounds.width
                var contrastingPixels = 0
                sheet.effectiveAppearance.performAsCurrentDrawingAppearance {
                    func luminance(_ color: NSColor) -> CGFloat {
                        let rgb = color.usingColorSpace(.deviceRGB)!
                        func linear(_ value: CGFloat) -> CGFloat {
                            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                        }
                        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
                    }
                    let background = bitmap.colorAt(x: Int(CGFloat(x + 1) * scale), y: Int(CGFloat(index * 50 + 1) * scale))!
                    let backgroundLuminance = luminance(background)
                    for px in Int(CGFloat(x) * scale)..<Int(CGFloat(x + 42) * scale) {
                        for py in Int(CGFloat(index * 50) * scale)..<Int(CGFloat(index * 50 + 48) * scale) {
                            let pixel = bitmap.colorAt(x: px, y: py)!.usingColorSpace(.deviceRGB)!
                            let pixelLuminance = luminance(pixel)
                            let contrast = (max(pixelLuminance, backgroundLuminance) + 0.05)
                                / (min(pixelLuminance, backgroundLuminance) + 0.05)
                            if contrast >= 3 { contrastingPixels += 1 }
                        }
                    }
                }
                check(contrastingPixels >= 3, "\(style.rawValue)/\(category.rawValue) paints foreground at \(size) selected=\(selected)")
            }
        }
    }
    if let directory = ProcessInfo.processInfo.environment["ICON_SNAPSHOT_DIRECTORY"] {
        try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try! bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("icons-\(style.rawValue)-\(appearanceName.rawValue).png"))
    }
}
// MARK: Open outlines optical balance, measured in the same fixed picker slots.
final class OpticalProbe: NSView {
    let category: ClipIconCategory
    let size: CGFloat
    let legacy: Bool
    let selected: Bool
    var slot: NSRect { NSRect(x: 8, y: 8, width: size, height: size) }
    init(category: ClipIconCategory, size: CGFloat, legacy: Bool, selected: Bool) {
        self.category = category; self.size = size; self.legacy = legacy; self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: size + 16, height: size + 16))
        appearance = NSAppearance(named: .aqua)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (selected ? NSColor.selectedContentBackgroundColor : .white).setFill(); bounds.fill()
        let color: NSColor = selected ? .white : .black
        if legacy {
            let image = NSImage(systemSymbolName: ClipTypeIcon.symbolName(category: category, style: .openOutlines),
                accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: size, weight: .regular))!
            let tinted = NSImage(size: image.size, flipped: false) { bounds in
                image.draw(in: bounds); color.setFill(); bounds.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: PickerView.aspectFitRect(for: image.size, in: slot), from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            ClipTypeIcon.draw(category: category, style: .openOutlines, in: slot, color: color)
        }
    }
    func pixels() -> (data: Data, ink: Int, outside: Int) {
        let bitmap = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / bounds.width
        var ink = 0, outside = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let isInk = selected ? min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.75
                    : max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.75
                if isInk {
                    ink += 1
                    if !slot.contains(NSPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)) { outside += 1 }
                }
            }
        }
        return (bitmap.representation(using: .png, properties: [:])!, ink, outside)
    }
}
for size: CGFloat in [22, 30] {
    for category in ClipIconCategory.allCases {
        for selected in [false, true] {
            let original = OpticalProbe(category: category, size: size, legacy: true, selected: selected).pixels()
            let refined = OpticalProbe(category: category, size: size, legacy: false, selected: selected).pixels()
            check(refined.outside == 0, "Open outlines stays inside fixed slot: \(category.rawValue)/\(size)/selected=\(selected)")
            if category == .text || category == .image {
                check(refined.ink > original.ink, "short Open outlines gains visible ink without a larger slot: \(category.rawValue)/\(size)/selected=\(selected)")
                let symbol = NSImage(systemSymbolName: ClipTypeIcon.symbolName(category: category, style: .openOutlines),
                    accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: size, weight: size <= 26 ? .medium : .regular))!
                let bitmap = NSBitmapImageRep(data: symbol.tiffRepresentation!)!
                let inset: CGFloat = category == .text ? 0.045 : 0.07
                let source = NSRect(x: CGFloat(bitmap.pixelsWide) * inset, y: CGFloat(bitmap.pixelsHigh) * inset,
                    width: CGFloat(bitmap.pixelsWide) * (1 - 2 * inset), height: CGFloat(bitmap.pixelsHigh) * (1 - 2 * inset))
                var clippedInk = false
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide where !source.contains(NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                        if bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.05 { clippedInk = true }
                    }
                }
                check(!clippedInk, "optical source crop removes transparent margins, not strokes: \(category.rawValue)/\(size)")
            } else {
                check(refined.data == original.data, "other Open outlines artwork unchanged: \(category.rawValue)/\(size)/selected=\(selected)")
            }
        }
    }
}

check(ClipTypeIcon.symbolName(category: .unknown, style: .openOutlines) == "questionmark.square", "unknown outline neutral fallback")
check(ClipTypeIcon.symbolName(category: .unknown, style: .framedSymbols) == "minus", "unknown specimen neutral fallback")
check(ClipTypeIcon.symbolName(category: .sensitive, style: .framedSymbols) == "ellipsis", "explicit sensitive specimen matches gallery")

// Frozen approved round-two/render.swift family-1 reference, excluding the real-thumbnail slot.
// Keep separate from production: pixel equality catches glyph, weight and coordinate drift.
final class EditorialReferenceProbe: NSView {
    let category: ClipIconCategory
    let size: CGFloat
    let selected: Bool
    let reference: Bool
    var systemColors = false
    var slot: NSRect { NSRect(x: 8, y: 8, width: size, height: size) }
    init(_ category: ClipIconCategory, _ size: CGFloat, _ selected: Bool, reference: Bool) {
        self.category = category; self.size = size; self.selected = selected; self.reference = reference
        super.init(frame: NSRect(x: 0, y: 0, width: size + 16, height: size + 16))
        appearance = NSAppearance(named: .aqua)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (selected ? NSColor.selectedContentBackgroundColor : systemColors ? InterfaceStyle.panelBackground : .white).setFill(); bounds.fill()
        let c: NSColor = systemColors ? PickerView.rowForeground(selected: selected) : selected ? .white : .black
        if !reference { ClipTypeIcon.draw(category: category, style: .editorialContentMarks, in: slot, color: c); return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Gallery picker(): icon(..., x, rowY + (rowHeight - 22) / 2, ...).
        // Larger destination slots add centering space, never a glyph/font scale.
        let transform = NSAffineTransform()
        if size >= 22 {
            transform.translateX(by: slot.midX - 11, yBy: slot.midY - 11)
        } else {
            transform.translateX(by: slot.minX, yBy: slot.minY)
            transform.scaleX(by: size / 22, yBy: size / 22)
        }
        transform.concat()
        let categories: [ClipIconCategory] = [.text, .formatted, .link, .unknown, .image, .file, .files,
            .code, .terminal, .structuredData, .sensitive, .unknown]
        let i = categories.firstIndex(of: category) ?? 11
        let x: CGFloat = 0, y: CGFloat = 0
        func box(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ c:NSColor) {
            c.setFill(); NSRect(x:x,y:y,width:w,height:h).fill()
        }
func stroke(_ points:[NSPoint],_ c:NSColor,_ width:CGFloat=1.2) { let p=NSBezierPath();p.lineWidth=width;p.move(to:points[0]);for v in points.dropFirst(){p.line(to:v)};c.setStroke();p.stroke() }
func mark(_ s:String,_ x:CGFloat,_ y:CGFloat,_ c:NSColor,_ size:CGFloat=14,_ mono:Bool=false) {
 let font = mono ? NSFont.monospacedSystemFont(ofSize:size,weight:.medium) : NSFont.systemFont(ofSize:size,weight:.regular)
 let attrs:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:c]
 let z=(s as NSString).size(withAttributes:attrs)
 (s as NSString).draw(at:NSPoint(x:x+(22-z.width)/2,y:y+(22-z.height)/2),withAttributes:attrs)
}
 switch i {
 case 0:
  for (dy,w) in [(5.0,18.0),(11.0,14.0),(17.0,18.0)] {box(x+2,y+dy,w,1.2,c)}
 case 1:
  mark("a",x-4,y-2,c,19);box(x+4,y+20,14,1,c);stroke([NSPoint(x:x+16,y:y+5),NSPoint(x:x+19,y:y+5),NSPoint(x:x+16,y:y+15),NSPoint(x:x+19,y:y+15)],c)
 case 2:
  mark("↗",x,y-2,c,21);box(x+3,y+20,16,1,c)
 case 4:
  mark("▧",x,y,c,22)
 case 5,6:
  // A page belongs only to file payloads, never as a generic type frame.
  if i == 6 {stroke([NSPoint(x:x+3,y:y+4),NSPoint(x:x+3,y:y+20),NSPoint(x:x+15,y:y+20)],c)}
  stroke([NSPoint(x:x+7,y:y+2),NSPoint(x:x+15,y:y+2),NSPoint(x:x+20,y:y+7),NSPoint(x:x+20,y:y+18),NSPoint(x:x+7,y:y+18),NSPoint(x:x+7,y:y+2)],c)
  stroke([NSPoint(x:x+15,y:y+2),NSPoint(x:x+15,y:y+7),NSPoint(x:x+20,y:y+7)],c)
 case 7: mark("</>",x,y,c,12,true)
 case 8: mark(">_",x,y,c,15,true)
 case 9:
  mark(":",x-7,y,c,16,true)
  for dy in [6.0,14.0] {box(x+10,y+dy,10,1.2,c)}
 case 10: mark("•••",x,y,c,14)
 default: mark("?",x,y,c,17)
 }
    }
    func bitmap() -> NSBitmapImageRep {
        let rep = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: rep); return rep
    }
}
for category in ClipIconCategory.allCases where ![.folder, .email, .color, .mixed].contains(category) {
    for size: CGFloat in [12, 18, 22, 26, 30] {
        for selected in [false, true] {
            let production = EditorialReferenceProbe(category, size, selected, reference: false)
            let actual = production.bitmap()
            let expected = EditorialReferenceProbe(category, size, selected, reference: true).bitmap()
            check(actual.representation(using: .png, properties: [:]) == expected.representation(using: .png, properties: [:]),
                  "approved editorial native geometry and destination centering matches: \(category)/\(size)/\(selected)")
            let scale = CGFloat(actual.pixelsWide) / production.bounds.width
            if size >= 22 {
                func nativePixels(_ bitmap: NSBitmapImageRep, origin: CGFloat) -> Data {
                    let rect = NSRect(x: origin * scale, y: origin * scale, width: 22 * scale, height: 22 * scale)
                    return NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: rect)!)
                        .representation(using: .png, properties: [:])!
                }
                let baseline = EditorialReferenceProbe(category, 22, selected, reference: false).bitmap()
                check(nativePixels(actual, origin: 8 + (size - 22) / 2) == nativePixels(baseline, origin: 8),
                      "editorial translated ink pixel geometry invariant at 22/26/30: \(category)/\(size)/\(selected)")
            }
            var outside = 0
            for y in 0..<actual.pixelsHigh {
                for x in 0..<actual.pixelsWide {
                    let pixel = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let ink = selected ? min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.75
                        : max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.75
                    if ink && !production.slot.contains(NSPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)) { outside += 1 }
                }
            }
            check(outside == 0, "editorial contained: \(category)/\(size)/\(selected)")
        }
    }
}

// Compare actual production row ink to the native gallery coordinate space at the SAME
// density and raster scale. Crop only for translation: production gutters must not change.
for (densityName, density) in [("compact", 4), ("comfortable", 10)] {
    for (appearanceName, appearance) in [("aqua", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        for (category, title) in [(ClipIconCategory.text, "Design review notes"), (.formatted, "Project notes"), (.link, "https://example.org/guide")] {
            for lines in [1, 2] {
                let text = title + (lines == 2 ? "\nKeep the menu bar simple." : "")
                let fixture = summary("text", text, formatted: category == .formatted)
                let model = PickerModel(search: { _, _ in [fixture, fixture] })
                let picker = PickerView(model: model)
                picker.appearance = NSAppearance(named: appearance)
                picker.settings.iconStyle = .editorialContentMarks
                picker.settings.pickerDensity = density
                picker.settings.pickerContentLines = 2
                picker.settings.showTimestamps = false
                model.reset()
                picker.setFrameSize(NSSize(width: 560, height: picker.desiredHeight(cap: 600, screenHeight: 800)))
                for selected in [true, false] {
                    picker.perform(selected ? .home : .down)
                    let row = picker.visibleRows[0].rect
                    let expectedHeight = CGFloat(lines * 16 + density * 2)
                    check(row.height == expectedHeight, "same-density gallery row height \(densityName)/\(lines) = \(expectedHeight)")
                    let bitmap = picker.bitmapImageRepForCachingDisplay(in: picker.bounds)!
                    picker.cacheDisplay(in: picker.bounds, to: bitmap)
                    let rasterScale = CGFloat(bitmap.pixelsWide) / picker.bounds.width
                    let destination = PickerView.typeSymbolRect(in: row, x: row.minX + 8, density: density)
                    let native = NSRect(x: destination.midX - 11, y: destination.midY - 11, width: 22, height: 22)
                    func crop(_ bitmap: NSBitmapImageRep, _ rect: NSRect) -> NSBitmapImageRep {
                        NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: NSRect(x: rect.minX * rasterScale,
                            y: rect.minY * rasterScale, width: rect.width * rasterScale, height: rect.height * rasterScale))!)
                    }
                    let actual = crop(bitmap, native)
                    let reference = EditorialReferenceProbe(category, 22, selected, reference: true)
                    reference.systemColors = true
                    reference.appearance = picker.appearance
                    let expected = crop(reference.bitmap(), NSRect(x: 8, y: 8, width: 22, height: 22))
                    check(actual.representation(using: .png, properties: [:]) == expected.representation(using: .png, properties: [:]),
                          "production row matches unscaled gallery ink: \(densityName)/\(category)/\(lines)/\(selected)/\(appearanceName)")
                    if category == .text {
                        // The first bar is exactly x=2..<20 in the native22 artwork.
                        let y = Int(5 * rasterScale)
                        let background = actual.colorAt(x: 0, y: y)!.usingColorSpace(.deviceRGB)!
                        let pixels = (0..<actual.pixelsWide).filter { x in
                            let pixel = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                            return abs(pixel.redComponent - background.redComponent) > 0.05
                                || abs(pixel.greenComponent - background.greenComponent) > 0.05
                                || abs(pixel.blueComponent - background.blueComponent) > 0.05
                        }
                        let inkWidth = CGFloat(pixels.count) / rasterScale
                        check(inkWidth == 18, "measured production text bar is18pt, not24.55: \(densityName)/\(selected)")
                        print("MEASURE \(densityName) row=\(row.height)pt bar=\(inkWidth)pt selected=\(selected) \(appearanceName)")
                    }
                    if let directory = ProcessInfo.processInfo.environment["ICON_SNAPSHOT_DIRECTORY"] {
                        let rowImage = NSImage(cgImage: crop(bitmap, row).cgImage!, size: row.size)
                        let galleryInk = NSImage(cgImage: expected.cgImage!, size: NSSize(width: 22, height: 22))
                        let size = NSSize(width: 1132, height: row.height + 24)
                        let sheet = NSImage(size: size, flipped: true) { _ in
                            InterfaceStyle.panelBackground.setFill(); NSRect(origin: .zero, size: size).fill()
                            InterfaceStyle.draw("Production · \(densityName) · native22", in: NSRect(x: 8, y: 0, width: 540, height: 24))
                            InterfaceStyle.draw("Approved gallery · \(densityName) · native22", in: NSRect(x: 580, y: 0, width: 540, height: 24))
                            rowImage.draw(in: NSRect(x: 0, y: 24, width: 560, height: row.height), from: .zero,
                                          operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                            let galleryRow = NSRect(x: 572, y: 24, width: 560, height: row.height)
                            if selected { InterfaceStyle.selectionFill(galleryRow) }
                            galleryInk.draw(in: NSRect(x: 580, y: 24 + (row.height - 22) / 2, width: 22, height: 22),
                                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                .foregroundColor: PickerView.rowForeground(selected: selected)]
                            (title as NSString).draw(at: NSPoint(x: 613, y: 24 + CGFloat(density) - 1), withAttributes: attrs)
                            if lines == 2 {
                                ("Keep the menu bar simple." as NSString).draw(at: NSPoint(x: 613, y: 24 + CGFloat(density) + 15),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: PickerView.rowForeground(selected: selected)])
                            }
                            return true
                        }
                        picker.effectiveAppearance.performAsCurrentDrawingAppearance {
                            let data = NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                            try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(
                                "editorial-production-vs-gallery-\(densityName)-\(appearanceName)-\(category.rawValue)-\(lines)-\(selected).png"))
                        }
                    }
                }
            }
        }
    }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
