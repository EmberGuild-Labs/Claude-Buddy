import AppKit
import ServiceManagement

/// The menu-bar item and everything in its menu.
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: Settings
    private let activity: ClaudeActivity
    private let overlay: OverlayController
    private let server: EventServer
    private var demoEnd: Timer?

    init(settings: Settings, activity: ClaudeActivity, overlay: OverlayController, server: EventServer) {
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

        menu.addItem(info("Claude: \(settings.quiet ? "Quiet mode" : activity.summary)"))
        let sessions = activity.liveSessionCount
        if sessions > 1 { menu.addItem(info("\(sessions) sessions")) }
        let hooksInstalled = HookInstaller.isInstalled()
        menu.addItem(info(hooksInstalled ? "Hooks: installed ✓" : "Hooks: not installed"))
        menu.addItem(info("Floor: \(overlay.floorMode)"))
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

        let screenMenu = NSMenu()
        screenMenu.addItem(item("Main Display", #selector(setScreenMain), on: !settings.followMouse))
        screenMenu.addItem(item("Display With Mouse", #selector(setScreenMouse), on: settings.followMouse))
        menu.addItem(submenu("Display", screenMenu))

        let demoMenu = NSMenu()
        for (i, title) in Self.demos.map(\.title).enumerated() {
            let it = item(title, #selector(demo(_:)))
            it.tag = i
            demoMenu.addItem(it)
        }
        menu.addItem(submenu("Try an Animation", demoMenu))
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

    @objc private func setScreenMain() {
        settings.followMouse = false
        overlay.updatePlacement()
    }

    @objc private func setScreenMouse() {
        settings.followMouse = true
        overlay.updatePlacement()
    }

    /// Demos feed fake hook events through the real pipeline.
    private static let demos: [(title: String, event: [String: Any]?)] = [
        ("Thinking", ["hook_event_name": "UserPromptSubmit"]),
        ("Running a Command", ["hook_event_name": "PreToolUse", "tool_name": "Bash"]),
        ("Editing Code", ["hook_event_name": "PreToolUse", "tool_name": "Edit"]),
        ("Searching Files", ["hook_event_name": "PreToolUse", "tool_name": "Grep"]),
        ("Browsing the Web", ["hook_event_name": "PreToolUse", "tool_name": "WebSearch"]),
        ("Needs Permission", ["hook_event_name": "Notification", "message": "Claude needs your permission to use Bash"]),
        ("Task Finished", ["hook_event_name": "Stop"]),
        ("Tool Failed", ["hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_response": ["is_error": true]]),
        ("Fall Asleep", nil),
    ]

    @objc private func demo(_ sender: NSMenuItem) {
        guard let event = Self.demos[sender.tag].event else {
            overlay.stage.forceSleep()
            return
        }
        var e = event
        e["session_id"] = "demo"
        let wasQuiet = activity.quiet
        activity.quiet = false
        activity.handle(e)
        activity.quiet = wasQuiet
        demoEnd?.invalidate()
        demoEnd = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.activity.handle(["hook_event_name": "SessionEnd", "session_id": "demo"])
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
