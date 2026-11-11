import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SimpleClipboardHistory-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { if ProcessInfo.processInfo.environment["KEEP_ICONSET"] == nil { try? FileManager.default.removeItem(at: iconset) } }
let sizes = [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]
for (name, pixels) in sizes {
    let side = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Could not allocate \(name)") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side), xRadius: side * 0.20, yRadius: side * 0.20).fill()
    let path = NSBezierPath()
    path.lineWidth = side * 0.045
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.20, alpha: 1).setStroke()
    path.move(to: NSPoint(x: side*0.33, y: side*0.72)); path.line(to: NSPoint(x: side*0.28, y: side*0.72))
    path.line(to: NSPoint(x: side*0.28, y: side*0.22)); path.line(to: NSPoint(x: side*0.72, y: side*0.22))
    path.line(to: NSPoint(x: side*0.72, y: side*0.72)); path.line(to: NSPoint(x: side*0.67, y: side*0.72)); path.stroke()
    NSBezierPath(roundedRect: NSRect(x: side*0.40, y: side*0.68, width: side*0.20, height: side*0.12), xRadius: side*0.035, yRadius: side*0.035).stroke()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Could not render \(name)") }
    try png.write(to: iconset.appendingPathComponent(name))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = ["iconutil", "--convert", "icns", "--output", output, iconset.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
