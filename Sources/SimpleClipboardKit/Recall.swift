import AppKit
import ApplicationServices

/// What a recall puts on the clipboard.
enum RecallFormat: Equatable {
    /// Every stored type, so formatting, images and files come back unchanged.
    case original
    /// Only the text. A clip without text is recalled unchanged.
    case plainText
    /// The text after a filter (`TextFilter.id`).
    case filter(String)
}

/// Gives a stored clip back: always onto the clipboard, and with mode "paste" also as Cmd-V to the frontmost app.
enum Recall {
    enum Outcome: Equatable {
        case onClipboard
        case pasted
        /// Mode "paste" without Accessibility permission. The clip is on the clipboard.
        case needsAccessibility
        /// The filter does not apply to this clip (no text, or for example text that is not Base64). Nothing changed.
        case filterFailed
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// The pasteboard items a recall writes, or nil when a filter does not apply.
    static func items(for stored: [[Representation]], format: RecallFormat) -> [[Representation]]? {
        let stringType = NSPasteboard.PasteboardType.string.rawValue
        switch format {
        case .original:
            return stored
        case .plainText:
            guard let text = TextTransforms.plainText(of: stored) else { return stored }
            return [[Representation(type: stringType, data: Data(text.utf8))]]
        case .filter(let id):
            guard let filter = TextFilter.named(id), let text = TextTransforms.plainText(of: stored),
                  let result = filter.apply(text) else { return nil }
            return [[Representation(type: stringType, data: Data(result.utf8))]]
        }
    }

    static func perform(items stored: [[Representation]], mode: RecallMode, format: RecallFormat = .original,
                        pasteboard: NSPasteboard = .general) -> Outcome {
        guard let items = items(for: stored, format: format) else { return .filterFailed }
        Capture.write(items, to: pasteboard)
        guard mode == .paste else { return .onClipboard }
        guard hasAccessibility else { return .needsAccessibility }
        // The picker has to finish closing so the key event goes to the app the user was in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { sendCommandV() }
        return .pasted
    }

    private static func sendCommandV() {
        let keyV: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Shows the system prompt that adds Simple Clipboard to the Accessibility list (once), then opens
    /// Privacy & Security > Accessibility in System Settings.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
