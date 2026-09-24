import AppKit
import QuartzCore

/// The strip along the bottom of the screen where the buddies live.
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
         "width": Int(bounds.width), "buddies": buddies.map(\.status)]
    }

    // MARK: - External input

    /// Routes a Claude Code moment to the buddy acting out that session.
    func pulse(_ p: Pulse, session: String) {
        syncSessions()
        let target = buddies.first { $0.sessionID == session } ?? main
        target?.pulse(p)
    }

    func forceSleep() {
        buddies.forEach { $0.forceSleep() }
    }

    // MARK: - Frame loop

    @objc private func step(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 30 : min(link.timestamp - lastTimestamp, 0.1)
        lastTimestamp = link.timestamp
        frames += 1

        syncClock += dt
        if syncClock > 0.25 {
            syncClock = 0
            syncSessions()
        }
        updateCursor(dt)
        updateInteractivity()

        for b in buddies { b.tick(dt) }
        greetings()
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

    /// Two buddies walking into each other stop and wave.
    private func greetings() {
        guard buddies.count > 1 else { return }
        for i in 0..<buddies.count {
            for j in (i + 1)..<buddies.count {
                let a = buddies[i], b = buddies[j]
                guard a.isWalkingWander, b.isWalkingWander, a.onGround, b.onGround else { continue }
                let dx = b.pos.x - a.pos.x
                let approaching = a.walkDirection * dx > 0 && b.walkDirection * dx < 0
                if approaching && abs(dx) < a.halfWidth * 2.2 {
                    a.greet()
                    b.greet()
                }
            }
        }
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
