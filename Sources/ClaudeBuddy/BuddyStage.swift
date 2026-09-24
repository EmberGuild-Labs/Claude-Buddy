import AppKit
import QuartzCore

/// A window's top edge, as ledges a buddy can stand on (stage coordinates).
struct WindowPlatform {
    /// (left edge, top edge) of the window — buddies standing on it ride along when it moves.
    let origin: CGPoint
    /// The parts of the top edge not covered by windows in front of it.
    let segments: [ClosedRange<CGFloat>]
}

/// The whole screen, where the buddies live: on the floor (Dock or screen bottom) and on
/// top of app windows.
///
/// Drawn with plain Core Animation layers, composited by the WindowServer, so the app itself
/// stays nearly idle. One display link drives every buddy. The main buddy is always here;
/// each additional Claude Code session gets an extra buddy with its own hat.
final class BuddyStage: NSView {
    var pixel: CGFloat = 4 {
        didSet { if oldValue != pixel { buddies.forEach { $0.applyScale() } } }
    }
    /// Height of the floor within the window (top of the Dock, or 0 for the screen's bottom edge).
    var groundY: CGFloat = 0
    var reduceMotion = false
    var cursorReactions = true
    var sessionBuddies = true
    /// The main buddy's hat (chosen, seasonal, or none).
    var mainHat: Hat = .none { didSet { main?.hat = mainHat } }
    var seasonalConfetti: [CGColor]?
    var snowing = false
    /// Let buddies hop onto app windows.
    var windowsEnabled = true
    var windowPlatforms: [Int: WindowPlatform] = [:]
    var danceToMusic = true
    var musicPlaying = false
    var musicTrack: String?
    var musicBPM: Double = 112
    /// Shared beat counter, so everyone dances (and congas) in sync.
    private(set) var beat: Double = 0
    var sessionsProvider: () -> [SessionInfo] = { [] }
    var aggregateProvider: () -> SessionInfo? = { nil }

    var isRunning: Bool {
        get { !(link?.isPaused ?? true) }
        set { link?.isPaused = !newValue }
    }

    static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(),
        "hidden": NSNull(), "opacity": NSNull(), "sublayers": NSNull(), "frame": NSNull(),
        "string": NSNull(), "contentsScale": NSNull(),
    ]

    private static let maxExtraBuddies = 6

    private(set) var buddies: [Buddy] = []
    private var main: Buddy? { buddies.first(where: \.isMain) }
    var buddyCount: Int { buddies.count }

    // Shared cursor state, read by every buddy.
    private(set) var mouse: CGPoint?
    /// Where the cursor was last frame, so a fast swipe between frames still counts.
    private(set) var previousMouse: CGPoint?
    private(set) var mouseSpeed: CGFloat = 0
    private(set) var optionHeld = false
    private(set) weak var nearestToCursor: Buddy?

    private var link: CADisplayLink?
    private var currentFPS = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var syncClock: TimeInterval = 0
    private var snowClock: TimeInterval = 0
    private var grabbed: Buddy?
    private var interactive = false

    // Games
    private(set) weak var tagIt: Buddy?
    private(set) weak var congaLeader: Buddy?
    private var gameClock: TimeInterval = 0
    private var gameCooldown: TimeInterval = .random(in: 60...120)
    /// Simulation time, advanced by `advance(_:)`.
    private var simTime: TimeInterval = 0
    private var recentFinishes: [(session: String, at: TimeInterval)] = []
    private var pendingConga: TimeInterval?
    private var congaRetries = 0

    /// True while someone stands on (or is jumping around) windows, so window positions
    /// should be refreshed quickly for smooth riding.
    var needsFastWindowUpdates: Bool { buddies.contains { $0.isOnWindow || !$0.onGround } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        setFPS(30)
        add(Buddy(stage: self, isMain: true, hat: mainHat, x: bounds.width * .random(in: 0.3...0.7), dropIn: false))
    }

    private func add(_ buddy: Buddy) {
        buddies.append(buddy)
        layer?.addSublayer(buddy.root)
    }

    private func setFPS(_ fps: Int) {
        guard fps != currentFPS, let link else { return }
        currentFPS = fps
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps), maximum: Float(fps), preferred: Float(fps))
    }

    private(set) var frames = 0

    var status: [String: Any] {
        ["frames": frames, "fps": currentFPS, "running": isRunning, "groundY": Int(groundY),
         "width": Int(bounds.width), "height": Int(bounds.height), "buddies": buddies.map(\.status),
         "windowLedges": windowPlatforms.count, "music": musicPlaying ? (musicTrack ?? "playing") : "off",
         "game": tagIt != nil ? "tag" : (congaLeader != nil ? "conga" : "none"),
         "tagIt": tagIt.flatMap { b in buddies.firstIndex { $0 === b } } ?? -1]
    }

    // MARK: - External input

    /// Routes a Claude Code moment to the buddy acting out that session.
    func pulse(_ p: Pulse, session: String) {
        syncSessions()
        let target = buddies.first { $0.sessionID == session } ?? main
        target?.pulse(p)
        if p == .finished { noteFinish(session) }
    }

    func forceSleep() {
        buddies.forEach { $0.forceSleep() }
    }

    // MARK: - Frame loop

    @objc private func step(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 30 : min(link.timestamp - lastTimestamp, 0.1)
        lastTimestamp = link.timestamp
        advance(dt)
    }

    /// One simulation step. The display link calls this; so does `--self-test`.
    func advance(_ dt: TimeInterval) {
        frames += 1
        simTime += dt

        syncClock += dt
        if syncClock > 0.25 {
            syncClock = 0
            syncSessions()
        }
        updateCursor(dt)
        updateInteractivity()

        beat += dt * (musicPlaying ? musicBPM : 112) / 60
        // Carriers move before their riders, so riders stay glued to their heads.
        for b in buddies.sorted(by: { $0.stackDepth < $1.stackDepth }) { b.tick(dt) }
        greetings()
        tickGames(dt)
        tickSnow(dt)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for b in buddies where b.isGone {
            b.root.removeFromSuperlayer()
        }
        buddies.removeAll(where: \.isGone)
        for b in buddies { b.render() }
        CATransaction.commit()

        // Effects (hearts, confetti, snow) are Core Animation animations that run on their
        // own, so only the buddies themselves set the frame rate.
        setFPS(buddies.map(\.desiredFPS).max() ?? 10)
    }

    /// Keeps one buddy per live session: the main buddy takes a session when it's free,
    /// extras drop in for the rest and walk off when their session ends.
    private func syncSessions() {
        guard let main else { return }
        guard sessionBuddies else {
            main.sessionID = nil
            main.info = aggregateProvider()
            for b in buddies where !b.isMain { b.beginLeaving() }
            return
        }
        let sessions = sessionsProvider()
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        for b in buddies {
            if let id = b.sessionID, byID[id] == nil {
                if b.isMain { b.sessionID = nil; b.info = nil } else { b.beginLeaving() }
            }
        }
        let assigned = Set(buddies.compactMap(\.sessionID))
        for s in sessions where !assigned.contains(s.id) {
            if main.sessionID == nil {
                main.sessionID = s.id
            } else if buddies.filter({ !$0.isMain && !$0.isLeaving }).count < Self.maxExtraBuddies {
                let usedHats = Set(buddies.map(\.hat))
                let hat = Hat.sessionPool.first { !usedHats.contains($0) } ?? Hat.sessionPool.randomElement()!
                let x = min(max(main.pos.x + .random(in: 60...160) * (Bool.random() ? 1 : -1), 40), bounds.width - 40)
                let extra = Buddy(stage: self, isMain: false, hat: hat, x: x, dropIn: true)
                extra.sessionID = s.id
                add(extra)
            }
        }
        for b in buddies {
            if let id = b.sessionID { b.info = byID[id] }
        }
    }

    /// Two buddies walking into each other on the same surface stop and high-five.
    private func greetings() {
        guard buddies.count > 1 else { return }
        for i in 0..<buddies.count {
            for j in (i + 1)..<buddies.count {
                let a = buddies[i], b = buddies[j]
                guard a.isWalkingWander, b.isWalkingWander, a.onGround, b.onGround, a.platform == b.platform else { continue }
                let dx = b.pos.x - a.pos.x
                let approaching = a.facing * dx > 0 && b.facing * dx < 0
                if approaching && abs(dx) < a.halfWidth * 2.2 {
                    a.highFive(with: b, leads: true)
                    b.highFive(with: a, leads: false)
                }
            }
        }
    }

    // MARK: - Games

    private func tickGames(_ dt: TimeInterval) {
        // Tag: runs until time's up or players drop out (e.g. Claude gets busy).
        if tagIt != nil {
            gameClock += dt
            let players = buddies.filter(\.isInTag)
            if gameClock > 14 || players.count < 2 || tagIt?.isInTag != true {
                players.forEach { $0.endGame() }
                tagIt = nil
            }
        }
        if congaLeader != nil {
            gameClock += dt
            let dancers = buddies.filter(\.isInConga)
            if gameClock > 10 || dancers.count < 2 || congaLeader?.isInConga != true {
                dancers.forEach { $0.endGame() }
                congaLeader = nil
            }
        }
        if let at = pendingConga, simTime >= at {
            // Buddies may still be mid-celebration; keep trying for a few seconds.
            if startConga() || congaRetries >= 6 {
                pendingConga = nil
            } else {
                congaRetries += 1
                pendingConga = simTime + 0.8
            }
        }
        // Now and then, idle buddies start a game of tag on their own.
        gameCooldown -= dt
        if gameCooldown <= 0 {
            gameCooldown = .random(in: 70...150)
            if Double.random(in: 0...1) < 0.6 { startTag() }
        }
    }

    @discardableResult
    func startTag() -> Bool {
        guard tagIt == nil, congaLeader == nil else { return false }
        let players = buddies.filter(\.canJoinGame)
        guard players.count >= 2 else { return false }
        gameClock = 0
        tagIt = players.randomElement()
        players.forEach { $0.joinTag() }
        return true
    }

    func tagged(_ buddy: Buddy) { tagIt = buddy }

    @discardableResult
    func startConga() -> Bool {
        guard tagIt == nil, congaLeader == nil else { return false }
        let players = buddies.filter(\.canJoinGame)
        guard players.count >= 2 else { return false }
        let leader = players.first(where: \.isMain) ?? players[0]
        let followers = players.filter { $0 !== leader }.sorted { abs($0.pos.x - leader.pos.x) < abs($1.pos.x - leader.pos.x) }
        gameClock = 0
        congaLeader = leader
        leader.joinConga(index: 0)
        for (i, b) in followers.enumerated() { b.joinConga(index: i + 1) }
        return true
    }

    /// When two or more sessions finish close together, everyone does a conga line.
    private func noteFinish(_ session: String) {
        let now = simTime
        recentFinishes.removeAll { now - $0.at > 15 }
        recentFinishes.append((session, now))
        if Set(recentFinishes.map(\.session)).count >= 2 && buddies.count >= 2 {
            recentFinishes.removeAll()
            congaRetries = 0
            pendingConga = now + 3.2  // After the celebrations.
        }
    }

    /// Window ledges within reach that are wide enough to stand on.
    func ledges(near x: CGFloat, reach: CGFloat, minWidth: CGFloat, excluding: Int) -> [(range: ClosedRange<CGFloat>, y: CGFloat)] {
        guard windowsEnabled else { return [] }
        var result: [(ClosedRange<CGFloat>, CGFloat)] = []
        for (id, w) in windowPlatforms where id != excluding {
            for seg in w.segments where seg.upperBound - seg.lowerBound >= minWidth {
                let nearest = min(max(x, seg.lowerBound), seg.upperBound)
                if abs(nearest - x) <= reach { result.append((seg, w.origin.y)) }
            }
        }
        return result
    }

    // MARK: - Cursor

    private func updateCursor(_ dt: TimeInterval) {
        optionHeld = NSEvent.modifierFlags.contains(.option)
        guard let window else { mouse = nil; return }
        let p = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if let old = mouse, dt > 0 {
            let instant = hypot(p.x - old.x, p.y - old.y) / dt
            mouseSpeed = mouseSpeed * 0.6 + instant * 0.4
        }
        previousMouse = mouse
        mouse = p
        nearestToCursor = buddies.filter { !$0.isLeaving }.min { abs($0.pos.x - p.x) < abs($1.pos.x - p.x) }
    }

    /// The window ignores the mouse unless ⌥ is held over a buddy (or a drag is underway),
    /// so it never gets in the way of the app you're using.
    private func updateInteractivity() {
        guard let window, let m = mouse else { return }
        let hit = optionHeld && buddies.contains { !$0.isLeaving && $0.hitRect.contains(m) }
        let want = grabbed != nil || hit
        if window.ignoresMouseEvents == want { window.ignoresMouseEvents = !want }
        if want {
            (grabbed != nil ? NSCursor.closedHand : NSCursor.openHand).set()
        } else if interactive {
            NSCursor.arrow.set()
        }
        interactive = want
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Topmost (last added) buddy wins.
        guard let b = buddies.last(where: { !$0.isLeaving && $0.hitRect.contains(p) }) else { return }
        grabbed = b
        b.grab(at: p, time: event.timestamp)
    }

    override func mouseDragged(with event: NSEvent) {
        grabbed?.drag(to: convert(event.locationInWindow, from: nil), time: event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        grabbed?.release()
        grabbed = nil
    }

    // MARK: - Effects (fire-and-forget Core Animation, run by the render server)

    private func play(_ layer: CALayer, _ animations: [CAAnimation], duration: TimeInterval) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.zPosition = 5
        self.layer?.addSublayer(layer)
        layer.add(group, forKey: "fx")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            layer.removeFromSuperlayer()
        }
    }

    /// A pixel-art sprite that drifts by (dx, dy) and fades out.
    func floatingEffect(_ image: CGImage, at point: CGPoint, dx: CGFloat, dy: CGFloat, duration: TimeInterval,
                        scale: CGFloat = 1, grow: (CGFloat, CGFloat)? = nil) {
        let l = CALayer()
        l.actions = Self.noActions
        l.contents = image
        l.magnificationFilter = .nearest
        l.bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width) * pixel * scale, height: CGFloat(image.height) * pixel * scale)
        l.position = point
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = point
        move.toValue = CGPoint(x: point.x + dx, y: point.y + dy)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.6, 1]
        var anims: [CAAnimation] = [move, fade]
        if let grow {
            let s = CABasicAnimation(keyPath: "transform.scale")
            s.fromValue = grow.0
            s.toValue = grow.1
            anims.append(s)
        }
        play(l, anims, duration: duration)
    }

    func confetti(at origin: CGPoint, colors: [CGColor]?) {
        let s = pixel / 4
        let palette = colors ?? BuddyArt.confettiColors
        for _ in 0..<(reduceMotion ? 10 : 24) {
            let piece = CALayer()
            piece.actions = Self.noActions
            piece.backgroundColor = palette.randomElement()!
            piece.bounds = CGRect(x: 0, y: 0, width: pixel, height: pixel)
            piece.position = origin
            let vx = CGFloat.random(in: -150...150) * s
            let up = CGFloat.random(in: 50...130) * s
            let path = CAKeyframeAnimation(keyPath: "position")
            path.values = [origin,
                           CGPoint(x: origin.x + vx * 0.35, y: origin.y + up),
                           CGPoint(x: origin.x + vx * 0.85, y: origin.y - 8 * pixel)]
            path.keyTimes = [0, 0.28, 1]
            path.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.toValue = CGFloat.random(in: -6...6)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.28, 1]
            play(piece, [path, spin, fade], duration: 1.25)
        }
    }

    /// December: a few snowflakes drift down around the main buddy.
    private func tickSnow(_ dt: TimeInterval) {
        guard snowing, !reduceMotion, let main else { return }
        snowClock += dt
        guard snowClock > 0.7 else { return }
        snowClock = 0
        let start = CGPoint(x: main.pos.x + .random(in: -60...60) * pixel / 4, y: main.pos.y + 26 * pixel)
        floatingEffect(BuddyArt.snowflake, at: start, dx: .random(in: -12...12), dy: -(start.y - groundY), duration: 3.2, scale: 0.6)
    }
}
