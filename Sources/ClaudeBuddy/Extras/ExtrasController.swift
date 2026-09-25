import AppKit

/// Glue for Extras in the running app: loads packs, registers their shortcuts and the leader
/// key, runs triggers, builds the "Extras" menu, and answers the `/claude-buddy/do` endpoint.
final class ExtrasController {
    let stage: BuddyStage
    private let defaults = UserDefaults.standard
    private let triggersEngine = TriggerEngine()
    private let leader = LeaderListener()
    private var leaderGrab: UInt32?
    private(set) var leaderFailed = false
    private var bindingGrabs: [UInt32] = []
    /// Shortcuts another app already owns.
    private(set) var failedBindings: [String] = []
    private var sequenceActions: [ActionSpec] = []
    private var pending: [(action: ActionSpec, label: String, expires: Date, context: TriggerContext)] = []
    let messages = MessagesWatcher()
    private var appNames: [String: String] = [:]
    private var queueTimer: Timer?
    private var adHocCount = 0
    /// False while the buddy is hidden: triggers wait instead of running unseen.
    var canPerform: () -> Bool = { true }

    static let leaderChoices = ["ctrl+opt+b", "cmd+opt+b", "ctrl+opt+g", "ctrl+opt+/", "off"]

    var leaderSetting: String {
        get { defaults.string(forKey: "ext.leader") ?? "ctrl+opt+b" }
        set { defaults.set(newValue, forKey: "ext.leader") }
    }
    var worn: [String] {
        get { defaults.stringArray(forKey: "ext.worn") ?? [] }
        set { defaults.set(newValue, forKey: "ext.worn") }
    }
    /// The built-in pack's automatic treats (coffee break, pizza party, coffee refill).
    var builtinTriggers: Bool {
        get { defaults.object(forKey: "ext.builtinTriggers") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ext.builtinTriggers") }
    }
    /// Opt-in: watch the Messages database for new texts (needs Full Disk Access).
    var watchTexts: Bool {
        get { defaults.bool(forKey: "ext.watchTexts") }
        set { defaults.set(newValue, forKey: "ext.watchTexts") }
    }
    var disabledPacks: Set<String> {
        get { Set(defaults.stringArray(forKey: "ext.disabledPacks") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "ext.disabledPacks") }
    }

    init(stage: BuddyStage) {
        self.stage = stage
        leader.onMatch = { [weak self] i in
            guard let self, i < self.sequenceActions.count else { return }
            self.perform(self.sequenceActions[i], label: "leader", queueIfBusy: false)
        }
        leader.onEscape = { [weak self] in self?.stage.director.cancel() }
        leader.onDisplay = { [weak self] text in self?.stage.director.showHUD(text, for: text == "?" ? 1 : 3) }
        triggersEngine.fire = { [weak self] t, context in
            let run = {
                guard let self else { return }
                if let c = t.condition, !ExtrasConditions.evaluate(c, stage: self.stage) { return }
                self.perform(t.action, label: "trigger", queueIfBusy: true, context: context)
            }
            if t.delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + t.delay, execute: run) } else { run() }
        }
        messages.onNewTexts = { [weak self] n in self?.triggersEngine.newText(count: n) }
    }

    func start() {
        reload()
        triggersEngine.start()
        queueTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.drainQueue()
            self?.checkWindows()
        }
        if watchTexts { messages.start() }
    }

    /// An idle buddy standing on an app's window can set off an "on-window" trigger (the Finder heist).
    func checkWindows(now: Date = Date()) {
        guard canPerform(), !stage.director.isActive, !stage.nap.isActive, !stage.boardOpen else { return }
        for b in stage.buddies where b.platform > 0 && b.canJoinGame && !b.isScripted {
            guard let owner = stage.windowPlatforms[b.platform]?.owner else { continue }
            if triggersEngine.windowEvent(bundleID: owner, name: appName(owner), subject: b, now: now) { return }
        }
    }

    private func appName(_ bundleID: String) -> String? {
        if let n = appNames[bundleID] { return n }
        let n = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
        appNames[bundleID] = n
        return n
    }

    /// Turns the new-text watcher on or off; asks for Full Disk Access if it can't read Messages.
    func setWatchTexts(_ on: Bool) {
        watchTexts = on
        guard on else { return messages.stop() }
        messages.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.watchTexts, self.messages.access != .ok else { return }
            self.explainFullDiskAccess()
        }
    }

    private func explainFullDiskAccess() {
        let alert = NSAlert()
        alert.messageText = "Let Claude Buddy notice new texts?"
        alert.informativeText = """
        To see when a text arrives, Claude Buddy reads your Messages database, and macOS only allows that with Full Disk Access.

        It opens the database read-only and only counts new incoming messages. It never reads who they're from or what they say, and never changes anything.

        In System Settings → Privacy & Security → Full Disk Access, turn on ClaudeBuddy (use + to add it from Applications if it isn't listed), then turn Watch for New Texts off and on again.

        Rebuilding Claude Buddy from source gives it a new signature, so you may need to turn this on again after an update.
        """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(MessagesWatcher.fullDiskAccessSettings) }
    }

    /// Re-reads the packs folder and re-registers everything.
    func reload() {
        ExtrasCatalog.current = ExtrasCatalog.load(disabled: disabledPacks)
        let catalog = ExtrasCatalog.current
        applyWorn()
        KeyGrabber.shared.release(bindingGrabs)
        bindingGrabs = []
        failedBindings = []
        for b in catalog.bindings {
            guard let text = b.keys, let combo = KeyCombo.parse(text) else { continue }
            if let id = KeyGrabber.shared.grab(code: combo.code, modifiers: combo.carbonModifiers, action: { [weak self] down in
                if down { self?.perform(b.action, label: combo.title, queueIfBusy: false) }
            }) {
                bindingGrabs.append(id)
            } else {
                failedBindings.append(combo.title)
            }
        }
        let seqs = catalog.bindings.filter { $0.sequence != nil }
        sequenceActions = seqs.map(\.action)
        leader.matcher = SequenceMatcher(sequences: seqs.compactMap(\.sequence))
        registerLeader()
        triggersEngine.triggers = catalog.triggers.filter { builtinTriggers || $0.pack != "builtin" }
    }

    private func registerLeader() {
        if let leaderGrab { KeyGrabber.shared.release(leaderGrab) }
        leaderGrab = nil
        leaderFailed = false
        guard let combo = KeyCombo.parse(leaderSetting) else { return }
        leaderGrab = KeyGrabber.shared.grab(code: combo.code, modifiers: combo.carbonModifiers) { [weak self] down in
            if down { self?.leader.begin() }
        }
        leaderFailed = leaderGrab == nil
    }

    private func applyWorn() {
        let known = ExtrasCatalog.current.accessories
        stage.mainBuddy?.accessories = worn.filter { known[$0] != nil }
    }

    func claudeEvent(_ event: [String: Any]) { triggersEngine.claudeEvent(event) }

    /// For the self-test: use these triggers without reloading packs or grabbing keys.
    func useTriggers(_ triggers: [TriggerDef]) { triggersEngine.triggers = triggers }

    // MARK: - Running things

    @discardableResult
    func perform(_ action: ActionSpec, label: String, queueIfBusy: Bool, context: TriggerContext = TriggerContext()) -> ActivityDirector.StartResult {
        guard let def = activity(for: action) else { return .unknown }
        if !canPerform() {
            if queueIfBusy { enqueue(action, label: label, context: context) }
            return .busy("Hidden")
        }
        let result = stage.director.start(def, preferred: context.subject, vars: context.vars)
        switch result {
        case .busy(let why):
            if queueIfBusy { enqueue(action, label: label, context: context) } else { stage.director.showHUD(why, for: 1.5) }
        case .unavailable(let why):
            stage.director.showHUD(why, for: 2)
        default:
            break
        }
        return result
    }

    private func activity(for action: ActionSpec) -> ActivityDef? {
        let catalog = ExtrasCatalog.current
        if let id = action.run { return catalog.activities[id] }
        adHocCount += 1
        let steps = action.steps ?? action.say.map { [Step.say(who: nil, text: $0, time: min(8, 2 + Double($0.count) * 0.07))] } ?? []
        return ActivityDef(id: "adhoc-\(adHocCount)", title: action.label, cast: [RoleSpec(name: "star", who: .main, ifMissing: .summon, hat: nil)],
                           props: [:], steps: steps, inMenu: false, greetAtEnd: action.say == nil, pack: "adhoc")
    }

    private func enqueue(_ action: ActionSpec, label: String, context: TriggerContext) {
        pending.removeAll { $0.action == action }
        pending.append((action, label, Date().addingTimeInterval(120), context))
    }

    private func drainQueue() {
        pending.removeAll { $0.expires < Date() }
        guard let next = pending.first, canPerform(), !stage.director.isActive, !stage.nap.isActive else { return }
        pending.removeFirst()
        let r = perform(next.action, label: next.label, queueIfBusy: false, context: next.context)
        if case .busy = r { pending.insert(next, at: 0) }
    }

    // MARK: - HTTP

    /// `POST /claude-buddy/do` with {"run": "fishing"}, {"say": "Hi"}, {"steps": […]}, or {"stop": true};
    /// `GET /claude-buddy/extras` lists what's loaded; `POST /claude-buddy/extras/reload` reloads packs.
    func handle(method: String, path: String, body: Data) -> (Int, String)? {
        switch (method, path) {
        case ("POST", "/claude-buddy/do"):
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return (400, "Send JSON like {\"run\": \"backflip\"}.\n") }
            if json["stop"] as? Bool == true {
                stage.director.cancel()
                return (200, "stopped\n")
            }
            var steps: [Step]?
            if let list = json["steps"] as? [Any] {
                let (parsed, problems) = PackParser.adHocSteps(list)
                let issues = problems + ExtrasCatalog.current.issues(inAdHoc: parsed)
                if !issues.isEmpty { return (400, issues.joined(separator: "\n") + "\n") }
                steps = parsed
            }
            let action = ActionSpec(run: json["run"] as? String, steps: steps, say: json["say"] as? String)
            if action.run == nil && action.steps == nil && action.say == nil { return (400, "Needs run, say, steps, or stop.\n") }
            switch perform(action, label: "http", queueIfBusy: json["queue"] as? Bool ?? false) {
            case .started: return (200, "started\n")
            case .signalled: return (200, "signalled (it was already running)\n")
            case .busy(let why): return (409, "busy: \(why)\n")
            case .unavailable(let why): return (409, "unavailable: \(why)\n")
            case .unknown: return (404, "no activity named \(action.run ?? "?")\n")
            }
        case ("GET", "/claude-buddy/extras"):
            let c = ExtrasCatalog.current
            let info: [String: Any] = [
                "activities": c.activities.values.sorted { $0.id < $1.id }.map { ["id": $0.id, "title": $0.title, "pack": $0.pack] },
                "accessories": c.accessories.keys.sorted(),
                "clips": c.clips.keys.sorted(),
                "packs": c.packs.map { ["id": $0.id, "name": $0.name, "file": $0.file?.path ?? "built-in"] },
                "bindings": c.bindings.map { ["keys": $0.keys ?? "", "sequence": $0.sequence?.joined(separator: " ") ?? "", "action": $0.action.label] },
                "triggers": c.triggers.map { Self.describe($0) },
                "problems": c.problems,
                "leader": leaderSetting + (leaderFailed ? " (in use by another app)" : ""),
                "running": stage.director.currentID ?? "none",
                "watchTexts": watchTexts ? "\(messages.access)" : "off",
            ]
            let data = (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return (200, String(decoding: data, as: UTF8.self) + "\n")
        case ("POST", "/claude-buddy/extras/reload"):
            reload()
            let problems = ExtrasCatalog.current.problems
            return (200, problems.isEmpty ? "reloaded, no problems\n" : "reloaded with problems:\n" + problems.joined(separator: "\n") + "\n")
        default:
            return nil
        }
    }

    // MARK: - Menu

    func menuItem() -> NSMenuItem {
        let catalog = ExtrasCatalog.current
        let menu = NSMenu()
        let director = stage.director

        if let running = director.currentID {
            let title = catalog.activities[running]?.title ?? "Activity"
            menu.addItem(BlockMenuItem("Stop \(title)") { [weak self] in self?.stage.director.cancel() })
            menu.addItem(.separator())
        }
        menu.addItem(info("Tricks & Activities"))
        let hints = keyHints()
        for a in catalog.activities.values.filter(\.inMenu).sorted(by: { $0.title < $1.title }) {
            let hint = hints[a.id].map { "   \($0)" } ?? ""
            let it = BlockMenuItem(a.title + hint) { [weak self] in
                self?.perform(ActionSpec(run: a.id), label: "menu", queueIfBusy: false)
            }
            if director.isActive || stage.nap.isActive || director.unavailableReason(a) != nil { it.action = nil }
            if let why = director.unavailableReason(a) { it.toolTip = why }
            menu.addItem(it)
        }
        menu.addItem(.separator())

        // Accessories, one per slot.
        let accMenu = NSMenu()
        let wornNow = Set(worn)
        accMenu.addItem(BlockMenuItem("None", on: wornNow.isEmpty) { [weak self] in
            self?.worn = []
            self?.applyWorn()
        })
        for slot in [AccessoryDef.Slot.head, .face, .held, .body, .back] {
            let list = catalog.accessories.values.filter { $0.slot == slot }.sorted { $0.title < $1.title }
            guard !list.isEmpty else { continue }
            accMenu.addItem(.separator())
            accMenu.addItem(info(slot.rawValue.capitalized))
            for acc in list {
                accMenu.addItem(BlockMenuItem(acc.title, on: wornNow.contains(acc.id)) { [weak self] in
                    guard let self else { return }
                    var w = self.worn.filter { catalog.accessories[$0]?.slot != slot }
                    if !wornNow.contains(acc.id) { w.append(acc.id) }
                    self.worn = w
                    self.applyWorn()
                })
            }
        }
        menu.addItem(submenu("Accessories", accMenu))

        // Leader key.
        let leaderMenu = NSMenu()
        for choice in Self.leaderChoices {
            let title = KeyCombo.parse(choice)?.title ?? "Off"
            leaderMenu.addItem(BlockMenuItem(title, on: leaderSetting == choice) { [weak self] in
                self?.leaderSetting = choice
                self?.registerLeader()
            })
        }
        if leaderFailed {
            leaderMenu.addItem(.separator())
            leaderMenu.addItem(info("That shortcut is taken by another app. Pick another."))
        }
        menu.addItem(submenu(leaderFailed ? "Leader Key ⚠︎" : "Leader Key", leaderMenu))

        // What's bound to what.
        let keysMenu = NSMenu()
        let leaderTitle = KeyCombo.parse(leaderSetting)?.title
        for b in catalog.bindings {
            let name = catalog.activities[b.action.run ?? ""]?.title ?? b.action.label
            if let k = b.keys, let combo = KeyCombo.parse(k) {
                keysMenu.addItem(info("\(combo.title)   \(name)" + (failedBindings.contains(combo.title) ? "  ⚠︎ taken" : "")))
            } else if let seq = b.sequence, let leaderTitle {
                keysMenu.addItem(info("\(leaderTitle) then \(seq.map(KeyNames.menuSymbol).joined(separator: " "))   \(name)"))
            }
        }
        if let leaderTitle { keysMenu.addItem(info("\(leaderTitle) then ⎋   Stop the current activity")) }
        if keysMenu.items.isEmpty { keysMenu.addItem(info("No shortcuts yet")) }
        menu.addItem(submenu(failedBindings.isEmpty ? "Shortcuts" : "Shortcuts ⚠︎", keysMenu))

        let trigMenu = NSMenu()
        trigMenu.addItem(BlockMenuItem("Automatic Treats (coffee, pizza, heists)", on: builtinTriggers) { [weak self] in
            guard let self else { return }
            self.builtinTriggers.toggle()
            self.reload()
        })
        let textsNeedAccess = watchTexts && messages.access == .needsFullDiskAccess
        trigMenu.addItem(BlockMenuItem(textsNeedAccess ? "Watch for New Texts ⚠︎ needs Full Disk Access" : "Watch for New Texts",
                                       on: watchTexts) { [weak self] in
            guard let self else { return }
            if textsNeedAccess { return self.explainFullDiskAccess() }
            self.setWatchTexts(!self.watchTexts)
        })
        trigMenu.addItem(.separator())
        for t in catalog.triggers where builtinTriggers || t.pack != "builtin" { trigMenu.addItem(info(Self.describe(t))) }
        if trigMenu.items.count == 2 { trigMenu.addItem(info("None. Add “triggers” to a pack.")) }
        menu.addItem(submenu("Schedules & Triggers", trigMenu))

        // Packs.
        let packMenu = NSMenu()
        let files = (try? FileManager.default.contentsOfDirectory(at: ExtrasCatalog.packsFolder, includingPropertiesForKeys: nil)) ?? []
        let userPacks = files.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> (String, String)? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let p = PackParser.parse(data: data, file: url, fallbackID: url.deletingPathExtension().lastPathComponent)
                return (p.id, p.name)
            }
        packMenu.addItem(info("Built-in (always on)"))
        let disabled = disabledPacks
        for (id, name) in userPacks {
            packMenu.addItem(BlockMenuItem(name, on: !disabled.contains(id)) { [weak self] in
                guard let self else { return }
                var d = self.disabledPacks
                if d.contains(id) { d.remove(id) } else { d.insert(id) }
                self.disabledPacks = d
                self.reload()
            })
        }
        packMenu.addItem(.separator())
        packMenu.addItem(BlockMenuItem("Open Packs Folder") { Self.openPacksFolder() })
        packMenu.addItem(BlockMenuItem("Reload Packs") { [weak self] in self?.reload() })
        let problems = catalog.problems
        if !problems.isEmpty {
            let probMenu = NSMenu()
            for p in problems.prefix(40) { probMenu.addItem(info(p)) }
            packMenu.addItem(submenu("Problems (\(problems.count))", probMenu))
        }
        menu.addItem(submenu(problems.isEmpty ? "Packs" : "Packs ⚠︎", packMenu))

        return submenu("Extras", menu)
    }

    /// "⌃⌥F" or "⌃⌥B ↑ ↑ ↓ ↓" for each activity with a shortcut.
    private func keyHints() -> [String: String] {
        var out: [String: String] = [:]
        let leaderTitle = KeyCombo.parse(leaderSetting)?.title
        for b in ExtrasCatalog.current.bindings {
            guard let id = b.action.run, out[id] == nil else { continue }
            if let k = b.keys, let c = KeyCombo.parse(k) { out[id] = c.title }
            else if let s = b.sequence, let leaderTitle { out[id] = "\(leaderTitle) " + s.map(KeyNames.menuSymbol).joined(separator: " ") }
        }
        return out
    }

    static func describe(_ t: TriggerDef) -> String {
        let what: String
        switch t.kind {
        case .at(let h, let m): what = String(format: "At %d:%02d", h, m)
        case .every(let s): what = s >= 3600 && s.truncatingRemainder(dividingBy: 3600) == 0 ? "Every \(Int(s / 3600))h" : "Every \(Int(s / 60))m"
        case .app(let e, let app):
            let verb = ["app-launch": "launches", "app-activate": "comes to the front", "app-quit": "quits", "app-open": "opens"][e] ?? e
            what = "When \(app) \(verb)"
        case .startup: what = "When Claude Buddy starts"
        case .wake: what = "When the Mac wakes"
        case .claude(let e, let tool): what = "On Claude \(e)" + (tool.map { " (\($0))" } ?? "")
        case .onWindow(let app): what = "When a buddy is on a \(app) window"
        case .newText: what = "When a new text arrives"
        }
        var extra: [String] = []
        if let days = t.days {
            let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            extra.append(days == [2, 3, 4, 5, 6] ? "weekdays" : days == [1, 7] ? "weekends" : days.sorted().map { names[$0] }.joined(separator: ","))
        }
        if let (s, e) = t.between { extra.append(String(format: "%d:%02d–%d:%02d", s / 60, s % 60, e / 60, e % 60)) }
        if t.chance < 1 { extra.append("\(Int(t.chance * 100))% chance") }
        if let c = t.condition { extra.append("if \(c)") }
        let name = t.action.run.flatMap { ExtrasCatalog.current.activities[$0]?.title } ?? t.action.label
        return what + (extra.isEmpty ? "" : " (\(extra.joined(separator: ", ")))") + " → " + name
    }

    static func openPacksFolder() {
        let folder = ExtrasCatalog.packsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? PacksReadme.text.write(to: readme, atomically: true, encoding: .utf8)
            try? PacksReadme.example.write(to: folder.appendingPathComponent("example-pack.json.sample"), atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(folder)
    }

    private func info(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }
}

/// A menu item that runs a closure.
final class BlockMenuItem: NSMenuItem {
    private let block: () -> Void

    init(_ title: String, on: Bool = false, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = on ? .on : .off
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { block() }
}

enum PacksReadme {
    static let text = """
    Claude Buddy packs
    ==================

    Put pack files (.json) in this folder, then choose Extras → Packs → Reload Packs
    in the menu bar (or run: curl -X POST http://127.0.0.1:47823/claude-buddy/extras/reload).

    A pack can add accessories (hats, glasses, things to hold), animation clips, activities
    (scripted routines with props, like the nap), keyboard shortcuts, leader-key sequences,
    and triggers (at a time of day, every N minutes, when an app opens, when Claude finishes).

    example-pack.json.sample shows every feature. Rename it to example-pack.json to try it.
    The full guide is docs/PACKS.md in the Claude Buddy repository.

    Problems in a pack show up under Extras → Packs → Problems.
    """

    static var example: String { ExamplePack.json }
}
