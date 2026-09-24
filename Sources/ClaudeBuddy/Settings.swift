import Foundation

final class Settings {
    static let shared = Settings()
    static let port: UInt16 = 47823
    static let sizeNames = ["Small", "Medium", "Large"]
    private static let pixelScales: [CGFloat] = [3, 4, 6]

    private let defaults = UserDefaults.standard

    var visible: Bool {
        get { defaults.object(forKey: "visible") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "visible") }
    }

    /// Ignore Claude Code events; the buddy just wanders.
    var quiet: Bool {
        get { defaults.bool(forKey: "quiet") }
        set { defaults.set(newValue, forKey: "quiet") }
    }

    var sizeIndex: Int {
        get { min(max(defaults.object(forKey: "size") as? Int ?? 1, 0), 2) }
        set { defaults.set(newValue, forKey: "size") }
    }

    /// Walk on whichever display the mouse is on, instead of the main display.
    var followMouse: Bool {
        get { defaults.bool(forKey: "followMouse") }
        set { defaults.set(newValue, forKey: "followMouse") }
    }

    var pixelScale: CGFloat { Self.pixelScales[sizeIndex] }

    /// Each extra Claude Code session gets its own buddy.
    var sessionBuddies: Bool {
        get { defaults.object(forKey: "sessionBuddies") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sessionBuddies") }
    }

    /// Eyes follow the cursor; buddies come over to play or get startled by fast swipes.
    var cursorReactions: Bool {
        get { defaults.object(forKey: "cursorReactions") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cursorReactions") }
    }

    /// System-wide shortcut that toggles the Today billboard.
    var todayShortcut: HotKey.Choice {
        get { defaults.string(forKey: "todayShortcut").flatMap(HotKey.Choice.init(rawValue:)) ?? .controlOptionT }
        set { defaults.set(newValue.rawValue, forKey: "todayShortcut") }
    }

    /// System-wide shortcut that starts (or ends) a nap.
    var napShortcut: HotKey.Choice {
        get { defaults.string(forKey: "napShortcut").flatMap(HotKey.Choice.init(rawValue:)) ?? .controlOptionN }
        set { defaults.set(newValue.rawValue, forKey: "napShortcut") }
    }

    /// Buddies hop onto the tops of app windows.
    var climbWindows: Bool {
        get { defaults.object(forKey: "climbWindows") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "climbWindows") }
    }

    /// Dance when Spotify or Apple Music is playing.
    var danceToMusic: Bool {
        get { defaults.object(forKey: "danceToMusic") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "danceToMusic") }
    }

    /// The main buddy's hat: nil = seasonal (automatic).
    var mainHat: Hat? {
        get { defaults.string(forKey: "mainHat").flatMap(Hat.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "mainHat") }
    }

    /// First launch, for the buddy's birthday party hat.
    var installedAt: Date {
        if let d = defaults.object(forKey: "installedAt") as? Date { return d }
        let now = Date()
        defaults.set(now, forKey: "installedAt")
        return now
    }
}
