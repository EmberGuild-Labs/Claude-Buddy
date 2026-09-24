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

/// The Claude Code state a buddy reacts to.
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

/// A live Claude Code session as a buddy sees it.
struct SessionInfo {
    let id: String
    let activity: Activity
    /// A tool used in the last few seconds, so fast tools (Read, Grep) still get their animation.
    let recentTool: ToolKind?
    /// Folder name of the session's working directory, for the buddy's name tag.
    let project: String?
}

/// Tracks Claude Code sessions from hook events.
final class ClaudeActivity {
    private struct Session {
        var state: Activity
        var updated: Date
        let started: Date
        var project: String?
        var lastTool: (kind: ToolKind, at: Date)?
    }

    private var sessions: [String: Session] = [:]
    private var lastTool: (kind: ToolKind, at: Date)?
    private(set) var lastToolName: String?
    private(set) var lastEventAt: Date?

    /// A session silent this long no longer counts as busy (e.g. a crashed CLI)…
    var busyTimeout: TimeInterval = 15 * 60
    /// …and after this long it's forgotten entirely (its buddy leaves).
    var presenceTimeout: TimeInterval = 45 * 60
    var quiet = false
    /// A pulse and the session it came from.
    var onPulse: ((Pulse, String) -> Void)?

    private func activity(of s: Session, now: Date) -> Activity {
        now.timeIntervalSince(s.updated) < busyTimeout ? s.state : .idle
    }

    /// Live sessions, oldest first.
    var liveSessions: [SessionInfo] {
        guard !quiet else { return [] }
        let now = Date()
        return sessions
            .filter { now.timeIntervalSince($0.value.updated) < presenceTimeout }
            .sorted { $0.value.started < $1.value.started }
            .map { id, s in
                let recent = s.lastTool.flatMap { now.timeIntervalSince($0.at) < 8 ? $0.kind : nil }
                return SessionInfo(id: id, activity: activity(of: s, now: now), recentTool: recent, project: s.project)
            }
    }

    /// Everything merged into one: waiting > tool > thinking > idle.
    var aggregate: SessionInfo {
        guard !quiet else { return SessionInfo(id: "*", activity: .idle, recentTool: nil, project: nil) }
        let now = Date()
        var best: Session?
        for s in sessions.values where now.timeIntervalSince(s.updated) < busyTimeout {
            guard let b = best else { best = s; continue }
            if s.state.rank > b.state.rank || (s.state.rank == b.state.rank && s.updated > b.updated) { best = s }
        }
        let recent = lastTool.flatMap { now.timeIntervalSince($0.at) < 8 ? $0.kind : nil }
        return SessionInfo(id: "*", activity: best?.state ?? .idle, recentTool: recent, project: nil)
    }

    func handle(_ event: [String: Any]) {
        let name = event["hook_event_name"] as? String ?? ""
        let sid = event["session_id"] as? String ?? "default"
        let now = Date()
        lastEventAt = now

        if name == "SessionEnd" {
            sessions[sid] = nil
            return
        }
        var s = sessions[sid] ?? Session(state: .idle, updated: now, started: now)
        s.updated = now
        if let cwd = event["cwd"] as? String, !cwd.isEmpty {
            s.project = URL(fileURLWithPath: cwd).lastPathComponent
        }

        switch name {
        case "SessionStart":
            s.state = .idle
            sessions[sid] = s
            pulse(.started, sid)
        case "UserPromptSubmit":
            s.state = .thinking
        case "PreToolUse":
            let toolName = event["tool_name"] as? String ?? ""
            let kind = ToolKind(toolName: toolName)
            s.lastTool = (kind, now)
            s.state = .tool(kind)
            lastTool = (kind, now)
            lastToolName = toolName
        case "PostToolUse":
            s.state = .thinking
            if Self.looksLikeFailure(event["tool_response"]) { sessions[sid] = s; pulse(.failed, sid) }
        case "PostToolUseFailure":
            s.state = .thinking
            sessions[sid] = s
            pulse(.failed, sid)
        case "Notification":
            let message = event["message"] as? String ?? ""
            let type = event["notification_type"] as? String ?? ""
            // "Waiting for your input" reminders get a quick wave; permission prompts
            // keep the buddy waving until Claude moves on.
            if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") {
                sessions[sid] = s
                pulse(.nudge, sid)
            } else {
                s.state = .waiting
            }
        case "Stop":
            s.state = .idle
            sessions[sid] = s
            pulse(.finished, sid)
        default:
            break
        }
        sessions[sid] = s
    }

    private func pulse(_ p: Pulse, _ sid: String) {
        guard !quiet else { return }
        onPulse?(p, sid)
    }

    private static func looksLikeFailure(_ response: Any?) -> Bool {
        guard let d = response as? [String: Any] else { return false }
        if (d["is_error"] as? Bool) == true || (d["success"] as? Bool) == false { return true }
        if let e = d["error"], !(e is NSNull) { return true }
        return false
    }

    var summary: String {
        switch aggregate.activity {
        case .idle: return "Idle"
        case .thinking: return "Thinking…"
        case .tool: return "Running \(lastToolName ?? "a tool")"
        case .waiting: return "Needs you!"
        }
    }
}
