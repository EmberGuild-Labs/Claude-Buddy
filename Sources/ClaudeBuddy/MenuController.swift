import AppKit
import ServiceManagement

/// The menu-bar item and everything in its menu.
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: Settings
    private let activity: ClaudeActivity
    private let overlay: OverlayController
    private let server: EventServer
    private let school: SchoolStore
    private let schoolWindows: SchoolWindows
    private let hotKey: HotKey

    init(settings: Settings, activity: ClaudeActivity, overlay: OverlayController, server: EventServer,
         school: SchoolStore, schoolWindows: SchoolWindows, hotKey: HotKey) {
        self.hotKey = hotKey
        self.school = school
        self.schoolWindows = schoolWindows
        self.settings = settings
        self.activity = activity
        self.overlay = overlay
        self.server = server
        super.init()
        statusItem.button?.image = BuddyArt.menuBarIcon()
        statusItem.button?.toolTip = "Claude Buddy"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let today = item(overlay.stage.boardOpen ? "Put Away Today Board" : "Today…", #selector(openToday))
        let shortcut = settings.todayShortcut
        if shortcut != .off && !hotKey.failed {
            today.keyEquivalent = shortcut.menuKey
            today.keyEquivalentModifierMask = shortcut.menuModifiers
        }
        menu.addItem(today)
        let shortcutMenu = NSMenu()
        for choice in HotKey.Choice.allCases {
            let it = item(choice.title, #selector(setShortcut(_:)), on: choice == shortcut)
            it.representedObject = choice.rawValue
            shortcutMenu.addItem(it)
        }
        if hotKey.failed {
            shortcutMenu.addItem(.separator())
            shortcutMenu.addItem(info("\(shortcut.title) is taken by another app. Pick another."))
        }
        menu.addItem(submenu(hotKey.failed ? "Today Shortcut ⚠︎" : "Today Shortcut", shortcutMenu))
        if let summary = school.summary { menu.addItem(info(summary)) }
        menu.addItem(item(school.isConnected ? "Canvas Settings…" : "Connect Canvas…", #selector(openCanvasSettings)))
        menu.addItem(.separator())

        menu.addItem(info("Claude: \(settings.quiet ? "Quiet mode" : activity.summary)"))
        let sessions = activity.liveSessions.count
        if sessions > 1 { menu.addItem(info("\(sessions) sessions")) }
        let hooksInstalled = HookInstaller.isInstalled()
        menu.addItem(info(hooksInstalled ? "Hooks: installed ✓" : "Hooks: not installed"))
        menu.addItem(info("Floor: \(overlay.floorMode)"))
        if overlay.music.isPlaying { menu.addItem(info("♪ " + (overlay.music.track ?? "Music playing"))) }
        menu.addItem(info(server.status))
        menu.addItem(.separator())

        menu.addItem(item("Show Buddy", #selector(toggleVisible), on: settings.visible))
        menu.addItem(item("Quiet Mode (ignore Claude)", #selector(toggleQuiet), on: settings.quiet))

        let sizeMenu = NSMenu()
        for (i, name) in Settings.sizeNames.enumerated() {
            let it = item(name, #selector(setSize(_:)), on: settings.sizeIndex == i)
            it.tag = i
            sizeMenu.addItem(it)
        }
        menu.addItem(submenu("Size", sizeMenu))

        let hatMenu = NSMenu()
        let seasonal = item("Seasonal" + (overlay.seasonName.map { " (\($0))" } ?? " (none right now)"),
                            #selector(setHat(_:)), on: settings.mainHat == nil)
        seasonal.representedObject = nil
        hatMenu.addItem(seasonal)
        hatMenu.addItem(.separator())
        for hat in Hat.allCases {
            let it = item(hat.title, #selector(setHat(_:)), on: settings.mainHat == hat)
            it.representedObject = hat.rawValue
            hatMenu.addItem(it)
        }
        menu.addItem(submenu("Hat", hatMenu))
        menu.addItem(item("Extra Buddy per Session", #selector(toggleSessionBuddies), on: settings.sessionBuddies))
        menu.addItem(item("Cursor Reactions", #selector(toggleCursor), on: settings.cursorReactions))
        menu.addItem(item("Climb onto Windows", #selector(toggleClimb), on: settings.climbWindows))
        menu.addItem(item("Dance to Music", #selector(toggleDance), on: settings.danceToMusic))

        let screenMenu = NSMenu()
        screenMenu.addItem(item("Main Display", #selector(setScreenMain), on: !settings.followMouse))
        screenMenu.addItem(item("Display With Mouse", #selector(setScreenMouse), on: settings.followMouse))
        menu.addItem(submenu("Display", screenMenu))

        let demoMenu = NSMenu()
        for (i, title) in Self.demoTitles.enumerated() {
            let it = item(title, #selector(demo(_:)))
            it.tag = i
            demoMenu.addItem(it)
        }
        menu.addItem(submenu("Try an Animation", demoMenu))
        let extras = overlay.stage.extraBuddyCount
        let dismiss = item(extras > 0 ? "Dismiss Extra Buddies (\(extras))" : "Dismiss Extra Buddies", #selector(dismissExtras))
        if extras == 0 { dismiss.action = nil }
        menu.addItem(dismiss)
        menu.addItem(info("Tip: hold ⌥ and click to pet, drag to toss"))
        menu.addItem(.separator())

        if hooksInstalled {
            menu.addItem(item("Remove Claude Code Hooks…", #selector(removeHooks)))
        } else {
            menu.addItem(item("Install Claude Code Hooks…", #selector(installHooks)))
        }
        menu.addItem(item("Launch at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Claude Buddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Builders

    private func info(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    // MARK: - Actions

    @objc private func toggleVisible() {
        settings.visible.toggle()
        overlay.setVisible(settings.visible)
    }

    @objc private func toggleQuiet() {
        settings.quiet.toggle()
        activity.quiet = settings.quiet
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        settings.sizeIndex = sender.tag
        overlay.applySettings()
    }

    @objc private func setHat(_ sender: NSMenuItem) {
        settings.mainHat = (sender.representedObject as? String).flatMap(Hat.init(rawValue:))
        overlay.applySettings()
    }

    @objc private func toggleSessionBuddies() {
        settings.sessionBuddies.toggle()
        overlay.applySettings()
    }

    @objc private func toggleCursor() {
        settings.cursorReactions.toggle()
        overlay.applySettings()
    }

    @objc private func toggleClimb() {
        settings.climbWindows.toggle()
        overlay.applySettings()
        overlay.updatePlacement()
    }

    @objc private func toggleDance() {
        settings.danceToMusic.toggle()
        overlay.applySettings()
    }

    @objc private func setScreenMain() {
        settings.followMouse = false
        overlay.updatePlacement()
    }

    @objc private func setScreenMouse() {
        settings.followMouse = true
        overlay.updatePlacement()
    }

    /// Menu demos. Most make every buddy act out the same thing for a while.
    private static let demoTitles = [
        "Thinking", "Running a Command", "Editing Code", "Searching Files", "Browsing the Web",
        "Needs Permission", "Task Finished", "Tool Failed", "Fall Asleep",
        "Dance Party (pretend music)", "Game of Tag", "Conga Line", "Add a Session Buddy", "Show My Next Assignment",
    ]
    private var demoSessionCount = 0

    @objc private func demo(_ sender: NSMenuItem) {
        let stage = overlay.stage
        switch Self.demoTitles[sender.tag] {
        case "Thinking": stage.demo(.thinking)
        case "Running a Command": stage.demo(.tool(.terminal), tool: .terminal)
        case "Editing Code": stage.demo(.tool(.build), tool: .build)
        case "Searching Files": stage.demo(.tool(.search), tool: .search)
        case "Browsing the Web": stage.demo(.tool(.web), tool: .web)
        case "Needs Permission": stage.demo(.waiting, seconds: 8)
        case "Task Finished": stage.demoPulse(.finished)
        case "Tool Failed": stage.demoPulse(.failed)
        case "Fall Asleep": stage.forceSleep()
        case "Dance Party (pretend music)":
            overlay.music.simulate(seconds: 25)
            stage.startDanceParty(seconds: 12)
        case "Game of Tag": withPlaymates { $0.startTag() }
        case "Conga Line": withPlaymates { $0.startConga() }
        case "Show My Next Assignment":
            // Only ever real Canvas data: the next thing due, or the billboard if nothing is.
            if !school.isConnected {
                schoolWindows.showSettings()
            } else if let snapshot = school.snapshot, let next = ReminderPlanner.next(in: snapshot, now: Date()) {
                stage.showReminder(next)
            } else {
                school.refreshIfStale()
                stage.openBoard()
            }
        default: addDemoSession(thinking: true)
        }
    }

    /// A pretend Claude session (so a new buddy drops in) that ends on its own.
    private func addDemoSession(thinking: Bool, lasting seconds: TimeInterval = 30) {
        demoSessionCount += 1
        let sid = "demo-extra-\(demoSessionCount)"
        activity.handle(["hook_event_name": "SessionStart", "session_id": sid, "cwd": "/demo/side-project-\(demoSessionCount)"])
        if thinking { activity.handle(["hook_event_name": "UserPromptSubmit", "session_id": sid]) }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.activity.handle(["hook_event_name": "SessionEnd", "session_id": sid])
        }
    }

    @objc private func setShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = HotKey.Choice(rawValue: raw) else { return }
        settings.todayShortcut = choice
        if !hotKey.register(choice) {
            alert("Shortcut already in use", "Another app is using \(choice.title). Pick a different Today shortcut.", style: .warning)
        }
    }

    @objc private func openToday() {
        school.refreshIfStale()
        overlay.stage.toggleBoard()
    }
    @objc private func openCanvasSettings() { schoolWindows.showSettings() }

    @objc private func dismissExtras() {
        activity.endSessions { $0.hasPrefix("demo") }
        overlay.stage.dismissExtras()
    }

    /// Games need at least two idle buddies; bring in a couple of pretend sessions if needed.
    private func withPlaymates(_ start: @escaping (BuddyStage) -> Bool) {
        if start(overlay.stage) { return }
        for _ in 0..<2 { addDemoSession(thinking: false, lasting: 40) }
        // Let them drop in and land first.
        Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            _ = start(self.overlay.stage)
        }
    }


    @objc private func installHooks() {
        do {
            let backup = try HookInstaller.install(port: Settings.port)
            var text = "The buddy will now react to Claude Code. Sessions started from now on pick up the hooks — restart any that are already open."
            if let backup { text += "\n\nYour previous settings were backed up to:\n\(backup.path)" }
            alert("Hooks installed", text)
        } catch {
            alert("Couldn't install hooks", error.localizedDescription, style: .warning)
        }
    }

    @objc private func removeHooks() {
        do {
            try HookInstaller.uninstall()
            alert("Hooks removed", "Claude Code will no longer send events to the buddy. Your other settings were left as they were.")
        } catch {
            alert("Couldn't remove hooks", error.localizedDescription, style: .warning)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    alert("One more step", "Allow Claude Buddy in System Settings › General › Login Items.")
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            alert("Couldn't change Launch at Login", error.localizedDescription, style: .warning)
        }
    }

    private func alert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
