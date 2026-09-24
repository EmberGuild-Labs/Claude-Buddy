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
}
