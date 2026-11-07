import AppKit

// Resizing for the borderless picker, the same way noteapp does it (noteapp Sources/NoteApp/WindowCorners.swift,
// WindowFrame.swift and PaletteView.diagonalResizeCursor at 617d7221). The system resizes a borderless,
// resizable window from its edges with the left-right and up-down cursors, but gives the corners no cursor and no
// drag. A small square in each corner adds both.

enum WindowCorner { case topLeft, topRight, bottomLeft, bottomRight }

enum WindowFrame {
    /// The frame after dragging `corner` by (dx, dy), in screen coordinates (y grows upward). The opposite corner
    /// stays where it is. The size stays between `minimum` and `maximum`.
    static func dragged(_ frame: NSRect, corner: WindowCorner, dx: CGFloat, dy: CGFloat,
                        minimum: NSSize, maximum: NSSize) -> NSRect {
        var result = frame
        switch corner {
        case .bottomRight, .topRight: result.size.width = frame.width + dx
        case .bottomLeft, .topLeft: result.size.width = frame.width - dx
        }
        switch corner {
        case .topLeft, .topRight: result.size.height = frame.height + dy
        case .bottomLeft, .bottomRight: result.size.height = frame.height - dy
        }
        result.size.width = min(max(result.size.width, minimum.width), maximum.width)
        result.size.height = min(max(result.size.height, minimum.height), maximum.height)
        if corner == .bottomLeft || corner == .topLeft { result.origin.x = frame.maxX - result.size.width }
        if corner == .bottomLeft || corner == .bottomRight { result.origin.y = frame.maxY - result.size.height }
        return result
    }

    /// The largest window size any screen can show.
    static func largestSize(of screens: [NSRect]) -> NSSize {
        NSSize(width: screens.map { $0.width }.max() ?? CGFloat.greatestFiniteMagnitude,
               height: screens.map { $0.height }.max() ?? CGFloat.greatestFiniteMagnitude)
    }
}

enum ResizeCursors {
    /// The diagonal resize cursor for a corner: the Java runtime cursor if it exists, else a drawn one.
    /// `northWestSouthEast` is the arrow that runs from the top left to the bottom right.
    static func diagonal(northWestSouthEast: Bool) -> NSCursor {
        if northWestSouthEast {
            return javaResizeCursor("javaResizeNWCursor") ?? northWestSouthEastCursor
        }
        return javaResizeCursor("javaResizeNECursor") ?? northEastSouthWestCursor
    }

    private static let northWestSouthEastCursor = drawnDiagonal(northWestSouthEast: true)
    private static let northEastSouthWestCursor = drawnDiagonal(northWestSouthEast: false)

    /// The Java runtime (and so the JetBrains IDEs) takes its diagonal resize cursors from Apple's
    /// JavaRuntimeSupport framework, which adds javaResize{NW,NE,SW,SE}Cursor to NSCursor once it is loaded. These
    /// are not documented API, so the drawn cursor is the fallback.
    private static let javaRuntimeSupportLoaded: Bool =
        dlopen("/System/Library/Frameworks/JavaRuntimeSupport.framework/JavaRuntimeSupport", RTLD_LAZY) != nil

    private static func javaResizeCursor(_ name: String) -> NSCursor? {
        guard javaRuntimeSupportLoaded else { return nil }
        let selector = Selector(name)
        guard NSCursor.responds(to: selector) else { return nil }
        return NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor
    }

    private static func drawnDiagonal(northWestSouthEast: Bool) -> NSCursor {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            let a = NSPoint(x: 3, y: northWestSouthEast ? 17 : 3)
            let b = NSPoint(x: 17, y: northWestSouthEast ? 3 : 17)
            let length = hypot(b.x - a.x, b.y - a.y)
            let d = NSPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
            let p = NSPoint(x: -d.y, y: d.x)
            let headLength: CGFloat = 7, headHalfWidth: CGFloat = 5
            let shape = NSBezierPath()
            shape.move(to: a)
            shape.line(to: b)
            for (tip, direction) in [(a, d), (b, NSPoint(x: -d.x, y: -d.y))] {
                let base = NSPoint(x: tip.x + direction.x * headLength, y: tip.y + direction.y * headLength)
                shape.move(to: tip)
                shape.line(to: NSPoint(x: base.x + p.x * headHalfWidth, y: base.y + p.y * headHalfWidth))
                shape.line(to: NSPoint(x: base.x - p.x * headHalfWidth, y: base.y - p.y * headHalfWidth))
                shape.close()
            }
            shape.lineJoinStyle = .round
            shape.lineCapStyle = .round
            NSColor.white.setStroke()
            shape.lineWidth = 4
            shape.stroke()
            NSColor.black.setStroke()
            NSColor.black.setFill()
            shape.lineWidth = 1.5
            shape.stroke()
            shape.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }
}

/// A small square in a corner of the window that shows a diagonal resize cursor and resizes the window when
/// dragged. Place it in an unflipped container view.
final class WindowCornerView: NSView {
    static let size: CGFloat = 10

    let corner: WindowCorner
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero
    /// Brackets the drag so a horizontal-only resize preserves a content-driven height cap.
    var onResizeStarted: ((NSRect) -> Void)?
    var onResizeEnded: ((NSRect) -> Void)?

    init(corner: WindowCorner) {
        self.corner = corner
        super.init(frame: NSRect(x: 0, y: 0, width: WindowCornerView.size, height: WindowCornerView.size))
        autoresizingMask = {
            switch corner {
            case .bottomLeft: return [.maxXMargin, .maxYMargin]
            case .bottomRight: return [.minXMargin, .maxYMargin]
            case .topLeft: return [.maxXMargin, .minYMargin]
            case .topRight: return [.minXMargin, .minYMargin]
            }
        }()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Puts the square in its corner of the parent view.
    func place(in parent: NSView) {
        let s = WindowCornerView.size
        let x = (corner == .topLeft || corner == .bottomLeft) ? 0 : parent.bounds.width - s
        let y = (corner == .bottomLeft || corner == .bottomRight) ? 0 : parent.bounds.height - s
        frame = NSRect(x: x, y: y, width: s, height: s)
    }

    override func resetCursorRects() {
        // Top left and bottom right share one arrow; the other two corners share the other.
        let slopesDown = corner == .topLeft || corner == .bottomRight
        addCursorRect(bounds, cursor: ResizeCursors.diagonal(northWestSouthEast: slopesDown))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startMouse = window.convertPoint(toScreen: event.locationInWindow)
        onResizeStarted?(startFrame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let proposed = WindowFrame.dragged(startFrame, corner: corner, dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y,
                                           minimum: window.minSize,
                                           maximum: window.maxSize)
        window.setFrame(proposed, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if let window { onResizeEnded?(window.frame) }
    }
}
