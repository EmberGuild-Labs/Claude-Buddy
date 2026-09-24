import AppKit

/// Borderless, transparent, click-through panel that never takes focus.
final class BuddyPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        // Above normal windows and the Dock, on every Space including full-screen apps.
        // (Set after isFloatingPanel, which resets the level to .floating.)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay window and keeps it sized to the bottom strip of the right screen,
/// with the floor on top of the Dock — or at the very bottom when a full-screen or
/// maximized app is in front.
final class OverlayController {
    let panel = BuddyPanel()
    let stage = BuddyStage(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
    private let settings: Settings
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var floorMode = "Above the Dock"

    init(settings: Settings, activity: ClaudeActivity) {
        self.settings = settings
        stage.pixel = settings.pixelScale
        stage.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        stage.activityProvider = { [unowned activity] in activity.current }
        stage.recentToolProvider = { [unowned activity] in activity.recentToolKind }

        updatePlacement()
        panel.contentView = stage
        setVisible(settings.visible)

        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in self?.updatePlacement() }
        timer?.tolerance = 0.25

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updatePlacement()
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stage.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updatePlacement()
        })
    }

    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        stage.isRunning = visible
    }

    func applySettings() {
        stage.pixel = settings.pixelScale
        updatePlacement()
    }

    private func targetScreen() -> NSScreen? {
        if settings.followMouse {
            let mouse = NSEvent.mouseLocation
            if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return s }
        }
        return NSScreen.screens.first
    }

    func updatePlacement() {
        guard let screen = targetScreen() else { return }
        let dockHeight = max(0, screen.visibleFrame.minY - screen.frame.minY)
        let covered = frontWindowCovers(screen)
        floorMode = covered ? "Screen bottom (full-screen/maximized app)" : "Above the Dock"

        // The window never moves while the buddy walks (moving windows is costly);
        // it only changes when the screen, Dock, or size setting does.
        let height = (dockHeight + CGFloat(BuddyArt.height) * settings.pixelScale + 110).rounded()
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        stage.groundY = covered ? 0 : dockHeight
    }

    private var lastCovered = false

    /// True when the frontmost app has a window filling the screen's usable area
    /// (full-screen or maximized/zoomed).
    private func frontWindowCovers(_ screen: NSScreen) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        // While our own alerts/menus are up, keep whatever we had.
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return lastCovered }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryTop = NSScreen.screens.first?.frame.maxY
        else { return false }

        let visible = screen.visibleFrame
        let tolerance: CGFloat = 30
        var covered = false
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            // CoreGraphics uses a top-left origin on the primary display.
            let rect = NSRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            guard rect.intersects(screen.frame) else { continue }
            if rect.width >= visible.width - tolerance,
               rect.height >= visible.height * 0.85,
               rect.minY <= visible.minY + tolerance {
                covered = true
                break
            }
        }
        lastCovered = covered
        return covered
    }
}
