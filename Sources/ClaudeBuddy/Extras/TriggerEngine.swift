import AppKit

/// Runs pack triggers: "at 14:30", "every 45m between 9–5", "when Xcode opens", "on wake",
/// "when Claude finishes". The decision logic is pure (`shouldFire…`) so the self-test can
/// drive it with fake dates; `start()` hooks it to the real clock and NSWorkspace.
final class TriggerEngine {
    var triggers: [TriggerDef] = [] {
        didSet { lastEvery = lastEvery.filter { k, _ in triggers.contains { $0.key == k } } }
    }
    /// Asked to run an action; the controller queues it if the buddy is busy.
    var fire: ((TriggerDef, TriggerContext) -> Void)?
    var defaults = UserDefaults.standard

    private var lastFired: [String: Date] = [:]
    private var lastEvery: [String: Date] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let startedAt = Date()

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.clockTick(Date()) }
        timer?.tolerance = 3
        let ws = NSWorkspace.shared.notificationCenter
        let appEvents: [(Notification.Name, String)] = [
            (NSWorkspace.didLaunchApplicationNotification, "app-launch"),
            (NSWorkspace.didActivateApplicationNotification, "app-activate"),
            (NSWorkspace.didTerminateApplicationNotification, "app-quit"),
        ]
        for (name, event) in appEvents {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.appEvent(event, name: app.localizedName, bundleID: app.bundleIdentifier, now: Date())
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.simple(.wake, now: Date())
        })
        // Let the buddy land first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.simple(.startup, now: Date()) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }

    // MARK: - Decisions

    /// Checks the time-based triggers.
    func clockTick(_ now: Date) {
        for t in triggers {
            switch t.kind {
            case .at(let h, let m):
                if shouldFireAt(t, hour: h, minute: m, now: now) { fireIfAllowed(t, now: now, markDay: true) }
            case .every(let seconds):
                let last = lastEvery[t.key] ?? startedAt
                if now.timeIntervalSince(last) >= seconds {
                    lastEvery[t.key] = now
                    fireIfAllowed(t, now: now)
                }
            default:
                break
            }
        }
    }

    /// "at" triggers fire once per day, within 10 minutes after their time (a Mac that was
    /// asleep at 14:30 and wakes at 14:35 still gets it; one that wakes at 16:00 doesn't).
    func shouldFireAt(_ t: TriggerDef, hour: Int, minute: Int, now: Date) -> Bool {
        let cal = Calendar.current
        guard let target = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return false }
        let late = now.timeIntervalSince(target)
        guard late >= 0, late < 600 else { return false }
        let day = Self.dayKey(now)
        return defaults.string(forKey: "ext.firedDay.\(t.key)") != day
    }

    func appEvent(_ event: String, name: String?, bundleID: String?, now: Date) {
        for t in triggers {
            guard case .app(let want, let match) = t.kind else { continue }
            let eventMatches = want == event || (want == "app-open" && (event == "app-launch" || event == "app-activate"))
            guard eventMatches, Self.appMatches(match, name: name, bundleID: bundleID) else { continue }
            fireIfAllowed(t, now: now, context: TriggerContext(vars: ["app": name ?? match]))
        }
    }

    /// An idle buddy is standing on a window of this app. Returns true if something fired.
    @discardableResult
    func windowEvent(bundleID: String?, name: String?, subject: Buddy, now: Date) -> Bool {
        var fired = false
        for t in triggers {
            guard case .onWindow(let match) = t.kind, Self.appMatches(match, name: name, bundleID: bundleID) else { continue }
            if fireIfAllowed(t, now: now, context: TriggerContext(subject: subject, vars: ["app": name ?? match])) { fired = true }
        }
        return fired
    }

    /// New incoming texts arrived.
    func newText(count: Int, now: Date = Date()) {
        let vars = ["count": count == 1 ? "a" : "\(count)", "s": count == 1 ? "" : "s"]
        for t in triggers where t.kind == .newText { fireIfAllowed(t, now: now, context: TriggerContext(vars: vars)) }
    }

    static func appMatches(_ match: String, name: String?, bundleID: String?) -> Bool {
        let m = match.lowercased()
        if let b = bundleID?.lowercased(), b == m { return true }
        if let n = name?.lowercased(), n == m || n == m.replacingOccurrences(of: ".app", with: "") { return true }
        // No name to go on (the app isn't running): "Finder" still matches com.apple.finder.
        if name == nil, let last = bundleID?.split(separator: ".").last, last.lowercased() == m { return true }
        return false
    }

    func simple(_ kind: TriggerDef.Kind, now: Date) {
        for t in triggers where t.kind == kind { fireIfAllowed(t, now: now) }
    }

    /// A Claude Code hook event (the same JSON the buddy reacts to).
    func claudeEvent(_ event: [String: Any], now: Date = Date()) {
        guard let name = event["hook_event_name"] as? String else { return }
        let tool = event["tool_name"] as? String
        var vars: [String: String] = ["event": name]
        if let tool { vars["tool"] = tool }
        if let cwd = event["cwd"] as? String { vars["project"] = URL(fileURLWithPath: cwd).lastPathComponent }
        for t in triggers {
            guard case .claude(let want, let wantTool) = t.kind, want == name else { continue }
            if let wantTool, wantTool != tool { continue }
            fireIfAllowed(t, now: now, context: TriggerContext(vars: vars))
        }
    }

    /// Days, time window, cooldown, and chance.
    func allowed(_ t: TriggerDef, now: Date) -> Bool {
        let cal = Calendar.current
        if let days = t.days, !days.contains(cal.component(.weekday, from: now)) { return false }
        if let (start, end) = t.between {
            let minute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
            let inside = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
            if !inside { return false }
        }
        if t.cooldown > 0, let last = lastFired[t.key], now.timeIntervalSince(last) < t.cooldown { return false }
        return true
    }

    @discardableResult
    private func fireIfAllowed(_ t: TriggerDef, now: Date, markDay: Bool = false, context: TriggerContext = TriggerContext()) -> Bool {
        guard allowed(t, now: now) else { return false }
        lastFired[t.key] = now
        if markDay { defaults.set(Self.dayKey(now), forKey: "ext.firedDay.\(t.key)") }
        guard t.chance >= 1 || Double.random(in: 0..<1) < t.chance else { return false }
        fire?(t, context)
        return true
    }

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

/// What a trigger was about: the buddy involved (if any) and words for `{placeholders}`.
struct TriggerContext {
    var subject: Buddy?
    var vars: [String: String] = [:]
}
