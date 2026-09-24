import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (works in any app, no Accessibility permission needed).
final class HotKey {
    /// The shortcut choices offered in the menu.
    enum Choice: String, CaseIterable {
        case controlOptionT, optionCommandT, controlOptionSpace, optionT
        case controlOptionN, optionCommandN, controlOptionZ
        case off

        static let todayChoices: [Choice] = [.controlOptionT, .optionCommandT, .controlOptionSpace, .optionT, .off]
        static let napChoices: [Choice] = [.controlOptionN, .optionCommandN, .controlOptionZ, .off]

        var title: String {
            switch self {
            case .controlOptionT: "⌃⌥T"
            case .optionCommandT: "⌥⌘T"
            case .controlOptionSpace: "⌃⌥Space"
            case .optionT: "⌥T  (stops ⌥T from typing †)"
            case .controlOptionN: "⌃⌥N"
            case .optionCommandN: "⌥⌘N"
            case .controlOptionZ: "⌃⌥Z"
            case .off: "Off"
            }
        }

        var keyCode: UInt32? {
            switch self {
            case .controlOptionT, .optionCommandT, .optionT: UInt32(kVK_ANSI_T)
            case .controlOptionSpace: UInt32(kVK_Space)
            case .controlOptionN, .optionCommandN: UInt32(kVK_ANSI_N)
            case .controlOptionZ: UInt32(kVK_ANSI_Z)
            case .off: nil
            }
        }

        var carbonModifiers: UInt32 {
            switch self {
            case .controlOptionT, .controlOptionSpace, .controlOptionN, .controlOptionZ: UInt32(controlKey | optionKey)
            case .optionCommandT, .optionCommandN: UInt32(optionKey | cmdKey)
            case .optionT: UInt32(optionKey)
            case .off: 0
            }
        }

        /// For showing the shortcut next to the menu item.
        var menuKey: String {
            switch self {
            case .controlOptionSpace: " "
            case .controlOptionN, .optionCommandN: "n"
            case .controlOptionZ: "z"
            default: "t"
            }
        }
        var menuModifiers: NSEvent.ModifierFlags {
            switch self {
            case .controlOptionT, .controlOptionSpace, .controlOptionN, .controlOptionZ: [.control, .option]
            case .optionCommandT, .optionCommandN: [.option, .command]
            case .optionT: [.option]
            case .off: []
            }
        }
    }

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void
    private(set) var registered: Choice = .off
    /// Set when another app already owns the chosen shortcut.
    private(set) var failed = false

    /// Each shortcut needs its own `id`; every handler sees every hot key press, so each
    /// checks the id and passes on presses that aren't its own.
    init(id: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Switches to `choice`. Returns false if another app already uses it.
    @discardableResult
    func register(_ choice: Choice) -> Bool {
        unregister()
        registered = choice
        failed = false
        guard let key = choice.keyCode else { return true }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4342_5544), id: id)  // "CBUD"
        let status = RegisterEventHotKey(key, choice.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        failed = status != noErr
        return !failed
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
