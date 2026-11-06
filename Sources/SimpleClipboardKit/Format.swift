import Foundation

enum Format {
    /// Short age for the menu bar title: "now", "45s", "12m", "3h", "5d".
    static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    /// Bytes in binary units with one decimal above 1 KB: "512 B", "1.5 KB", "20.0 MB".
    static func bytes(_ count: Int) -> String {
        if count < 1024 { return "\(count) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(count) / 1024
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }

    /// Menu bar title: clip count, two spaces, age of the last copy. "0" when the history is empty.
    static func statusTitle(clipCount: Int, lastCopiedAt: Date?, now: Date, paused: Bool) -> String {
        var title = "\(clipCount)"
        if let lastCopiedAt { title += "  " + age(from: lastCopiedAt, to: now) }
        if paused { title += "  paused" }
        return title
    }

    /// A menu row: the preview cut to `width` characters with an ellipsis.
    static func menuPreview(_ text: String, width: Int = 50) -> String {
        text.count <= width ? text : String(text.prefix(width - 1)) + "\u{2026}"
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
