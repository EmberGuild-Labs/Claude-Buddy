import Foundation

/// What kind of tool Claude is using — each gets its own animation.
enum ToolKind: Hashable {
    case terminal, build, search, web, other

    init(toolName: String) {
        switch toolName {
        case "Bash", "BashOutput", "KillShell", "KillBash": self = .terminal
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "TodoWrite": self = .build
        case "Read", "Grep", "Glob", "LS", "LSP": self = .search
        case "WebFetch", "WebSearch": self = .web
        default: self = toolName.hasPrefix("mcp__") ? .web : .other
        }
    }
}

/// The overall Claude Code state the buddy reacts to.
enum Activity: Equatable {
    case idle, thinking, tool(ToolKind), waiting

    fileprivate var rank: Int {
        switch self {
        case .idle: 0
        case .thinking: 1
        case .tool: 2
        case .waiting: 3
        }
    }
}

/// One-shot moments that trigger a reaction.
enum Pulse { case started, finished, failed, nudge }

/// Folds Claude Code hook events from any number of sessions into one `Activity`.
final class ClaudeActivity {
    private struct Session {
        var state: Activity
        var updated: Date
    }

    private var sessions: [String: Session] = [:]
    private var lastTool: (kind: ToolKind, at: Date)?
    private(set) var lastToolName: String?
    private(set) var lastEventAt: Date?

    /// Sessions that go quiet this long (e.g. a crashed CLI) stop counting as busy.
    var staleAfter: TimeInterval = 15 * 60
    var quiet = false
    var onPulse: ((Pulse) -> Void)?

    /// Highest-priority state across live sessions: waiting > tool > thinking > idle.
    var current: Activity {
        guard !quiet else { return .idle }
        let now = Date()
        var best: Session?
        for s in sessions.values where now.timeIntervalSince(s.updated) < staleAfter {
            guard let b = best else { best = s; continue }
            if s.state.rank > b.state.rank || (s.state.rank == b.state.rank && s.updated > b.updated) { best = s }
        }
        return best?.state ?? .idle
    }

    /// A tool used in the last few seconds, so fast tools (Read, Grep) still get their animation.
    var recentToolKind: ToolKind? {
        guard let t = lastTool, Date().timeIntervalSince(t.at) < 8 else { return nil }
        return t.kind
    }

    var liveSessionCount: Int {
        let now = Date()
        return sessions.values.filter { now.timeIntervalSince($0.updated) < staleAfter }.count
    }

    func handle(_ event: [String: Any]) {
        let name = event["hook_event_name"] as? String ?? ""
        let sid = event["session_id"] as? String ?? "default"
        lastEventAt = Date()

        switch name {
        case "SessionStart":
            set(sid, .idle)
            pulse(.started)
        case "UserPromptSubmit":
            set(sid, .thinking)
        case "PreToolUse":
            let toolName = event["tool_name"] as? String ?? ""
            let kind = ToolKind(toolName: toolName)
            lastTool = (kind, Date())
            lastToolName = toolName
            set(sid, .tool(kind))
        case "PostToolUse":
            set(sid, .thinking)
            if Self.looksLikeFailure(event["tool_response"]) { pulse(.failed) }
        case "PostToolUseFailure":
            set(sid, .thinking)
            pulse(.failed)
        case "Notification":
            let message = event["message"] as? String ?? ""
            let type = event["notification_type"] as? String ?? ""
            // "Waiting for your input" reminders get a quick wave; permission prompts
            // keep the buddy waving until Claude moves on.
            if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") {
                pulse(.nudge)
            } else {
                set(sid, .waiting)
            }
        case "Stop":
            set(sid, .idle)
            pulse(.finished)
        case "SubagentStop":
            sessions[sid]?.updated = Date()
        case "SessionEnd":
            sessions[sid] = nil
        default:
            break
        }
    }

    private func set(_ sid: String, _ state: Activity) {
        sessions[sid] = Session(state: state, updated: Date())
    }

    private func pulse(_ p: Pulse) {
        guard !quiet else { return }
        onPulse?(p)
    }

    private static func looksLikeFailure(_ response: Any?) -> Bool {
        guard let d = response as? [String: Any] else { return false }
        if (d["is_error"] as? Bool) == true || (d["success"] as? Bool) == false { return true }
        if let e = d["error"], !(e is NSNull) { return true }
        return false
    }

    var summary: String {
        switch current {
        case .idle: return "Idle"
        case .thinking: return "Thinking…"
        case .tool: return "Running \(lastToolName ?? "a tool")"
        case .waiting: return "Needs you!"
        }
    }
}
