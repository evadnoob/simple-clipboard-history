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

    /// "Nov 6" in the user's locale.
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
