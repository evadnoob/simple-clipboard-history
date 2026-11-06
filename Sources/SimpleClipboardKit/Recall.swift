import AppKit
import ApplicationServices

/// Gives a stored clip back: always onto the clipboard, and with mode "paste" also as Cmd-V to the frontmost app.
enum Recall {
    enum Outcome: Equatable {
        case onClipboard
        case pasted
        /// Mode "paste" without Accessibility permission. The clip is on the clipboard.
        case needsAccessibility
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func perform(items: [[Representation]], mode: RecallMode, pasteboard: NSPasteboard = .general) -> Outcome {
        Capture.write(items, to: pasteboard)
        guard mode == .paste else { return .onClipboard }
        guard hasAccessibility else { return .needsAccessibility }
        // The menu has to finish closing so the key event goes to the app the user was in.
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

    /// Opens Privacy & Security > Accessibility in System Settings.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
