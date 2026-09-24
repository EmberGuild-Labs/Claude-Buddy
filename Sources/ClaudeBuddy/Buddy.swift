import AppKit
import QuartzCore

/// One critter: a small state machine picking behaviors, a bit of physics, cursor reactions,
/// games with the other buddies, and its own Core Animation layers. The `BuddyStage` owns
/// and drives every buddy.
///
/// `pos` is the point between the buddy's feet, in stage coordinates (the whole screen,
/// origin bottom-left). A buddy stands on the floor (the Dock or the screen's bottom edge),
/// on the top edge of an app window, or on another buddy's head.
final class Buddy {
    unowned let stage: BuddyStage
    let isMain: Bool
    var hat: Hat
    /// The Claude Code session this buddy acts out (nil = free to wander).
    var sessionID: String?
    var info: SessionInfo?
    private(set) var isLeaving = false
    private(set) var isGone = false

    /// What it's standing on: 0 = the floor, >0 = a window number, -1 = in the air (or riding).
    private(set) var platform = 0
    private var platformOrigin = CGPoint.zero
    /// The buddy it's riding piggyback on, and the one riding it.
    private(set) weak var carrier: Buddy?
    fileprivate(set) weak var rider: Buddy?

    let root = CALayer()
    private let sprite = CALayer()
    private let bubble = CALayer()
    private let orbit = CALayer()
    private let tag = CATextLayer()
    private var tagText: String?
    private var currentImage: CGImage?

    private enum Mode: Equatable {
        case stand, sit, walk, sleep, wake, work(ToolKind), alert, hello, celebrate, pet, dizzy
        case held, tossed, arrive, chase, leap, dance, highFive, tag, conga, ride, cheer

        /// Reactions play to the end instead of being interrupted by Claude activity.
        var isReaction: Bool {
            switch self {
            case .wake, .hello, .celebrate, .pet, .dizzy, .held, .tossed, .arrive, .leap, .highFive, .ride, .cheer: true
            default: false
            }
        }
    }

    private enum WalkPurpose { case wander, pace, flee, leave }

    private let sleepAfter: TimeInterval = 5 * 60

    private var pixel: CGFloat { stage.pixel }
    /// Speeds and distances are tuned for pixel = 4 and scale with size.
    private var s: CGFloat { pixel / 4 }
    var halfWidth: CGFloat { 9 * pixel }
    /// Height of the top of its head above its feet (where a rider sits) — lower when sitting.
    var headHeight: CGFloat {
        switch mode {
        case .sit, .sleep, .ride: 7 * pixel
        default: 9 * pixel
        }
    }
    private var gravity: CGFloat { 2200 * s }
    /// Its session — or, while a menu demo runs, the demo everyone acts out together.
    private var currentInfo: SessionInfo? { isLeaving ? nil : (stage.demoInfo ?? info) }
    private var activity: Activity { currentInfo?.activity ?? .idle }

    private var mode: Mode = .stand
    private var modeTime: TimeInterval = 0
    private var modeDuration: TimeInterval = 2
    private var targetX: CGFloat = 0
    private var walkSpeed: CGFloat = 40
    private var walkPurpose = WalkPurpose.wander
    private var paceCenter: CGFloat?
    private var lastActivity: Activity = .idle
    private var lastWorkWasAct = false
    private var lastStimulus = Date()

    private(set) var pos: CGPoint
    private var vel = CGVector.zero
    private(set) var onGround = true
    private(set) var facing: CGFloat = 1
    private var squashTimer: TimeInterval = 0
    private var blinkTimer: TimeInterval = .random(in: 1...4)
    private var blinkLeft: TimeInterval = 0
    private var lookDir = 0
    private var lookTimer: TimeInterval = 1.5
    private var clock: TimeInterval = .random(in: 0...10)
    private var effectClock: TimeInterval = 0
    private var jumps = 0
    private var lastHammerFrame = 0
    private var flipTime: TimeInterval?
    private var greetCooldown: TimeInterval = 0
    private var leapCooldown: TimeInterval = .random(in: 8...20)
    private var lastBeat = -1
    private var movedThisTick = false
    private var lastTickX: CGFloat = 0

    // Games
    private enum PendingGame: Equatable { case tag, conga(Int) }
    /// A game it's jumping down from a window to join.
    private var pendingGame: PendingGame?
    private var gameFreeze: TimeInterval = 0
    private var congaIndex = 0
    /// No tag-backs: whoever just tagged it is safe for a moment.
    private weak var tagBackBlocked: Buddy?
    private var tagBackUntil: TimeInterval = 0
    private weak var partner: Buddy?
    private var highFiveLeads = false
    /// Only a buddy you drop can land on another's head (not one hopping off or tumbling).
    private var droppedByUser = false

    // Cursor
    private var cursorNear = false
    private var cursorDX: CGFloat = 0
    private var cursorDist: CGFloat = .infinity
    private var lingerTime: TimeInterval = 0
    private var behindTime: TimeInterval = 0
    private var chaseCooldown: TimeInterval = 8
    private var fleeCooldown: TimeInterval = 0
    private var chaseWalking = false

    // Dragging
    private var dragMoved = false
    private var dragStart = CGPoint.zero
    private var grabOffset = CGPoint.zero
    private var lastDragPoint = CGPoint.zero
    private var lastDragTime: TimeInterval = 0
    private var dragVel = CGVector.zero

    init(stage: BuddyStage, isMain: Bool, hat: Hat, x: CGFloat, dropIn: Bool) {
        self.stage = stage
        self.isMain = isMain
        self.hat = hat
        pos = CGPoint(x: x, y: stage.groundY)

        for l in [root, sprite, bubble, orbit, tag] { l.actions = BuddyStage.noActions }
        root.addSublayer(sprite)
        root.addSublayer(orbit)
        root.addSublayer(bubble)
        root.addSublayer(tag)
        sprite.anchorPoint = CGPoint(x: 0.5, y: BuddyArt.anchorY)
        sprite.magnificationFilter = .nearest
        bubble.anchorPoint = CGPoint(x: 0.5, y: 0)
        bubble.magnificationFilter = .nearest
        bubble.zPosition = 2
        orbit.zPosition = 3
        tag.zPosition = 4
        tag.anchorPoint = CGPoint(x: 0.5, y: 0)
        tag.alignmentMode = .center
        tag.foregroundColor = CGColor(gray: 1, alpha: 1)
        tag.backgroundColor = CGColor(srgbRed: 0.17, green: 0.11, blue: 0.09, alpha: 0.88)
        tag.cornerRadius = 4
        tag.isHidden = true
        applyScale()
        lastTickX = x

        if dropIn {
            pos.y = stage.bounds.height - 16 * pixel
            onGround = false
            platform = -1
            enter(.arrive, duration: .infinity)
        } else {
            enter(.hello, duration: 1.6)
        }
    }

    func applyScale() {
        sprite.bounds = CGRect(x: 0, y: 0, width: CGFloat(BuddyArt.width) * pixel, height: CGFloat(BuddyArt.height) * pixel)
        sprite.position = CGPoint(x: 0, y: BuddyArt.anchorY * sprite.bounds.height)
        orbit.position = CGPoint(x: 0, y: 11 * pixel)
        bubble.contents = nil
        tagText = nil
    }

    // MARK: - What the stage asks about

    var hitRect: CGRect {
        CGRect(x: pos.x - halfWidth, y: pos.y, width: halfWidth * 2, height: 11 * pixel)
            .insetBy(dx: -6 * s, dy: -6 * s)
    }

    /// Frames per second this buddy needs right now.
    var desiredFPS: Int {
        switch mode {
        case .sleep: 10
        case .stand, .sit: onGround && !stage.musicPlaying ? 15 : 30
        default: 30
        }
    }

    var isHeld: Bool { mode == .held }
    var isWalkingWander: Bool { mode == .walk && (walkPurpose == .wander || walkPurpose == .pace) }
    var isInTag: Bool { mode == .tag || pendingGame == .tag }
    var isInConga: Bool {
        if mode == .conga { return true }
        if case .conga = pendingGame { return true }
        return false
    }
    var isOnWindow: Bool { platform > 0 || carrier?.isOnWindow == true }
    /// How many buddies it's stacked on top of.
    var stackDepth: Int { carrier.map { $0.stackDepth + 1 } ?? 0 }

    /// Free to join a game with the others: idle and not busy with anything else.
    /// (Buddies up on windows jump down to the floor to play.)
    var canJoinGame: Bool {
        guard activity == .idle, !isLeaving, carrier == nil, rider == nil else { return false }
        if mode == .leap { return pendingGame == nil }  // Joins on landing.
        guard onGround else { return false }
        switch mode {
        case .stand, .sit, .dance, .chase: return true
        case .walk: return walkPurpose == .wander
        default: return false
        }
    }

    var status: [String: Any] {
        var d: [String: Any] = [
            "main": isMain, "hat": hat.rawValue, "mode": "\(mode)", "x": Int(pos.x), "y": Int(pos.y),
            "activity": "\(activity)", "leaving": isLeaving, "platform": platform,
        ]
        if let sessionID { d["session"] = sessionID }
        if let p = info?.project { d["project"] = p }
        if carrier != nil { d["riding"] = true }
        return d
    }

    // MARK: - External input

    func pulse(_ p: Pulse) {
        lastStimulus = Date()
        guard !isLeaving, mode != .held, mode != .tossed, mode != .arrive, mode != .leap else { return }
        switch p {
        case .finished:
            enter(.celebrate, duration: stage.reduceMotion ? 1.4 : 2.8)
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

    /// Wave goodbye, then walk off the nearer screen edge.
    func beginLeaving() {
        guard !isLeaving else { return }
        isLeaving = true
        sessionID = nil
        info = nil
        if mode != .held { enter(.hello, duration: 1.2) }
    }

    /// Two buddies meeting: turn to each other and high-five.
    func highFive(with other: Buddy, leads: Bool) {
        guard greetCooldown <= 0, !mode.isReaction, !isLeaving else { return }
        greetCooldown = 20
        partner = other
        highFiveLeads = leads
        facing = other.pos.x >= pos.x ? 1 : -1
        enter(.highFive, duration: 1.1)
    }

    func joinTag() {
        if mode == .leap { pendingGame = .tag; return }
        if platform != 0 { return jumpDownToPlay(.tag) }
        gameFreeze = 0.6
        enter(.tag, duration: .infinity)
    }

    private func jumpDownToPlay(_ game: PendingGame) {
        pendingGame = game
        leap(toX: clampX(pos.x + .random(in: -60...60) * s, floor: true), y: stage.groundY)
    }

    /// Just got tagged: now it's "it". Count to three before chasing, and no tag-backs.
    func gotTagged(by tagger: Buddy) {
        gameFreeze = 1.2
        tagBackBlocked = tagger
        tagBackUntil = clock + 1.2 + 2.0
        hop(220)
    }

    /// Another session finished: a quick cheer from the sidelines.
    func cheer() {
        guard activity == .idle, !mode.isReaction, !isLeaving, onGround, mode != .tag, mode != .conga else { return }
        enter(.cheer, duration: 1.0)
    }

    /// Menu demo: dance right away.
    func startDancing(for seconds: TimeInterval) {
        guard !isLeaving, !mode.isReaction else { return }
        enter(.dance, duration: seconds)
    }

    func joinConga(index: Int) {
        if mode == .leap { pendingGame = .conga(index); return }
        if platform != 0 { return jumpDownToPlay(.conga(index)) }
        congaIndex = index
        enter(.conga, duration: .infinity)
    }

    /// The stage ends a game (tag or conga).
    func endGame() {
        pendingGame = nil
        guard mode == .tag || mode == .conga else { return }
        enter(.hello, duration: 1.0)
    }

    // MARK: - Frame

    func tick(_ dt: TimeInterval) {
        clock += dt
        greetCooldown -= dt
        leapCooldown -= dt
        lastTickX = pos.x
        if activity != lastActivity {
            activityChanged(from: lastActivity, to: activity)
            lastActivity = activity
        }
        modeTime += dt
        tickTimers(dt)
        tickCursor(dt)
        tickMode(dt)
        tickPhysics(dt)
        movedThisTick = abs(pos.x - lastTickX) > 0.3
        if isLeaving && (pos.x < -halfWidth * 2 || pos.x > stage.bounds.width + halfWidth * 2) { isGone = true }
    }

    private func activityChanged(from old: Activity, to new: Activity) {
        if new != .idle { lastStimulus = Date() }
        if old == .idle && new != .idle { paceCenter = pos.x }
        guard !mode.isReaction, !isLeaving else { return }
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
        if isLeaving {
            if platform > 0 {
                leap(toX: clampX(pos.x, floor: true), y: stage.groundY)
            } else {
                let offLeft = pos.x < stage.bounds.width / 2
                walk(to: offLeft ? -halfWidth * 3 : stage.bounds.width + halfWidth * 3, speed: 95 * s, purpose: .leave)
            }
            return
        }
        switch activity {
        case .waiting:
            enter(.alert, duration: .infinity)
        case .thinking, .tool:
            var kind: ToolKind?
            if case .tool(let k) = activity { kind = k } else { kind = currentInfo?.recentTool }
            if let kind, !lastWorkWasAct {
                lastWorkWasAct = true
                enter(.work(kind), duration: .random(in: 2.4...4.2))
            } else {
                lastWorkWasAct = false
                if kind == nil && Double.random(in: 0...1) < 0.25 {
                    enter(.stand, duration: .random(in: 0.6...1.2))
                } else {
                    let center = clampX(paceCenter ?? pos.x)
                    walk(to: destination(around: center, range: 170 * s, minDistance: 60 * s),
                         speed: (kind != nil ? 120 : 80) * s, purpose: .pace)
                }
            }
        case .idle:
            if Date().timeIntervalSince(lastStimulus) > sleepAfter {
                enter(.sleep, duration: .infinity)
                return
            }
            if stage.musicPlaying && stage.danceToMusic && Double.random(in: 0...1) < 0.55 {
                enter(.dance, duration: .random(in: 6...12))
                return
            }
            if leapCooldown <= 0 && Double.random(in: 0...1) < (platform > 0 ? 0.3 : 0.2) && tryLeap() {
                return
            }
            let r = Double.random(in: 0...1)
            if r < 0.5 {
                walk(to: destination(around: pos.x, range: 420 * s, minDistance: 60 * s), speed: 34 * s, purpose: .wander)
            } else if r < 0.8 {
                enter(.stand, duration: .random(in: 2...5))
            } else {
                enter(.sit, duration: .random(in: 4...9))
            }
        }
    }

    /// Hop up onto a window, over to another, or back down to the floor.
    private func tryLeap() -> Bool {
        leapCooldown = .random(in: 10...25)
        guard stage.windowsEnabled else { return false }
        let ledges = stage.ledges(near: pos.x, reach: 520 * s, minWidth: halfWidth * 4, excluding: platform)
        if platform > 0 && (ledges.isEmpty || Double.random(in: 0...1) < 0.6) {
            leap(toX: clampX(pos.x + .random(in: -120...120) * s, floor: true), y: stage.groundY)
            return true
        }
        guard let ledge = ledges.randomElement() else { return false }
        let inset = halfWidth * 0.8
        let lo = ledge.range.lowerBound + inset, hi = ledge.range.upperBound - inset
        guard lo < hi else { return false }
        leap(toX: min(max(pos.x + .random(in: -80...80) * s, lo), hi), y: ledge.y)
        return true
    }

    private func leap(toX x: CGFloat, y: CGFloat) {
        let dy = y - pos.y
        let apex = max(dy, 0) + 36 * s
        let vy = sqrt(2 * gravity * apex)
        let tUp = vy / gravity
        let tDown = sqrt(2 * max(apex - dy, 1) / gravity)
        detachFromCarrier()
        vel = CGVector(dx: (x - pos.x) / (tUp + tDown), dy: vy)
        onGround = false
        platform = -1
        facing = x >= pos.x ? 1 : -1
        enter(.leap, duration: .infinity)
    }

    /// Where it can walk: its window ledge, or the whole floor.
    private var walkBounds: ClosedRange<CGFloat> {
        if platform > 0, let seg = currentSegment {
            let lo = seg.lowerBound + halfWidth * 0.5, hi = seg.upperBound - halfWidth * 0.5
            return lo <= hi ? lo...hi : pos.x...pos.x
        }
        return floorBounds
    }

    private var floorBounds: ClosedRange<CGFloat> {
        halfWidth...max(halfWidth, stage.bounds.width - halfWidth)
    }

    private var currentSegment: ClosedRange<CGFloat>? {
        guard platform > 0, let w = stage.windowPlatforms[platform] else { return nil }
        return w.segments.first { $0.contains(pos.x) }
    }

    private func clampX(_ x: CGFloat, floor: Bool = false) -> CGFloat {
        let b = floor ? floorBounds : walkBounds
        return min(max(x, b.lowerBound), b.upperBound)
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

    private func walk(to x: CGFloat, speed: CGFloat, purpose: WalkPurpose) {
        targetX = x
        walkSpeed = speed
        walkPurpose = purpose
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
        case .celebrate: stage.confetti(at: CGPoint(x: pos.x, y: pos.y + 8 * pixel), colors: isMain ? stage.seasonalConfetti : nil)
        case .pet: hearts(3)
        case .dizzy: orbitStars()
        case .hello, .wake, .cheer: hop(300)
        case .alert: faceCursor()
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
        chaseCooldown -= dt
        fleeCooldown -= dt
        if let t = flipTime { flipTime = t + dt >= 0.42 ? nil : t + dt }
    }

    private func tickMode(_ dt: TimeInterval) {
        switch mode {
        case .walk:
            let target = walkPurpose == .leave ? targetX : clampX(targetX)
            let dx = target - pos.x
            let step = walkSpeed * dt
            if abs(dx) <= step {
                pos.x = target
                chooseNext()
            } else {
                pos.x += dx > 0 ? step : -step
                facing = dx > 0 ? 1 : -1
            }
        case .sleep:
            effectClock += dt
            if effectClock > 1.5 {
                effectClock = 0
                stage.floatingEffect(BuddyArt.zee, at: CGPoint(x: pos.x + facing * 5 * pixel, y: pos.y + 8 * pixel),
                                     dx: facing * 16 * s, dy: 40 * s, duration: 1.8, grow: (0.6, 1.1))
            }
        case .alert:
            faceCursor()
            effectClock += dt
            if effectClock > 2.2 && onGround && !stage.reduceMotion {
                effectClock = 0
                hop(260)
            }
        case .celebrate:
            if onGround && modeTime < modeDuration - 0.5 {
                hop(stage.reduceMotion ? 330 : 470)
                jumps += 1
                if jumps == 2 && !stage.reduceMotion { flipTime = 0 }
            }
            if modeTime >= modeDuration && onGround { chooseNext() }
        case .dizzy:
            for (i, star) in (orbit.sublayers ?? []).enumerated() {
                let a = clock * 6 + Double(i) * 2 * .pi / 3
                star.position = CGPoint(x: cos(a) * 7 * pixel, y: sin(a) * 2 * pixel)
            }
            if modeTime >= modeDuration { chooseNext() }
        case .chase:
            tickChase(dt)
        case .dance:
            tickDance()
        case .highFive:
            if highFiveLeads && modeTime >= 0.3 && modeTime - dt < 0.3, let partner {
                let mid = CGPoint(x: (pos.x + partner.pos.x) / 2, y: pos.y + 11 * pixel)
                for dx in [-1.0, 0.0, 1.0] {
                    stage.floatingEffect(BuddyArt.star, at: mid, dx: CGFloat(dx) * 16 * s, dy: 14 * s, duration: 0.45, scale: 0.7)
                }
            }
            if modeTime >= modeDuration { chooseNext() }
        case .tag:
            tickTag(dt)
        case .conga:
            tickConga(dt)
        case .ride:
            if modeTime >= modeDuration { hopOffCarrier() }
        case .held, .tossed, .arrive, .leap:
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

    // MARK: - Music

    private func tickDance() {
        if !stage.musicPlaying && modeTime > 1 { chooseNext(); return }
        let beat = Int(stage.beat)
        if beat != lastBeat {
            lastBeat = beat
            switch beat % 8 {
            case 4: facing = -facing
            case 6: hop(200)
            default: break
            }
            if beat % 8 == 7 && !stage.reduceMotion && beat % 16 == 15 { flipTime = 0; hop(360) }
            if beat % (isMain ? 2 : 4) == 0 {
                stage.floatingEffect(BuddyArt.notes.randomElement()!,
                                     at: CGPoint(x: pos.x + .random(in: -6...6) * pixel, y: pos.y + 12 * pixel),
                                     dx: .random(in: -20...20) * s, dy: 46 * s, duration: 1.4, scale: 0.8)
            }
        }
        if modeTime >= modeDuration && onGround { chooseNext() }
    }

    // MARK: - Games

    private func tickTag(_ dt: TimeInterval) {
        if gameFreeze > 0 { gameFreeze -= dt; return }
        let others = stage.buddies.filter { $0 !== self && $0.isInTag }
        if stage.tagIt === self {
            // Chase the nearest player, preferring anyone but the one who just tagged it.
            let blocked = clock < tagBackUntil ? tagBackBlocked : nil
            let candidates = others.count > 1 ? others.filter { $0 !== blocked } : others
            guard let target = candidates.min(by: { abs($0.pos.x - pos.x) < abs($1.pos.x - pos.x) }) else { return }
            let dx = target.pos.x - pos.x
            facing = dx >= 0 ? 1 : -1
            pos.x = clampX(pos.x + facing * min(abs(dx), 140 * s * dt))
            if target !== blocked && abs(dx) < halfWidth * 1.3 && abs(target.pos.y - pos.y) < 30 * s {
                stage.tagged(target)
                target.gotTagged(by: self)
                // Dash away from the new "it" right away.
                facing = dx >= 0 ? -1 : 1
                vel = CGVector(dx: facing * 240 * s, dy: 280 * s)
                onGround = false
                platform = -1
                stage.floatingEffect(BuddyArt.star, at: CGPoint(x: (pos.x + target.pos.x) / 2, y: pos.y + 8 * pixel),
                                     dx: 0, dy: 16 * s, duration: 0.5)
            }
        } else if let it = stage.tagIt {
            let dx = pos.x - it.pos.x
            guard abs(dx) < 280 * s else {
                facing = dx >= 0 ? -1 : 1
                return
            }
            let away: CGFloat = dx >= 0 ? 1 : -1
            let b = walkBounds
            let cornered = (away > 0 && pos.x >= b.upperBound - 4) || (away < 0 && pos.x <= b.lowerBound + 4)
            if cornered && abs(dx) < halfWidth * 3.5 && onGround {
                // Leap over whoever's "it".
                facing = -away
                vel.dx = -away * 280 * s
                vel.dy = 560 * s
                onGround = false
                platform = -1
            } else if onGround {
                facing = away
                pos.x = clampX(pos.x + away * 125 * s * dt)
            }
        }
    }

    private func tickConga(_ dt: TimeInterval) {
        guard let leader = stage.congaLeader else { return }
        let beat = Int(stage.beat)
        if beat != lastBeat {
            lastBeat = beat
            if beat % 4 == 3 { hop(170) }
            if congaIndex == 0 && beat % 2 == 0 {
                stage.floatingEffect(BuddyArt.notes.randomElement()!, at: CGPoint(x: pos.x, y: pos.y + 12 * pixel),
                                     dx: .random(in: -16...16) * s, dy: 44 * s, duration: 1.3, scale: 0.8)
            }
        }
        if leader === self {
            let b = walkBounds
            if pos.x >= b.upperBound - 2 { facing = -1 }
            if pos.x <= b.lowerBound + 2 { facing = 1 }
            pos.x = clampX(pos.x + facing * 60 * s * dt)
        } else {
            let spacing = halfWidth * 2.3
            let target = clampX(leader.pos.x - leader.facing * CGFloat(congaIndex) * spacing)
            let dx = target - pos.x
            if abs(dx) > 2 {
                pos.x += (dx > 0 ? 1 : -1) * min(abs(dx), 150 * s * dt)
                facing = abs(dx) > spacing * 0.5 ? (dx > 0 ? 1 : -1) : leader.facing
            } else {
                facing = leader.facing
            }
        }
    }

    // MARK: - Piggyback

    private func detachFromCarrier() {
        carrier?.rider = nil
        carrier = nil
    }

    private func hopOffCarrier() {
        let away: CGFloat = carrier.map { -$0.facing } ?? (Bool.random() ? 1 : -1)
        detachFromCarrier()
        enter(.tossed, duration: .infinity)
        vel = CGVector(dx: away * 190 * s, dy: 330 * s)
        onGround = false
        platform = -1
    }

    // MARK: - Cursor reactions

    private var canPlayWithCursor: Bool {
        guard activity == .idle, !isLeaving, carrier == nil else { return false }
        switch mode {
        case .stand, .sit: return true
        case .walk: return walkPurpose == .wander
        default: return false
        }
    }

    private func tickCursor(_ dt: TimeInterval) {
        guard stage.cursorReactions, !stage.optionHeld, let m = stage.mouse else {
            cursorNear = false
            cursorDist = .infinity
            lingerTime = 0
            return
        }
        cursorDX = m.x - pos.x
        cursorDist = hypot(cursorDX, m.y - (pos.y + 5 * pixel))
        cursorNear = cursorDist < 240 * s
        let speed = stage.mouseSpeed

        // A fast swipe right past it: startle and run away.
        let head = CGPoint(x: pos.x, y: pos.y + 5 * pixel)
        let swipeDist = Self.distance(from: head, toSegment: stage.previousMouse ?? m, m)
        if swipeDist < 90 * s && speed > 1400 && fleeCooldown <= 0 && canPlayWithCursor {
            fleeCooldown = 5
            chaseCooldown = max(chaseCooldown, 10)
            let away: CGFloat = cursorDX > 0 ? -1 : 1
            walk(to: clampX(pos.x + away * 180 * s), speed: 175 * s, purpose: .flee)
            hop(300)
            return
        }

        // Lingering nearby: the closest buddy comes over to play.
        if cursorNear && speed < 350 { lingerTime += dt } else { lingerTime = 0 }
        if lingerTime > 0.9 && chaseCooldown <= 0 && canPlayWithCursor && stage.nearestToCursor === self {
            enter(.chase, duration: 7)
            lingerTime = 0
        }

        // Standing around: turn to face the cursor if it's behind.
        if cursorNear && (mode == .stand || mode == .sit) && cursorDX * facing < 0 {
            behindTime += dt
            if behindTime > 0.5 { facing = -facing; behindTime = 0 }
        } else {
            behindTime = 0
        }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let len2 = ab.dx * ab.dx + ab.dy * ab.dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / len2))
        return hypot(p.x - (a.x + t * ab.dx), p.y - (a.y + t * ab.dy))
    }

    private func tickChase(_ dt: TimeInterval) {
        guard let m = stage.mouse, cursorDist < 330 * s, activity == .idle, !stage.optionHeld else {
            chaseCooldown = 20
            chooseNext()
            return
        }
        let dx = m.x - pos.x
        let stopAt = 14 * pixel
        if abs(dx) > 4 { facing = dx > 0 ? 1 : -1 }
        if abs(dx) > stopAt {
            chaseWalking = true
            pos.x = clampX(pos.x + facing * min(abs(dx) - stopAt, 80 * s * dt))
        } else {
            chaseWalking = false
            effectClock += dt
            if effectClock > 1.1 && onGround && !stage.reduceMotion {
                effectClock = 0
                hop(230)
            }
        }
        if modeTime > modeDuration {
            chaseCooldown = 25
            chooseNext()
        }
    }

    private var eyesFollowCursor: Bool {
        switch mode {
        case .stand, .sit, .walk, .work, .ride: true
        default: false
        }
    }

    private func faceCursor() {
        guard let m = stage.mouse else { return }
        if abs(m.x - pos.x) > 4 { facing = m.x >= pos.x ? 1 : -1 }
    }

    // MARK: - Physics

    private func hop(_ speed: CGFloat) {
        guard onGround, carrier == nil else { return }
        vel = CGVector(dx: 0, dy: speed * s)
        onGround = false
        platform = -1
    }

    private func fallOff() {
        onGround = false
        platform = -1
        vel = .zero
    }

    private func tickPhysics(_ dt: TimeInterval) {
        if mode == .held {
            onGround = false
            platform = -1
            vel = .zero
            return
        }
        // Riding piggyback: stick to the carrier's head.
        if let c = carrier {
            if c.isGone || c.isHeld || c.isLeaving {
                detachFromCarrier()
                fallOff()
            } else {
                pos = CGPoint(x: c.pos.x, y: c.pos.y + c.headHeight)
                facing = c.facing
                onGround = true
                return
            }
        }

        if onGround {
            if platform == 0 {
                let groundY = stage.groundY
                if pos.y < groundY - 1 {
                    // The floor rose (e.g. left a full-screen app): hop back up onto it.
                    vel = CGVector(dx: 0, dy: sqrt(2 * gravity * (groundY - pos.y + 14 * s)))
                    onGround = false
                    platform = -1
                } else if pos.y > groundY + 1 {
                    fallOff()
                } else {
                    pos.y = groundY
                }
            } else if platform > 0, let w = stage.windowPlatforms[platform] {
                // Ride along when the window moves.
                pos.x += w.origin.x - platformOrigin.x
                pos.y = w.origin.y
                platformOrigin = w.origin
                if !w.segments.contains(where: { $0.contains(pos.x) }) { fallOff() }
            } else {
                fallOff()  // The window closed, minimized, or got covered.
            }
        }

        if !onGround {
            let prevY = pos.y
            vel.dy -= gravity * dt
            pos.y += vel.dy * dt
            pos.x += vel.dx * dt
            if vel.dy <= 0 { land(from: prevY) }
        }

        guard !isLeaving else { return }
        let b = floorBounds
        if pos.x < b.lowerBound {
            pos.x = b.lowerBound
            if !onGround { vel.dx = abs(vel.dx) * 0.6; facing = 1 }
        } else if pos.x > b.upperBound {
            pos.x = b.upperBound
            if !onGround { vel.dx = -abs(vel.dx) * 0.6; facing = -1 }
        }
    }

    /// Lands on the highest surface crossed this frame: the floor, a window ledge, or
    /// (when dropped by the user) another buddy's head.
    private func land(from prevY: CGFloat) {
        var bestY = -CGFloat.infinity
        var bestPlatform = -1
        var bestCarrier: Buddy?

        if pos.y <= stage.groundY {
            bestY = stage.groundY
            bestPlatform = 0
        }
        for (id, w) in stage.windowPlatforms where w.origin.y <= prevY + 0.5 && w.origin.y >= pos.y && w.origin.y > bestY {
            if w.segments.contains(where: { $0.contains(pos.x) }) {
                bestY = w.origin.y
                bestPlatform = id
            }
        }
        if mode == .tossed && droppedByUser && rider == nil {
            for b in stage.buddies where b !== self && b.onGround && !b.isLeaving && !b.isHeld && b.rider == nil
                && b.stackDepth < 2 && abs(b.pos.x - pos.x) < halfWidth * 0.9 {
                let headY = b.pos.y + b.headHeight
                if headY <= prevY + 0.5 && headY >= pos.y && headY > bestY {
                    bestY = headY
                    bestCarrier = b
                }
            }
        }
        guard bestY > -.infinity else { return }

        let impact = -vel.dy
        droppedByUser = false
        pos.y = bestY
        vel = .zero
        onGround = true
        if let c = bestCarrier {
            platform = -1
            carrier = c
            c.rider = self
            squashTimer = 0.14
            enter(.ride, duration: .random(in: 8...14))
            return
        }
        platform = bestPlatform
        if platform > 0, let w = stage.windowPlatforms[platform] { platformOrigin = w.origin }
        landed(impact: impact)
    }

    private func landed(impact: CGFloat) {
        if impact > 250 * s { squashTimer = 0.14 }
        switch mode {
        case .tossed:
            if impact > 1200 * s { enter(.dizzy, duration: 1.8) } else { chooseNext() }
        case .arrive:
            poof()
            enter(.hello, duration: 1.6)
        case .leap:
            if let game = pendingGame, platform != 0 { return jumpDownToPlay(game) }
            switch pendingGame {
            case .tag?:
                pendingGame = nil
                gameFreeze = 0.3
                enter(.tag, duration: .infinity)
            case .conga(let i)?:
                pendingGame = nil
                congaIndex = i
                enter(.conga, duration: .infinity)
            case nil:
                chooseNext()
            }
        default:
            break
        }
    }

    // MARK: - Rendering

    func render() {
        let image = BuddyArt.image(currentPose())
        if image !== currentImage {
            sprite.contents = image
            currentImage = image
        }
        var angle: CGFloat = 0
        if mode == .held {
            angle = max(-0.5, min(0.5, -dragVel.dx * 0.0006))
        } else if mode == .dizzy && !stage.reduceMotion {
            angle = sin(clock * 14) * 0.12
        } else if let t = flipTime {
            angle = -facing * 2 * .pi * min(t / 0.42, 1)
        } else if mode == .dance && !stage.reduceMotion {
            angle = sin(stage.beat * .pi) * 0.08
        }
        sprite.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: facing, y: 1))
        root.position = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        updateBubble()
        updateTag()
    }

    private func walkingLegs(fps: Double) -> (Pose.Legs, Int) {
        let i = Int(clock * fps) % 4
        return ([.stepA, .stand, .stepB, .stand][i], i % 2)
    }

    private func currentPose() -> Pose {
        var p = Pose()
        p.hat = hat
        p.look = lookDir
        let beat = Int(stage.beat)
        switch mode {
        case .walk:
            (p.legs, p.bob) = walkingLegs(fps: walkSpeed > 90 * s ? 12 : 8)
            p.look = 1
            if walkPurpose == .flee {
                p.eyes = .wide
                p.arms = .up
            }
        case .stand:
            if stage.musicPlaying { p.bob = beat % 2 }  // Bops along to the music.
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
        case .celebrate, .cheer:
            p.arms = .up
            p.eyes = .happy
        case .pet:
            p.eyes = .happy
            p.bob = Int(clock * 6) % 2
            p.look = 0
        case .dizzy:
            p.eyes = .dizzy
            p.look = 0
        case .held, .tossed, .arrive, .leap:
            p.arms = .up
            p.eyes = .wide
            p.look = 0
        case .chase:
            if chaseWalking {
                (p.legs, p.bob) = walkingLegs(fps: 10)
                p.eyes = .wide
            } else {
                p.eyes = .happy
                p.arms = onGround ? .down : .up
            }
            p.look = 1
        case .dance:
            let moves: [Pose.Arms] = [.up, .down, .waveHigh, .waveLow, .up, .down, .up, .waveHigh]
            p.arms = moves[beat % moves.count]
            p.eyes = .happy
            p.bob = beat % 2
            p.look = 0
        case .highFive:
            p.arms = modeTime < 0.55 ? .waveHigh : .down
            p.eyes = .happy
            p.look = 1
        case .tag:
            if movedThisTick { (p.legs, p.bob) = walkingLegs(fps: 12) }
            if stage.tagIt === self {
                p.arms = .holdOut
                p.eyes = .wide
                p.look = 1
            } else {
                p.arms = .up
                p.eyes = gameFreeze > 0 ? .wide : .happy
                p.look = -1
            }
        case .conga:
            if movedThisTick { (p.legs, _) = walkingLegs(fps: 8) }
            p.arms = congaIndex == 0 ? (beat % 2 == 0 ? .waveHigh : .up) : .holdOut
            p.eyes = .happy
            p.bob = beat % 2
            p.look = 1
        case .ride:
            p.legs = .tucked
            p.eyes = .happy
            p.arms = Int(clock * 2) % 4 == 0 ? .up : .down
            p.look = 1
        }
        // Eyes follow a nearby cursor.
        if cursorNear && eyesFollowCursor {
            p.look = cursorDX * facing >= 0 ? 1 : -1
        }
        if blinkLeft > 0 && (p.eyes == .open || p.eyes == .wide) { p.eyes = .closed }
        if squashTimer > 0 && p.legs != .tucked {
            p.squash = true
            p.bob = 0
        }
        return p
    }

    private func updateBubble() {
        var image: CGImage?
        var offset = CGPoint.zero
        switch mode {
        case .alert:
            image = BuddyArt.alertBubble
            let bounce = stage.reduceMotion ? 0 : abs(sin(clock * 4)) * 2
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

    /// Name tag on hover: the session's project, or the song for a dancing main buddy.
    private func updateTag() {
        var label = stage.buddyCount > 1 ? info?.project : nil
        if isMain && mode == .dance, let track = stage.musicTrack { label = "♪ " + track }
        let show = label != nil && ((cursorDist < 120 * s && mode != .held) || (mode == .alert && stage.buddyCount > 1))
        guard show, let label else {
            tag.isHidden = true
            return
        }
        if tagText != label {
            tagText = label
            let text = label.count > 28 ? String(label.prefix(27)) + "…" : label
            let font = NSFont.monospacedSystemFont(ofSize: max(10, 11 * s), weight: .bold)
            let size = (text as NSString).size(withAttributes: [.font: font])
            tag.string = text
            tag.font = font
            tag.fontSize = font.pointSize
            tag.contentsScale = stage.window?.backingScaleFactor ?? 2
            tag.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 12, height: ceil(size.height) + 4)
        }
        tag.isHidden = false
        let top = bubble.isHidden ? 12 * pixel : bubble.position.y + bubble.bounds.height
        tag.position = CGPoint(x: 0, y: (top + 3 * s).rounded())
    }

    // MARK: - Effects

    private func hearts(_ count: Int) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) { [weak self] in
                guard let self else { return }
                self.stage.floatingEffect(BuddyArt.heart,
                                          at: CGPoint(x: self.pos.x + .random(in: -4...4) * self.pixel, y: self.pos.y + 11 * self.pixel),
                                          dx: .random(in: -10...10) * self.s, dy: 40 * self.s, duration: 1.1)
            }
        }
    }

    private func spark() {
        let origin = CGPoint(x: pos.x + facing * 14 * pixel, y: pos.y + 1 * pixel)
        for dx in [-1.0, 0.2, 1.0] {
            stage.floatingEffect(BuddyArt.star, at: origin, dx: CGFloat(dx) * 14 * s, dy: .random(in: 8...18) * s,
                                 duration: 0.35, scale: 0.5)
        }
    }

    private func poof() {
        let origin = CGPoint(x: pos.x, y: pos.y + 1 * pixel)
        for dx in [-1.0, -0.4, 0.4, 1.0] {
            stage.floatingEffect(BuddyArt.star, at: origin, dx: CGFloat(dx) * 30 * s, dy: .random(in: 4...14) * s,
                                 duration: 0.4, scale: 0.6)
        }
    }

    private func orbitStars() {
        for _ in 0..<3 {
            let star = CALayer()
            star.actions = BuddyStage.noActions
            star.contents = BuddyArt.star
            star.magnificationFilter = .nearest
            star.bounds = CGRect(x: 0, y: 0, width: 3 * pixel * 0.75, height: 3 * pixel * 0.75)
            orbit.addSublayer(star)
        }
    }

    // MARK: - Dragging (the stage routes ⌥-mouse events here)

    func grab(at p: CGPoint, time: TimeInterval) {
        dragMoved = false
        dragStart = p
        grabOffset = CGPoint(x: pos.x - p.x, y: pos.y - p.y)
        lastDragPoint = p
        lastDragTime = time
        dragVel = .zero
    }

    func drag(to p: CGPoint, time: TimeInterval) {
        if !dragMoved {
            guard hypot(p.x - dragStart.x, p.y - dragStart.y) > 4 else { return }
            dragMoved = true
            lastStimulus = Date()
            detachFromCarrier()
            enter(.held, duration: .infinity)
        }
        let dt = max(time - lastDragTime, 1.0 / 240)
        let instant = CGVector(dx: (p.x - lastDragPoint.x) / dt, dy: (p.y - lastDragPoint.y) / dt)
        dragVel = CGVector(dx: dragVel.dx * 0.5 + instant.dx * 0.5, dy: dragVel.dy * 0.5 + instant.dy * 0.5)
        lastDragPoint = p
        lastDragTime = time
        pos.x = clampX(p.x + grabOffset.x, floor: true)
        pos.y = min(max(stage.groundY, p.y + grabOffset.y), stage.bounds.height - 12 * pixel)
        if abs(dragVel.dx) > 40 { facing = dragVel.dx > 0 ? 1 : -1 }
    }

    func release() {
        if dragMoved {
            // Flick to throw — or drop onto a window ledge or another buddy's head.
            let limit = 1600 * s
            vel = CGVector(dx: max(-limit, min(limit, dragVel.dx)), dy: max(-limit, min(1400 * s, dragVel.dy)))
            onGround = false
            platform = -1
            droppedByUser = true
            enter(.tossed, duration: .infinity)
        } else {
            lastStimulus = Date()
            chaseCooldown = max(chaseCooldown, 6)
            enter(.pet, duration: 1.6)
        }
    }
}

private extension Activity {
    var isTool: Bool {
        if case .tool = self { return true }
        return false
    }
}
