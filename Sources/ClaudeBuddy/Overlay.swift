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
    private var pollTick = 0
    let music = MusicWatcher()
    private var lookTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var floorMode = "Above the Dock"

    init(settings: Settings, activity: ClaudeActivity) {
        self.settings = settings
        stage.pixel = settings.pixelScale
        stage.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        stage.sessionsProvider = { [unowned activity] in activity.liveSessions }
        stage.aggregateProvider = { [unowned activity] in activity.aggregate }
        applyLook()

        updatePlacement()
        panel.contentView = stage
        setVisible(settings.visible)

        // Window positions refresh ~1×/s normally, and 20×/s while a buddy stands on or
        // jumps between windows, so riding a dragged window stays smooth.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Nothing to do while the display sleeps (the buddies pause too).
            guard let self, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
            self.pollTick += 1
            self.stage.musicPlaying = self.music.isPlaying
            self.stage.musicTrack = self.music.track
            self.stage.musicBPM = self.music.bpm
            if self.stage.needsFastWindowUpdates || self.pollTick % 16 == 0 { self.updatePlacement() }
        }
        // Seasons change at midnight; checking hourly is plenty.
        lookTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.applyLook() }
        timer?.tolerance = 0.01

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
        applyLook()
        updatePlacement()
    }

    /// Hat, seasonal extras, and behavior toggles.
    private func applyLook() {
        let season = Season.look(installed: settings.installedAt)
        stage.mainHat = settings.mainHat ?? season?.hat ?? .none
        stage.seasonalConfetti = season?.confetti
        stage.snowing = season?.snow ?? false
        stage.sessionBuddies = settings.sessionBuddies
        stage.windowsEnabled = settings.climbWindows
        stage.danceToMusic = settings.danceToMusic
        stage.cursorReactions = settings.cursorReactions
    }

    /// Name of the current season's look, for the menu.
    var seasonName: String? { Season.look(installed: settings.installedAt).map { "\($0.name): \($0.hat.title)" } }

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
        let windows = scanWindows(on: screen)
        floorMode = windows.frontCovers ? "Screen bottom (full-screen/maximized app)" : "Above the Dock"

        // The overlay covers the whole screen (so buddies can climb windows) but passes
        // every click through. It never moves while buddies walk — moving windows is costly.
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
        stage.groundY = windows.frontCovers ? 0 : dockHeight
        stage.windowPlatforms = settings.climbWindows ? windows.platforms : [:]
    }

    private var lastCovered = false
    /// pid → bundle ID, so window scans don't look apps up every time.
    private var bundleIDs: [pid_t: String] = [:]

    private func bundleID(_ pid: pid_t) -> String? {
        if let b = bundleIDs[pid] { return b }
        guard let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        if bundleIDs.count > 200 { bundleIDs.removeAll() }
        bundleIDs[pid] = b
        return b
    }

    private struct WindowScan {
        var frontCovers = false
        var platforms: [Int: WindowPlatform] = [:]
    }

    /// One pass over the on-screen windows (front to back) that finds:
    /// - whether the frontmost app fills the screen (full-screen or maximized), and
    /// - every normal window's top edge, minus the parts hidden behind windows in front of it.
    /// Reading window bounds needs no special permission.
    private func scanWindows(on screen: NSScreen) -> WindowScan {
        var scan = WindowScan()
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryTop = NSScreen.screens.first?.frame.maxY
        else { return scan }

        let visible = screen.visibleFrame
        let buddyRoom = CGFloat(BuddyArt.height) * settings.pixelScale * 0.6
        var inFront: [NSRect] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ourPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            // CoreGraphics uses a top-left origin on the primary display.
            let rect = NSRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            guard rect.intersects(screen.frame), rect.width >= 60, rect.height >= 40 else { continue }
            defer { inFront.append(rect) }

            if pid == frontPID, rect.width >= visible.width - 30, rect.height >= visible.height * 0.85,
               rect.minY <= visible.minY + 30 {
                scan.frontCovers = true
            }

            // A ledge needs headroom below the menu bar and enough width to stand on.
            let top = rect.maxY
            guard rect.width >= 150, top + buddyRoom <= visible.maxY, top > visible.minY + 40 else { continue }
            var segments = [rect.minX...rect.maxX]
            for front in inFront where front.minY <= top + 2 && front.maxY >= top - 2 {
                segments = segments.flatMap { seg -> [ClosedRange<CGFloat>] in
                    var parts: [ClosedRange<CGFloat>] = []
                    if front.minX > seg.lowerBound { parts.append(seg.lowerBound...min(seg.upperBound, front.minX)) }
                    if front.maxX < seg.upperBound { parts.append(max(seg.lowerBound, front.maxX)...seg.upperBound) }
                    return front.maxX <= seg.lowerBound || front.minX >= seg.upperBound ? [seg] : parts
                }
            }
            // Stage coordinates are relative to the screen's bottom-left corner.
            let ox = screen.frame.minX, oy = screen.frame.minY
            let local = segments.filter { $0.upperBound - $0.lowerBound >= 40 }
                .map { ($0.lowerBound - ox)...($0.upperBound - ox) }
            if !local.isEmpty {
                scan.platforms[number] = WindowPlatform(origin: CGPoint(x: rect.minX - ox, y: top - oy), segments: local, owner: bundleID(pid))
            }
        }
        if frontPID == ourPID { scan.frontCovers = lastCovered }
        lastCovered = scan.frontCovers
        return scan
    }
}
