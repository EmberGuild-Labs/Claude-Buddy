import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (works in any app, no Accessibility permission needed).
final class HotKey {
    /// The shortcut choices offered in the menu.
    enum Choice: String, CaseIterable {
        case controlOptionT, optionCommandT, controlOptionSpace, optionT, off

        var title: String {
            switch self {
            case .controlOptionT: "⌃⌥T"
            case .optionCommandT: "⌥⌘T"
            case .controlOptionSpace: "⌃⌥Space"
            case .optionT: "⌥T  (stops ⌥T from typing †)"
            case .off: "Off"
            }
        }

        var keyCode: UInt32? {
            switch self {
            case .controlOptionT, .optionCommandT, .optionT: UInt32(kVK_ANSI_T)
            case .controlOptionSpace: UInt32(kVK_Space)
            case .off: nil
            }
        }

        var carbonModifiers: UInt32 {
            switch self {
            case .controlOptionT, .controlOptionSpace: UInt32(controlKey | optionKey)
            case .optionCommandT: UInt32(optionKey | cmdKey)
            case .optionT: UInt32(optionKey)
            case .off: 0
            }
        }

        /// For showing the shortcut next to the menu item.
        var menuKey: String { self == .controlOptionSpace ? " " : "t" }
        var menuModifiers: NSEvent.ModifierFlags {
            switch self {
            case .controlOptionT, .controlOptionSpace: [.control, .option]
            case .optionCommandT: [.option, .command]
            case .optionT: [.option]
            case .off: []
            }
        }
    }

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var registered: Choice = .off
    /// Set when another app already owns the chosen shortcut.
    private(set) var failed = false

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
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
        let id = EventHotKeyID(signature: OSType(0x4342_5544), id: 1)  // "CBUD"
        let status = RegisterEventHotKey(key, choice.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        failed = status != noErr
        return !failed
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
