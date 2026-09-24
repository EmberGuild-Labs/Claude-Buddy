import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let activity = ClaudeActivity()
    private let server = EventServer(port: Settings.port)
    private var overlay: OverlayController?
    private var menu: MenuController?
    private var school: SchoolStore?
    private var schoolWindows: SchoolWindows?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        activity.quiet = settings.quiet
        let overlay = OverlayController(settings: settings, activity: activity)
        activity.onPulse = { [weak overlay] p, session in overlay?.stage.pulse(p, session: session) }
        server.onEvent = { [weak self] event in self?.activity.handle(event) }
        server.statusProvider = { [weak overlay] in overlay?.stage.status ?? [:] }
        do { try server.start() } catch { NSLog("Claude Buddy: server failed to start: \(error)") }
        let school = SchoolStore()
        let windows = SchoolWindows(store: school)
        school.onReminder = { [weak overlay] r in overlay?.stage.showReminder(r) }
        overlay.stage.onOpenReminder = { [weak overlay] r in
            if let url = r.url { NSWorkspace.shared.open(url) } else { overlay?.stage.openBoard() }
        }
        overlay.stage.boardDataProvider = {
            Billboard.Data(connected: school.isConnected, loading: school.isRefreshing, error: school.lastError, snapshot: school.snapshot)
        }
        overlay.stage.onBoardAction = { action in
            switch action {
            case .open(let url): NSWorkspace.shared.open(url)
            case .connect: windows.showSettings()
            case .refresh: school.refresh()
            default: break
            }
        }
        self.school = school
        schoolWindows = windows
        menu = MenuController(settings: settings, activity: activity, overlay: overlay, server: server,
                              school: school, schoolWindows: windows)
        self.overlay = overlay
    }
}

// Command-line helpers (used by the build script and for scripting):
//   --render-icon <dir.iconset>   write app icon PNGs
//   --install-hooks [settings]    add hooks to ~/.claude/settings.json (or the given file)
//   --uninstall-hooks [settings]  remove them
let args = CommandLine.arguments
func argument(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if let file = argument(after: "--render-board") {
    let tabName = argument(after: file) ?? "due"
    let tab: Billboard.Tab = tabName == "missing" ? .missing : tabName == "grades" ? .grades : .due
    BoardPreview.render(to: URL(fileURLWithPath: file), tab: tab)
    exit(0)
}
if args.contains("--self-test") {
    exit(SelfTest.run())
}
if let file = argument(after: "--render-sprites") {
    SpriteSheet.write(to: URL(fileURLWithPath: file))
    exit(0)
}
if let dir = argument(after: "--render-icon") {
    IconRenderer.writeIconset(to: URL(fileURLWithPath: dir))
    exit(0)
}
if args.contains("--install-hooks") || args.contains("--uninstall-hooks") {
    let install = args.contains("--install-hooks")
    let url = argument(after: install ? "--install-hooks" : "--uninstall-hooks").map { URL(fileURLWithPath: $0) }
        ?? HookInstaller.defaultSettingsURL
    do {
        if install { try HookInstaller.install(port: Settings.port, at: url) } else { try HookInstaller.uninstall(at: url) }
        print("\(install ? "Installed" : "Removed") Claude Buddy hooks in \(url.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
