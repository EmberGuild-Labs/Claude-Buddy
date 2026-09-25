import AppKit
import Carbon.HIToolbox

/// Key names used in packs ("f", "space", "up", "f5", "slash") and their virtual key codes.
enum KeyNames {
    static let codes: [String: Int] = {
        var m: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape,
            "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "minus": kVK_ANSI_Minus, "equals": kVK_ANSI_Equal, "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period,
            "slash": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
            "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket, "backslash": kVK_ANSI_Backslash,
            "grave": kVK_ANSI_Grave,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ]
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, k) in fkeys.enumerated() { m["f\(i + 1)"] = k }
        return m
    }()

    static func code(for name: String) -> UInt32? { codes[canonical(name)].map { UInt32($0) } }

    static func canonical(_ name: String) -> String {
        switch name.lowercased() {
        case "esc": "escape"
        case "enter": "return"
        case "backspace": "delete"
        default: name.lowercased()
        }
    }

    /// How a key looks in the buddy's pixel-font bubble.
    static func display(_ name: String) -> String {
        switch canonical(name) {
        case "up": "▲"
        case "down": "▼"
        case "left": "◄"
        case "right": "►"
        case "space": "SPC"
        case "return": "RET"
        case "escape": "ESC"
        case "delete": "DEL"
        case let n where n.count == 1: n.uppercased()
        case let n: n.uppercased()
        }
    }

    /// How a key looks in a menu.
    static func menuSymbol(_ name: String) -> String {
        switch canonical(name) {
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "space": "Space"
        case "return": "↩"
        case "escape": "⎋"
        case "delete": "⌫"
        case "tab": "⇥"
        case let n: n.uppercased()
        }
    }
}

/// A global shortcut like "ctrl+opt+b".
struct KeyCombo: Hashable {
    let key: String
    let code: UInt32
    let carbonModifiers: UInt32
    let modifierNames: [String]

    static func parse(_ text: String) -> KeyCombo? {
        let parts = text.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init)
        guard let keyName = parts.last, let code = KeyNames.code(for: keyName) else { return nil }
        var mods: UInt32 = 0
        var names: [String] = []
        for m in parts.dropLast() {
            switch m {
            case "ctrl", "control", "⌃": mods |= UInt32(controlKey); names.append("ctrl")
            case "opt", "option", "alt", "⌥": mods |= UInt32(optionKey); names.append("opt")
            case "cmd", "command", "⌘": mods |= UInt32(cmdKey); names.append("cmd")
            case "shift", "⇧": mods |= UInt32(shiftKey); names.append("shift")
            default: return nil
            }
        }
        // A shortcut with no modifiers would swallow that key everywhere, all the time.
        guard mods != 0 || keyName.hasPrefix("f") && keyName.count > 1 else { return nil }
        return KeyCombo(key: KeyNames.canonical(keyName), code: code, carbonModifiers: mods, modifierNames: names)
    }

    var title: String {
        var s = ""
        if modifierNames.contains("ctrl") { s += "⌃" }
        if modifierNames.contains("opt") { s += "⌥" }
        if modifierNames.contains("shift") { s += "⇧" }
        if modifierNames.contains("cmd") { s += "⌘" }
        return s + KeyNames.menuSymbol(key)
    }
}

/// System-wide key grabs for Extras: shortcuts from packs, the leader key, and the keys it
/// listens for briefly afterwards (and puppet controls). Carbon hot keys need no Accessibility
/// permission; a grabbed key doesn't reach other apps, so bare keys are only grabbed briefly.
final class KeyGrabber {
    static let shared = KeyGrabber()

    private struct Grab {
        let ref: EventHotKeyRef
        let action: (_ down: Bool) -> Void
    }
    private var grabs: [UInt32: Grab] = [:]
    private var nextID: UInt32 = 1000   // HotKey uses small ids; stay well clear.
    private var handler: EventHandlerRef?
    private static let signature = OSType(0x4342_4558)  // "CBEX"

    private init() {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.signature == KeyGrabber.signature else { return OSStatus(eventNotHandledErr) }
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = pressed.id
            DispatchQueue.main.async { KeyGrabber.shared.grabs[id]?.action(down) }
            return noErr
        }, 2, &specs, nil, &handler)
    }

    /// Returns an id for `release`, or nil if another app already owns the key.
    func grab(code: UInt32, modifiers: UInt32, action: @escaping (_ down: Bool) -> Void) -> UInt32? {
        var ref: EventHotKeyRef?
        let id = nextID
        nextID += 1
        let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        grabs[id] = Grab(ref: ref, action: action)
        return id
    }

    func release(_ id: UInt32) {
        guard let g = grabs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(g.ref)
    }

    func release(_ ids: [UInt32]) { ids.forEach(release) }
}

/// Matches keys typed after the leader key against the packs' sequences.
struct SequenceMatcher {
    enum Result: Equatable {
        /// Fires now: nothing longer starts this way.
        case run(Int)
        /// Complete, but a longer sequence also starts this way: wait briefly for more keys.
        case runUnlessMore(Int)
        /// Could still become a sequence.
        case partial
        case none
    }

    let sequences: [[String]]

    func match(_ typed: [String]) -> Result {
        let t = typed.map(KeyNames.canonical)
        guard !t.isEmpty else { return .partial }
        var exact: Int?
        var longer = false
        for (i, seq) in sequences.enumerated() {
            let s = seq.map(KeyNames.canonical)
            if s == t { exact = exact ?? i } else if s.count > t.count && Array(s.prefix(t.count)) == t { longer = true }
        }
        if let exact { return longer ? .runUnlessMore(exact) : .run(exact) }
        return longer ? .partial : .none
    }

    /// Every key some sequence uses (the only keys grabbed while listening).
    var keys: Set<String> { Set(sequences.flatMap { $0.map(KeyNames.canonical) }) }
}

/// The leader key: press it, then type a short sequence ("up up down down") within a couple of
/// seconds. The buddy shows what you've typed so far.
final class LeaderListener {
    private(set) var isListening = false
    private var typed: [String] = []
    private var grabIDs: [UInt32] = []
    private var timer: DispatchWorkItem?
    var matcher = SequenceMatcher(sequences: [])
    /// Called with the sequence index to run.
    var onMatch: ((Int) -> Void)?
    /// Esc while listening.
    var onEscape: (() -> Void)?
    /// What to show in the bubble (nil = hide).
    var onDisplay: ((String?) -> Void)?
    var timeout: TimeInterval = 2.5
    /// For tests: don't touch real hot keys.
    var grabKeys = true

    func begin() {
        if isListening { return finish(showing: nil) }  // Leader twice = never mind.
        isListening = true
        typed = []
        if grabKeys {
            for name in matcher.keys.union(["escape"]) {
                guard let code = KeyNames.code(for: name) else { continue }
                if let id = KeyGrabber.shared.grab(code: code, modifiers: 0, action: { [weak self] down in
                    if down { self?.key(name) }
                }) { grabIDs.append(id) }
            }
        }
        onDisplay?("...")
        restartTimer()
    }

    func key(_ raw: String) {
        guard isListening else { return }
        let name = KeyNames.canonical(raw)
        if name == "escape" {
            finish(showing: nil)
            onEscape?()
            return
        }
        typed.append(name)
        onDisplay?(typed.map(KeyNames.display).joined(separator: " "))
        switch matcher.match(typed) {
        case .run(let i):
            finish(showing: nil)
            onMatch?(i)
        case .runUnlessMore:
            restartTimer(after: 0.6)
        case .partial:
            restartTimer()
        case .none:
            finish(showing: "?")
        }
    }

    /// Time's up: run a complete sequence that was waiting for more keys, else give up.
    func expire() {
        guard isListening else { return }
        if case .runUnlessMore(let i) = matcher.match(typed) {
            finish(showing: nil)
            onMatch?(i)
        } else {
            finish(showing: typed.isEmpty ? nil : "?")
        }
    }

    func finish(showing text: String?) {
        timer?.cancel()
        timer = nil
        KeyGrabber.shared.release(grabIDs)
        grabIDs = []
        isListening = false
        typed = []
        onDisplay?(text)
    }

    private func restartTimer(after seconds: TimeInterval? = nil) {
        timer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.expire() }
        timer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (seconds ?? timeout), execute: item)
    }
}
