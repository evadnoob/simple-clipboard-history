import Foundation

/// How choosing a clip gives it back.
enum RecallMode: String, CaseIterable {
    /// Put the clip on the clipboard. The user presses Cmd-V.
    case clipboard
    /// Put the clip on the clipboard, then send Cmd-V to the frontmost app. Needs Accessibility.
    case paste
}

/// Values from the hand-written settings file. Missing or invalid values use the defaults.
struct Settings: Equatable {
    var recallMode: RecallMode = .clipboard
    /// Most clips kept. The least recently copied clips are deleted first.
    var historyLimit = 1000
    /// Clips larger than this are not recorded.
    var maximumClipBytes = 20 * 1024 * 1024
    /// Bundle identifiers of apps whose copies are not recorded.
    var ignoredApps: [String] = []

    static let defaults = Settings()

    /// Default ~/.config/simple-clipboard/simple-clipboard.kdl. SIMPLE_CLIPBOARD_SETTINGS overrides it.
    static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["SIMPLE_CLIPBOARD_SETTINGS"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/simple-clipboard/simple-clipboard.kdl")
    }

    /// Parses settings text. Returns the settings plus one problem string per value that was ignored.
    static func parse(_ text: String) -> (settings: Settings, problems: [String]) {
        var settings = Settings()
        var problems: [String] = []
        let nodes: [KDLNode]
        do {
            nodes = try KDL.parse(text, hashComments: true)
        } catch {
            return (settings, ["settings file: \(error)"])
        }
        for node in nodes {
            switch node.name {
            case "recall":
                for child in node.children {
                    switch child.name {
                    case "mode":
                        if case .string(let text)? = child.arguments.first, let mode = RecallMode(rawValue: text) {
                            settings.recallMode = mode
                        } else {
                            let allowed = RecallMode.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")
                            problems.append("line \(child.line): recall mode must be \(allowed)")
                        }
                    default:
                        problems.append("line \(child.line): unknown setting recall \(child.name)")
                    }
                }
            case "history":
                for child in node.children {
                    switch child.name {
                    case "limit":
                        if let number = positiveInteger(child) { settings.historyLimit = number } else {
                            problems.append("line \(child.line): history limit must be a whole number above 0")
                        }
                    case "maximum-clip-megabytes":
                        if let number = positiveInteger(child) { settings.maximumClipBytes = number * 1024 * 1024 } else {
                            problems.append("line \(child.line): history maximum-clip-megabytes must be a whole number above 0")
                        }
                    default:
                        problems.append("line \(child.line): unknown setting history \(child.name)")
                    }
                }
            case "capture":
                for child in node.children {
                    switch child.name {
                    case "ignore-app":
                        if case .string(let identifier)? = child.arguments.first, !identifier.isEmpty {
                            settings.ignoredApps.append(identifier)
                        } else {
                            problems.append("line \(child.line): capture ignore-app needs a bundle identifier string")
                        }
                    default:
                        problems.append("line \(child.line): unknown setting capture \(child.name)")
                    }
                }
            default:
                problems.append("line \(node.line): unknown setting \(node.name)")
            }
        }
        return (settings, problems)
    }

    private static func positiveInteger(_ node: KDLNode) -> Int? {
        guard case .number(let value)? = node.arguments.first, value >= 1, value == value.rounded(),
              value < Double(Int32.max) else { return nil }
        return Int(value)
    }

    /// Written when the user opens the settings file and it does not exist yet.
    static let template = """
    # Simple Clipboard settings. Changes apply when the file is saved.

    recall {
        # "clipboard": choosing a clip puts it on the clipboard; you press Cmd-V.
        # "paste": also sends Cmd-V to the frontmost app. Needs Accessibility permission.
        mode "clipboard"
    }

    history {
        # Most clips kept. The least recently copied clips are deleted first.
        limit 1000
        # Clips larger than this are not recorded.
        maximum-clip-megabytes 20
    }

    capture {
        # Copies made in these apps are not recorded. One line per app bundle identifier.
        # ignore-app "com.1password.1password"
    }

    """
}

/// Reloads the settings file when its modification date changes. Call `reloadIfChanged` from a timer.
final class SettingsFile {
    let url: URL
    private(set) var settings = Settings()
    private(set) var problems: [String] = []
    private var loadedModificationDate: Date?
    private var loadedOnce = false

    init(url: URL) {
        self.url = url
    }

    /// Returns true when the settings were (re)loaded.
    @discardableResult
    func reloadIfChanged() -> Bool {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if loadedOnce && modificationDate == loadedModificationDate { return false }
        loadedOnce = true
        loadedModificationDate = modificationDate
        if modificationDate == nil {
            settings = Settings()
            problems = []
        } else if let text = try? String(contentsOf: url, encoding: .utf8) {
            (settings, problems) = Settings.parse(text)
        } else {
            settings = Settings()
            problems = ["settings file: cannot read \(url.path)"]
        }
        return true
    }

    /// Writes the template if the file does not exist.
    func createIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Settings.template.write(to: url, atomically: true, encoding: .utf8)
    }
}
