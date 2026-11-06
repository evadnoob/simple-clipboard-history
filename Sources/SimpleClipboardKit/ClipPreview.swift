import AppKit

/// What the picker's preview shows for a clip.
enum ClipPreview {
    case text(String)
    case image(NSImage)
    case files([String])
    case other(String)

    /// Characters of text shown in the preview.
    static let textLimit = 20_000

    static func make(from items: [[Representation]]) -> ClipPreview {
        let all = items.flatMap { $0 }
        let filePaths = items.compactMap { item -> String? in
            guard let representation = item.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }),
                  let text = String(data: representation.data, encoding: .utf8), let url = URL(string: text) else { return nil }
            return url.path
        }
        if !filePaths.isEmpty { return .files(filePaths) }
        let imageTypes = [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue,
                          "public.jpeg", "public.heic"]
        if let text = all.first(where: { $0.type == NSPasteboard.PasteboardType.string.rawValue })
            .flatMap({ String(data: $0.data, encoding: .utf8) }) {
            return .text(String(text.prefix(textLimit)))
        }
        for type in imageTypes {
            if let representation = all.first(where: { $0.type == type }), let image = NSImage(data: representation.data) {
                return .image(image)
            }
        }
        return .other(all.map(\.type).joined(separator: "\n"))
    }
}
