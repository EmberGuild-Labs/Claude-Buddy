import AppKit
import QuartzCore

/// The buddy: a small state machine picking behaviors, a bit of physics, and pose rendering.
///
/// Drawn with plain Core Animation layers, composited by the WindowServer, so the app itself
/// stays nearly idle. The view spans the bottom strip of the screen (origin bottom-left);
/// `pos` is the point between the buddy's feet.
final class BuddyStage: NSView {
    var pixel: CGFloat = 4 { didSet { if oldValue != pixel { applyScale() } } }
    /// Height of the floor within the window (top of the Dock, or 0 for the screen's bottom edge).
    var groundY: CGFloat = 0
    var reduceMotion = false
    var activityProvider: () -> Activity = { .idle }
    var recentToolProvider: () -> ToolKind? = { nil }

    var isRunning: Bool {
        get { !(link?.isPaused ?? true) }
        set { link?.isPaused = !newValue }
    }

    private enum Mode: Equatable {
        case stand, sit, walk, sleep, wake, work(ToolKind), alert, hello, celebrate, pet, dizzy, held, tossed

        /// Reactions play to the end instead of being interrupted by Claude activity.
        var isReaction: Bool {
            switch self {
            case .wake, .hello, .celebrate, .pet, .dizzy, .held, .tossed: true
            default: false
            }
        }
    }

    private let sleepAfter: TimeInterval = 5 * 60

    private let root = CALayer()
    private let sprite = CALayer()
    private let bubble = CALayer()
    private let orbit = CALayer()
    private var link: CADisplayLink?
    private var currentImage: CGImage?
    private var currentFPS = 0

    /// Speeds and distances are tuned for pixel = 4 and scale with size.
    private var s: CGFloat { pixel / 4 }
    private var halfWidth: CGFloat { 9 * pixel }
    private var gravity: CGFloat { 2200 * s }

    private var mode: Mode = .stand
    private var modeTime: TimeInterval = 0
    private var modeDuration: TimeInterval = 2
    private var targetX: CGFloat = 0
    private var walkSpeed: CGFloat = 40
    private var paceCenter: CGFloat?
    private var lastActivity: Activity = .idle
    private var lastWorkWasAct = false
    private var lastStimulus = Date()

    private var pos = CGPoint(x: -1, y: 0)
    private var vel = CGVector.zero
    private var onGround = true
    private var facing: CGFloat = 1
    private var squashTimer: TimeInterval = 0
    private var blinkTimer: TimeInterval = 3
    private var blinkLeft: TimeInterval = 0
    private var lookDir = 0
    private var lookTimer: TimeInterval = 1.5
    private var clock: TimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var effectClock: TimeInterval = 0
    private var jumps = 0
    private var lastHammerFrame = 0
    private var flipTime: TimeInterval?
    private var liveEffects = 0

    private var dragging = false
    private var dragMoved = false
    private var dragStart = CGPoint.zero
    private var grabOffset = CGPoint.zero
    private var lastDragPoint = CGPoint.zero
    private var lastDragTime: TimeInterval = 0
    private var dragVel = CGVector.zero
    private var interactive = false

    // MARK: - Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
        for l in [root, sprite, bubble, orbit] { l.actions = Self.noActions }
        layer?.addSublayer(root)
        root.addSublayer(sprite)
        root.addSublayer(orbit)
        root.addSublayer(bubble)
        sprite.anchorPoint = CGPoint(x: 0.5, y: BuddyArt.anchorY)
        sprite.magnificationFilter = .nearest
        bubble.anchorPoint = CGPoint(x: 0.5, y: 0)
        bubble.magnificationFilter = .nearest
        bubble.zPosition = 2
        orbit.zPosition = 3
        applyScale()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(),
        "hidden": NSNull(), "opacity": NSNull(), "sublayers": NSNull(), "frame": NSNull(),
    ]

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        setFPS(30)
        pos = CGPoint(x: bounds.width * .random(in: 0.3...0.7), y: groundY)
        enter(.hello, duration: 1.6)
    }

    private func setFPS(_ fps: Int) {
        guard fps != currentFPS, let link else { return }
        currentFPS = fps
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps), maximum: Float(fps), preferred: Float(fps))
    }

    private func applyScale() {
        sprite.bounds = CGRect(x: 0, y: 0, width: CGFloat(BuddyArt.width) * pixel, height: CGFloat(BuddyArt.height) * pixel)
        sprite.position = CGPoint(x: 0, y: BuddyArt.anchorY * sprite.bounds.height)
        orbit.position = CGPoint(x: 0, y: 11 * pixel)
        bubble.contents = nil
    }

    // MARK: - External input

    func pulse(_ p: Pulse) {
        lastStimulus = Date()
        guard mode != .held, mode != .tossed else { return }
        switch p {
        case .finished:
            enter(.celebrate, duration: reduceMotion ? 1.4 : 2.8)
        case .failed:
            if mode != .celebrate { enter(.dizzy, duration: 1.8) }
        case .started:
            if mode == .sleep { enter(.wake, duration: 1) } else if !mode.isReaction { enter(.hello, duration: 1.6) }
        case .nudge:
            if mode == .sleep { enter(.wake, duration: 1) } else if !mode.isReaction { enter(.hello, duration: 2.4) }
        }
    }

    func forceSleep() {
        lastStimulus = .distantPast
        enter(.sleep, duration: .infinity)
    }

    private func pet() {
        lastStimulus = Date()
        enter(.pet, duration: 1.6)
    }

    // MARK: - Frame loop

    @objc private func step(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 30 : min(link.timestamp - lastTimestamp, 0.1)
        lastTimestamp = link.timestamp
        clock += dt
        if pos.x < 0 { pos.x = bounds.width / 2 }

        updateInteractivity()
        let activity = activityProvider()
        if activity != lastActivity {
            activityChanged(from: lastActivity, to: activity)
            lastActivity = activity
        }
        modeTime += dt
        tickTimers(dt)
        tickMode(dt)
        tickPhysics(dt)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        render(activity)
        CATransaction.commit()

        switch mode {
        case .sleep: setFPS(10)
        case .stand, .sit: setFPS(liveEffects == 0 && onGround ? 15 : 30)
        default: setFPS(30)
        }
    }

    private func activityChanged(from old: Activity, to new: Activity) {
        if new != .idle { lastStimulus = Date() }
        if old == .idle && new != .idle { paceCenter = pos.x }
        guard !mode.isReaction else { return }
        if mode == .sleep {
            if new != .idle { enter(.wake, duration: 1) }
            return
        }
        // Tool → thinking → tool flips happen many times a second; let the current bit
        // finish. Only starting/stopping work and permission prompts interrupt.
        let busyFlip = (old == .idle) != (new == .idle)
        if new == .waiting || old == .waiting || busyFlip { chooseNext() }
    }

    // MARK: - Behavior

    private func chooseNext() {
        let activity = activityProvider()
        switch activity {
        case .waiting:
            enter(.alert, duration: .infinity)
        case .thinking, .tool:
            var kind: ToolKind?
            if case .tool(let k) = activity { kind = k } else { kind = recentToolProvider() }
            if let kind, !lastWorkWasAct {
                lastWorkWasAct = true
                enter(.work(kind), duration: .random(in: 2.4...4.2))
            } else {
                lastWorkWasAct = false
                if kind == nil && Double.random(in: 0...1) < 0.25 {
                    enter(.stand, duration: .random(in: 0.6...1.2))
                } else {
                    pace(fast: kind != nil)
                }
            }
        case .idle:
            if Date().timeIntervalSince(lastStimulus) > sleepAfter {
                enter(.sleep, duration: .infinity)
                return
            }
            let r = Double.random(in: 0...1)
            if r < 0.5 { wander() }
            else if r < 0.8 { enter(.stand, duration: .random(in: 2...5)) }
            else { enter(.sit, duration: .random(in: 4...9)) }
        }
    }

    private var walkBounds: ClosedRange<CGFloat> {
        halfWidth...max(halfWidth, bounds.width - halfWidth)
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        min(max(x, walkBounds.lowerBound), walkBounds.upperBound)
    }

    /// Picks a destination at least `minDistance` away, within `range` of `center`.
    private func destination(around center: CGFloat, range: CGFloat, minDistance: CGFloat) -> CGFloat {
        var t = clampX(center + .random(in: -range...range))
        if abs(t - pos.x) < minDistance {
            t = clampX(pos.x + (t >= pos.x ? 1 : -1) * minDistance * 1.5)
            if abs(t - pos.x) < minDistance { t = clampX(pos.x - (t >= pos.x ? 1 : -1) * minDistance * 1.5) }
        }
        return t
    }

    private func wander() {
        walk(to: destination(around: pos.x, range: 420 * s, minDistance: 60 * s), speed: 34 * s)
    }

    private func pace(fast: Bool) {
        let center = clampX(paceCenter ?? pos.x)
        walk(to: destination(around: center, range: 170 * s, minDistance: 60 * s), speed: (fast ? 120 : 80) * s)
    }

    private func walk(to x: CGFloat, speed: CGFloat) {
        targetX = x
        walkSpeed = speed
        enter(.walk, duration: .infinity)
        facing = x >= pos.x ? 1 : -1
    }

    private func enter(_ m: Mode, duration: TimeInterval) {
        mode = m
        modeTime = 0
        modeDuration = duration
        effectClock = 0
        jumps = 0
        orbit.sublayers = nil
        switch m {
        case .celebrate: confetti()
        case .pet: hearts(3)
        case .dizzy: orbitStars()
        case .hello, .wake: hop(300)
        case .alert: faceMouse()
        default: break
        }
    }

    private func tickTimers(_ dt: TimeInterval) {
        blinkTimer -= dt
        blinkLeft -= dt
        if blinkTimer <= 0 {
            blinkLeft = 0.12
            blinkTimer = .random(in: 2.5...5.5)
        }
        lookTimer -= dt
        if lookTimer <= 0 {
            lookDir = [-1, 0, 0, 1].randomElement()!
            lookTimer = .random(in: 1...2.5)
        }
        squashTimer -= dt
        if let t = flipTime { flipTime = t + dt >= 0.42 ? nil : t + dt }
    }

    private func tickMode(_ dt: TimeInterval) {
        switch mode {
        case .walk:
            let dx = targetX - pos.x
            let step = walkSpeed * dt
            if abs(dx) <= step {
                pos.x = targetX
                chooseNext()
            } else {
                pos.x += dx > 0 ? step : -step
                facing = dx > 0 ? 1 : -1
            }
        case .sleep:
            effectClock += dt
            if effectClock > 1.5 {
                effectClock = 0
                spawnZ()
            }
        case .alert:
            faceMouse()
            effectClock += dt
            if effectClock > 2.2 && onGround && !reduceMotion {
                effectClock = 0
                hop(260)
            }
        case .celebrate:
            if onGround && modeTime < modeDuration - 0.5 {
                hop(reduceMotion ? 330 : 470)
                jumps += 1
                if jumps == 2 && !reduceMotion { flipTime = 0 }
            }
            if modeTime >= modeDuration && onGround { chooseNext() }
        case .dizzy:
            for (i, star) in (orbit.sublayers ?? []).enumerated() {
                let a = clock * 6 + Double(i) * 2 * .pi / 3
                star.position = CGPoint(x: cos(a) * 7 * pixel, y: sin(a) * 2 * pixel)
            }
            if modeTime >= modeDuration { chooseNext() }
        case .held, .tossed:
            break
        case .work(let kind):
            if kind == .build {
                let frame = Int(clock * 3.5) % 2
                if frame == 1 && lastHammerFrame == 0 { spark() }
                lastHammerFrame = frame
            }
            if modeTime >= modeDuration { chooseNext() }
        default:
            if modeTime >= modeDuration { chooseNext() }
        }
    }

    // MARK: - Physics

    private func hop(_ speed: CGFloat) {
        guard onGround else { return }
        vel.dy = speed * s
        onGround = false
    }

    private func tickPhysics(_ dt: TimeInterval) {
        if mode == .held {
            onGround = false
            vel = .zero
            return
        }
        // The floor rose (e.g. left a full-screen app): hop back up onto it.
        if onGround && pos.y < groundY - 1 {
            vel.dy = sqrt(2 * gravity * (groundY - pos.y + 14 * s))
            onGround = false
        }
        // The floor dropped away: fall.
        if onGround && pos.y > groundY + 1 { onGround = false }

        if onGround {
            pos.y = groundY
        } else {
            vel.dy -= gravity * dt
            pos.y += vel.dy * dt
            if mode == .tossed { pos.x += vel.dx * dt }
            if vel.dy <= 0 && pos.y <= groundY {
                let impact = -vel.dy
                pos.y = groundY
                vel.dy = 0
                onGround = true
                landed(impact: impact)
            }
        }

        let bounds = walkBounds
        if pos.x < bounds.lowerBound {
            pos.x = bounds.lowerBound
            if mode == .tossed { vel.dx = abs(vel.dx) * 0.6; facing = 1 }
        } else if pos.x > bounds.upperBound {
            pos.x = bounds.upperBound
            if mode == .tossed { vel.dx = -abs(vel.dx) * 0.6; facing = -1 }
        }
    }

    private func landed(impact: CGFloat) {
        if impact > 250 * s { squashTimer = 0.14 }
        if mode == .tossed {
            vel.dx = 0
            if impact > 1200 * s { enter(.dizzy, duration: 1.8) } else { chooseNext() }
        }
    }

    // MARK: - Rendering

    private func render(_ activity: Activity) {
        let image = BuddyArt.image(currentPose())
        if image !== currentImage {
            sprite.contents = image
            currentImage = image
        }
        var angle: CGFloat = 0
        if mode == .held {
            angle = max(-0.5, min(0.5, -dragVel.dx * 0.0006))
        } else if mode == .dizzy && !reduceMotion {
            angle = sin(clock * 14) * 0.12
        } else if let t = flipTime {
            angle = -facing * 2 * .pi * min(t / 0.42, 1)
        }
        sprite.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: facing, y: 1))
        root.position = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        updateBubble(activity)
    }

    private func currentPose() -> Pose {
        var p = Pose()
        p.look = lookDir
        switch mode {
        case .walk:
            let fps: Double = walkSpeed > 90 * s ? 12 : 8
            let i = Int(clock * fps) % 4
            p.legs = [.stepA, .stand, .stepB, .stand][i]
            p.bob = i % 2
            p.look = 1
        case .stand:
            break
        case .sit:
            p.legs = .tucked
        case .sleep:
            p.legs = .tucked
            p.eyes = .closed
        case .wake:
            p.arms = .up
            p.eyes = modeTime < 0.5 ? .closed : .happy
        case .work(let kind):
            switch kind {
            case .terminal, .other:
                p.arms = Int(clock * 9) % 2 == 0 ? .typeA : .typeB
                p.prop = .keyboard
                p.look = 1
            case .build:
                let up = Int(clock * 3.5) % 2 == 0
                p.arms = up ? .hammerUp : .hammerDown
                p.prop = up ? .hammerUp : .hammerDown
                p.look = 1
            case .search:
                p.arms = .holdOut
                p.prop = .magnifier
                p.eyes = .wide
                p.look = Int(clock / 0.8) % 3 == 2 ? 0 : 1
            case .web:
                let a = Int(clock * 4) % 2 == 0
                p.prop = a ? .antennaA : .antennaB
                p.eyes = .wide
                p.bob = a ? 1 : 0
                p.look = 0
            }
        case .alert:
            p.arms = Int(clock * 4) % 2 == 0 ? .waveHigh : .waveLow
            p.eyes = .wide
            p.look = 0
        case .hello:
            p.arms = Int(clock * 5) % 2 == 0 ? .waveHigh : .waveLow
            p.eyes = .happy
        case .celebrate:
            p.arms = .up
            p.eyes = .happy
        case .pet:
            p.eyes = .happy
            p.bob = Int(clock * 6) % 2
            p.look = 0
        case .dizzy:
            p.eyes = .dizzy
            p.look = 0
        case .held, .tossed:
            p.arms = .up
            p.eyes = .wide
            p.look = 0
        }
        if blinkLeft > 0 && (p.eyes == .open || p.eyes == .wide) { p.eyes = .closed }
        if squashTimer > 0 && p.legs != .tucked {
            p.squash = true
            p.bob = 0
        }
        return p
    }

    private func updateBubble(_ activity: Activity) {
        var image: CGImage?
        var offset = CGPoint.zero
        switch mode {
        case .alert:
            image = BuddyArt.alertBubble
            let bounce = reduceMotion ? 0 : abs(sin(clock * 4)) * 2
            offset = CGPoint(x: 0, y: (12 + bounce) * pixel)
        case .walk, .stand:
            if activity == .thinking || activity.isTool {
                image = BuddyArt.thinkBubble(dots: Int(clock * 2.5) % 4)
                offset = CGPoint(x: facing * 6 * pixel, y: 11 * pixel)
            }
        default:
            break
        }
        guard let image else {
            bubble.isHidden = true
            return
        }
        bubble.isHidden = false
        if (bubble.contents as! CGImage?) !== image {
            bubble.contents = image
            bubble.bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width) * pixel, height: CGFloat(image.height) * pixel)
        }
        bubble.position = CGPoint(x: offset.x.rounded(), y: offset.y.rounded())
    }

    // MARK: - Effects (fire-and-forget Core Animation, run by the render server)

    private func effectLayer(_ image: CGImage, at point: CGPoint, scale: CGFloat = 1) -> CALayer {
        let l = CALayer()
        l.actions = Self.noActions
        l.contents = image
        l.magnificationFilter = .nearest
        l.bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width) * pixel * scale, height: CGFloat(image.height) * pixel * scale)
        l.position = point
        l.zPosition = 5
        return l
    }

    /// Adds `layer`, animates it, and removes it when done.
    private func play(_ layer: CALayer, _ animations: [CAAnimation], duration: TimeInterval) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer?.addSublayer(layer)
        layer.add(group, forKey: "fx")
        CATransaction.commit()
        liveEffects += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            layer.removeFromSuperlayer()
            self?.liveEffects -= 1
        }
    }

    private func floatAway(_ layer: CALayer, dx: CGFloat, dy: CGFloat, duration: TimeInterval, grow: (CGFloat, CGFloat)? = nil) {
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = layer.position
        move.toValue = CGPoint(x: layer.position.x + dx, y: layer.position.y + dy)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.6, 1]
        var anims: [CAAnimation] = [move, fade]
        if let grow {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = grow.0
            scale.toValue = grow.1
            anims.append(scale)
        }
        play(layer, anims, duration: duration)
    }

    private func hearts(_ count: Int) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) { [weak self] in
                guard let self else { return }
                let l = self.effectLayer(BuddyArt.heart, at: CGPoint(
                    x: self.pos.x + .random(in: -4...4) * self.pixel, y: self.pos.y + 11 * self.pixel))
                self.floatAway(l, dx: .random(in: -10...10) * self.s, dy: 40 * self.s, duration: 1.1)
            }
        }
    }

    private func spawnZ() {
        let l = effectLayer(BuddyArt.zee, at: CGPoint(x: pos.x + facing * 5 * pixel, y: pos.y + 8 * pixel))
        floatAway(l, dx: facing * 16 * s, dy: 40 * s, duration: 1.8, grow: (0.6, 1.1))
    }

    private func spark() {
        let origin = CGPoint(x: pos.x + facing * 14 * pixel, y: pos.y + 1 * pixel)
        for dx in [-1.0, 0.2, 1.0] {
            let l = effectLayer(BuddyArt.star, at: origin, scale: 0.5)
            floatAway(l, dx: CGFloat(dx) * 14 * s, dy: .random(in: 8...18) * s, duration: 0.35)
        }
    }

    private func confetti() {
        let origin = CGPoint(x: pos.x, y: pos.y + 8 * pixel)
        for _ in 0..<(reduceMotion ? 10 : 24) {
            let piece = CALayer()
            piece.actions = Self.noActions
            piece.backgroundColor = BuddyArt.confettiColors.randomElement()!
            piece.bounds = CGRect(x: 0, y: 0, width: pixel, height: pixel)
            piece.position = origin
            piece.zPosition = 4
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

    private func orbitStars() {
        for _ in 0..<3 {
            let star = CALayer()
            star.actions = Self.noActions
            star.contents = BuddyArt.star
            star.magnificationFilter = .nearest
            star.bounds = CGRect(x: 0, y: 0, width: 3 * pixel * 0.75, height: 3 * pixel * 0.75)
            orbit.addSublayer(star)
        }
    }

    // MARK: - Mouse (hold ⌥ to pet or pick up)

    private var buddyFrame: CGRect {
        CGRect(x: pos.x - halfWidth, y: pos.y, width: halfWidth * 2, height: 11 * pixel)
    }

    private func viewMouse() -> CGPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    private func faceMouse() {
        guard let m = viewMouse() else { return }
        if abs(m.x - pos.x) > 4 { facing = m.x >= pos.x ? 1 : -1 }
    }

    /// The window ignores the mouse unless ⌥ is held over the buddy (or a drag is underway),
    /// so it never gets in the way of the app you're using.
    private func updateInteractivity() {
        guard let window, let m = viewMouse() else { return }
        let hit = buddyFrame.insetBy(dx: -6 * s, dy: -6 * s).contains(m)
        let want = dragging || (NSEvent.modifierFlags.contains(.option) && hit)
        if window.ignoresMouseEvents == want { window.ignoresMouseEvents = !want }
        if want {
            (dragging ? NSCursor.closedHand : NSCursor.openHand).set()
        } else if interactive {
            NSCursor.arrow.set()
        }
        interactive = want
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard buddyFrame.insetBy(dx: -6 * s, dy: -6 * s).contains(p) else { return }
        dragging = true
        dragMoved = false
        dragStart = p
        grabOffset = CGPoint(x: pos.x - p.x, y: pos.y - p.y)
        lastDragPoint = p
        lastDragTime = event.timestamp
        dragVel = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !dragMoved {
            guard hypot(p.x - dragStart.x, p.y - dragStart.y) > 4 else { return }
            dragMoved = true
            lastStimulus = Date()
            enter(.held, duration: .infinity)
        }
        let dt = max(event.timestamp - lastDragTime, 1.0 / 240)
        let instant = CGVector(dx: (p.x - lastDragPoint.x) / dt, dy: (p.y - lastDragPoint.y) / dt)
        dragVel = CGVector(dx: dragVel.dx * 0.5 + instant.dx * 0.5, dy: dragVel.dy * 0.5 + instant.dy * 0.5)
        lastDragPoint = p
        lastDragTime = event.timestamp
        pos.x = clampX(p.x + grabOffset.x)
        pos.y = min(max(groundY, p.y + grabOffset.y), bounds.height - 12 * pixel)
        if abs(dragVel.dx) > 40 { facing = dragVel.dx > 0 ? 1 : -1 }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        if dragMoved {
            // Flick to throw.
            let limit = 1600 * s
            vel = CGVector(dx: max(-limit, min(limit, dragVel.dx)), dy: max(-limit, min(1400 * s, dragVel.dy)))
            onGround = false
            enter(.tossed, duration: .infinity)
        } else {
            pet()
        }
    }
}

private extension Activity {
    var isTool: Bool {
        if case .tool = self { return true }
        return false
    }
}
