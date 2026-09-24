import Foundation

/// Adds/removes the buddy's hooks in ~/.claude/settings.json, leaving everything else untouched.
enum HookInstaller {
    enum Failure: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): "Couldn't read Claude settings: \(why)"
            }
        }
    }

    static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse",
        "PostToolUse", "Notification", "Stop", "SubagentStop",
    ]
    private static let toolEvents: Set = ["PreToolUse", "PostToolUse"]

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Forwards the hook payload to the buddy. Never prints to stdout (UserPromptSubmit and
    /// SessionStart would add it to Claude's context) and always exits 0, even if the buddy
    /// isn't running. `Expect:` stops curl waiting on 100-continue for big payloads.
    static func command(port: UInt16) -> String {
        "curl -s -m 1 -o /dev/null -H 'Content-Type: application/json' -H 'Expect:' "
            + "--data-binary @- http://127.0.0.1:\(port)\(EventServer.eventPath) >/dev/null 2>&1 || true"
    }

    static func isInstalled(at url: URL = defaultSettingsURL) -> Bool {
        guard let settings = try? load(url), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]])?.contains(where: containsBuddyHook) ?? false
        }
    }

    /// Returns the backup file's URL, if there was an existing file to back up.
    @discardableResult
    static func install(port: UInt16, at url: URL = defaultSettingsURL) throws -> URL? {
        var settings = try load(url)
        var hooks = stripped(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(port: port), "timeout": 3]]]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        settings["hooks"] = hooks
        return try save(settings, to: url)
    }

    @discardableResult
    static func uninstall(at url: URL = defaultSettingsURL) throws -> URL? {
        var settings = try load(url)
        guard let hooks = settings["hooks"] as? [String: Any] else { return nil }
        let cleaned = stripped(hooks)
        settings["hooks"] = cleaned.isEmpty ? nil : cleaned
        return try save(settings, to: url)
    }

    // MARK: -

    private static func containsBuddyHook(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String)?.contains(EventServer.eventPath) == true
        }
    }

    /// Removes our hook commands; drops groups and events that end up empty.
    private static func stripped(_ hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard containsBuddyHook(group) else { return group }
                var g = group
                let remaining = (g["hooks"] as? [[String: Any]] ?? []).filter {
                    ($0["command"] as? String)?.contains(EventServer.eventPath) != true
                }
                if remaining.isEmpty { return nil }
                g["hooks"] = remaining
                return g
            }
            result[event] = kept.isEmpty ? nil : kept
        }
        return result
    }

    private static func load(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure.unreadable("top level isn't a JSON object")
            }
            return dict
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
    }

    private static func save(_ settings: [String: Any], to url: URL) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fm.fileExists(atPath: url.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let b = url.deletingLastPathComponent().appendingPathComponent("settings.json.claude-buddy-backup-\(stamp)")
            try? fm.removeItem(at: b)
            try fm.copyItem(at: url, to: b)
            backup = b
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        return backup
    }
}
