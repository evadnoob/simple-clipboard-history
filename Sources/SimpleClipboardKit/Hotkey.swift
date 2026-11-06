import AppKit
import Carbon.HIToolbox

/// The key combinations offered for opening the picker.
enum HotkeyChoice: String, CaseIterable {
    case shiftCommandV
    case optionCommandV
    case controlCommandV
    case shiftOptionCommandV
    case none

    static let defaultChoice = HotkeyChoice.shiftCommandV

    var keyCode: UInt32 { UInt32(kVK_ANSI_V) }

    var carbonModifiers: UInt32 {
        switch self {
        case .shiftCommandV: return UInt32(cmdKey | shiftKey)
        case .optionCommandV: return UInt32(cmdKey | optionKey)
        case .controlCommandV: return UInt32(cmdKey | controlKey)
        case .shiftOptionCommandV: return UInt32(cmdKey | shiftKey | optionKey)
        case .none: return 0
        }
    }

    /// For showing the shortcut on a menu item.
    var menuModifiers: NSEvent.ModifierFlags {
        switch self {
        case .shiftCommandV: return [.command, .shift]
        case .optionCommandV: return [.command, .option]
        case .controlCommandV: return [.command, .control]
        case .shiftOptionCommandV: return [.command, .shift, .option]
        case .none: return []
        }
    }

    var title: String {
        switch self {
        case .shiftCommandV: return "Shift-Command-V"
        case .optionCommandV: return "Option-Command-V"
        case .controlCommandV: return "Control-Command-V"
        case .shiftOptionCommandV: return "Shift-Option-Command-V"
        case .none: return "None"
        }
    }
}

/// One system-wide hotkey through the Carbon hotkey API, which needs no permission.
final class GlobalHotkey {
    enum Status: Equatable {
        case off
        case registered(HotkeyChoice)
        /// Usually another app already uses the combination.
        case failed(HotkeyChoice, OSStatus)
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private(set) var status: Status = .off

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.action() }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func register(_ choice: HotkeyChoice) {
        unregister()
        guard choice != .none else { status = .off; return }
        let identifier = EventHotKeyID(signature: OSType(0x5343_4C50), id: 1) // "SCLP"
        let result = RegisterEventHotKey(choice.keyCode, choice.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        status = result == noErr ? .registered(choice) : .failed(choice, result)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        status = .off
    }
}
