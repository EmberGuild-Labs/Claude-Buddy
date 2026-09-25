import AppKit
import QuartzCore

/// Performs pack activities: casts buddies (summoning a guest when a role is missing), then
/// runs the script, moving and posing them, showing props, and listening for clicks and keys.
/// Works like `NapDirector` (it scripts buddies through `beginScript`/`script`/`endScript`), but
/// the routine comes from data. One activity runs at a time; the nap and the billboard win.
final class ActivityDirector {
    unowned let stage: BuddyStage
    var catalog: ExtrasCatalog { ExtrasCatalog.current }
    /// Real system-wide key grabs for `waitFor key:…` and puppet mode (off in the self-test).
    var grabsRealKeys = true
    /// `openApp` steps really launch apps (off in the self-test and `--film`).
    var opensApps = true
    /// Apps an `openApp` step asked for (for tests).
    private(set) var openedApps: [String] = []
    /// Called when an activity ends (finished or cancelled), with its id.
    var onEnd: ((String) -> Void)?

    fileprivate weak var host: CALayer?
    private(set) var performance: Performance?
    /// The leader key's little "listening" bubble over the main buddy.
    private let hud = CALayer()
    private var hudText: String?
    private var hudUntil: TimeInterval = 0
    fileprivate(set) var clock: TimeInterval = 0

    var isActive: Bool { performance != nil }
    var currentID: String? { performance?.def.id }

    enum StartResult: Equatable {
        case started, signalled
        case busy(String)
        case unavailable(String)
        case unknown
    }

    init(stage: BuddyStage) {
        self.stage = stage
        hud.actions = BuddyStage.noActions
        hud.magnificationFilter = .nearest
        hud.anchorPoint = CGPoint(x: 0.5, y: 0)
        hud.zPosition = 30
        hud.isHidden = true
    }

    func attach(to layer: CALayer?) {
        host = layer
        layer?.addSublayer(hud)
    }

    var status: [String: Any] {
        guard let p = performance else { return ["activity": "none"] }
        return ["activity": p.def.id, "phase": p.casting ? "casting" : "running",
                "cast": p.actors.mapValues { a in a.left ? "left" : (a.buddy.isGuest ? "guest" : (a.buddy.isMain ? "main" : "extra")) }]
    }

    // MARK: - Control

    /// Why an activity can't start at all right now (nil = it can).
    func unavailableReason(_ def: ActivityDef) -> String? {
        let free = freeBuddies()
        var used = 0
        for role in def.cast where role.ifMissing == .unavailable {
            let candidates = role.who == .main ? free.filter(\.isMain) : (role.who == .other ? free.filter { !$0.isMain } : free)
            if candidates.count <= used { return "Needs \(def.cast.filter { $0.ifMissing != .skip }.count) buddies" }
            used += 1
        }
        return nil
    }

    @discardableResult
    func start(_ id: String) -> StartResult {
        guard let def = catalog.activities[id] else { return .unknown }
        return start(def)
    }

    /// `preferred`: the buddy a trigger was about (e.g. the one on a Finder window) plays the
    /// first `any`/`other` role if it's free. `vars` fill `{placeholders}` in `say` text.
    @discardableResult
    func start(_ def: ActivityDef, preferred: Buddy? = nil, vars: [String: String] = [:]) -> StartResult {
        if let p = performance {
            if p.def.id == def.id {
                p.signal(.again)
                return .signalled
            }
            return .busy("Busy with \(p.def.title)")
        }
        if stage.nap.isActive { return .busy("Napping") }
        guard stage.mainBuddy != nil else { return .busy("No buddy") }
        if let reason = unavailableReason(def) { return .unavailable(reason) }

        var free = freeBuddies()
        var actors: [String: Buddy] = [:]
        var guests: [(String, RoleSpec)] = []
        for role in def.cast {
            let pick: Buddy?
            switch role.who {
            case .main: pick = free.first(where: \.isMain)
            case .other:
                pick = preferred.flatMap { p in free.first { $0 === p && !$0.isMain } } ?? nearestToMain(free.filter { !$0.isMain })
            case .any:
                pick = preferred.flatMap { p in free.first { $0 === p } } ?? free.first(where: \.isMain) ?? nearestToMain(free)
            }
            if let pick {
                actors[role.name] = pick
                free.removeAll { $0 === pick }
            } else if role.who == .main {
                return .busy("The main buddy is busy")
            } else {
                switch role.ifMissing {
                case .summon: guests.append((role.name, role))
                case .unavailable: return .unavailable("Needs more buddies")
                case .skip: break
                }
            }
        }
        if stage.boardOpen { stage.closeBoard() }
        let usedHats = Set(stage.buddies.map(\.hat))
        for (name, role) in guests {
            let hat = role.hat ?? Hat.sessionPool.first { !usedHats.contains($0) } ?? .party
            if let g = stage.summonGuest(hat: hat) { actors[name] = g }
        }
        performance = Performance(def: def, director: self, buddies: actors, vars: vars)
        return .started
    }

    /// Stops the current activity right away and puts everyone back to normal.
    func cancel() {
        guard let p = performance else { return }
        performance = nil
        p.cleanUp(greet: false)
        onEnd?(p.def.id)
    }

    /// An ⌥-click on a scripted buddy.
    func clicked(_ buddy: Buddy) {
        guard let p = performance, let role = p.actors.first(where: { $0.value.buddy === buddy })?.key else { return }
        p.signal(.click(role))
    }

    /// A key grabbed for `waitFor key:…` or puppet mode.
    func keyEvent(_ name: String, down: Bool) {
        performance?.key(KeyNames.canonical(name), down: down)
    }

    /// Shows (or hides) the leader-key bubble over the main buddy.
    func showHUD(_ text: String?, for seconds: TimeInterval = 3) {
        hudText = text
        hudUntil = clock + seconds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let text {
            let canvas = SpeechBubble.render(text, maxWidth: 80)
            hud.contents = canvas.cgImage()
            hud.bounds = CGRect(x: 0, y: 0, width: CGFloat(canvas.width) * stage.boardScale, height: CGFloat(canvas.height) * stage.boardScale)
            hud.isHidden = false
            layoutHUD()
        } else {
            hud.isHidden = true
        }
        CATransaction.commit()
    }

    private func layoutHUD() {
        guard let main = stage.mainBuddy else { return }
        let half = hud.bounds.width / 2
        let x = min(max(main.pos.x, half + 4), stage.bounds.width - half - 4)
        hud.position = CGPoint(x: x.rounded(), y: (main.pos.y + 15 * stage.pixel).rounded())
    }

    // MARK: - Frame

    func tick(_ dt: TimeInterval) {
        clock += dt
        if hudText != nil {
            if clock > hudUntil { showHUD(nil) } else { layoutHUD() }
        }
        guard let p = performance else { return }
        if p.tick(dt) {
            performance = nil
            p.cleanUp(greet: p.def.greetAtEnd)
            onEnd?(p.def.id)
        }
    }

    // MARK: - Helpers

    fileprivate func freeBuddies() -> [Buddy] {
        stage.buddies.filter { !$0.isLeaving && !$0.isGone && !$0.isHeld && !$0.isScripted }
    }

    private func nearestToMain(_ list: [Buddy]) -> Buddy? {
        let x = stage.mainBuddy?.pos.x ?? 0
        // Prefer buddies whose Claude session is idle; then the closest.
        return list.min { a, b in
            let ai = a.info?.activity ?? .idle, bi = b.info?.activity ?? .idle
            if (ai == .idle) != (bi == .idle) { return ai == .idle }
            return abs(a.pos.x - x) < abs(b.pos.x - x)
        }
    }

    fileprivate func grab(_ key: String) -> UInt32? {
        guard grabsRealKeys, let code = KeyNames.code(for: key) else { return nil }
        return KeyGrabber.shared.grab(code: code, modifiers: 0) { [weak self] down in self?.keyEvent(key, down: down) }
    }

    fileprivate func release(_ id: UInt32) { KeyGrabber.shared.release(id) }

    fileprivate func openApp(_ app: String) {
        openedApps.append(app)
        guard opensApps else { return }
        let ws = NSWorkspace.shared
        var url = ws.urlForApplication(withBundleIdentifier: app)
        if url == nil {
            let name = app.hasSuffix(".app") ? app : app + ".app"
            url = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
                .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        guard let url else { return }
        ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Performance

enum Signal: Hashable {
    case click(String)
    case again
    case key(String)
}

/// A buddy's part in the running activity.
final class CastMember {
    let buddy: Buddy
    let role: String
    var x: CGFloat
    var y: CGFloat
    var startX: CGFloat
    var startY: CGFloat
    var facing: CGFloat
    var basePose = PoseSpec()
    var clip: Clip?
    var clipTime: Double = 0
    var clipLastFrame = -1
    var walking = false
    var airborne = false
    var crouching = false
    var hidden = false
    var extraAccessories: [String] = []
    var riding: (prop: String, offset: PointExpr?)?
    var left = false
    let bubble = CALayer()
    var sayText: String?
    var sayUntil: TimeInterval = 0
    var bubbleShowing: String?
    var legClock: Double = 0

    init(buddy: Buddy, role: String) {
        self.buddy = buddy
        self.role = role
        x = buddy.pos.x
        y = buddy.pos.y
        startX = x
        startY = y
        facing = buddy.facing
        bubble.actions = BuddyStage.noActions
        bubble.magnificationFilter = .nearest
        bubble.anchorPoint = CGPoint(x: 0.5, y: 0)
        bubble.zPosition = 25
        bubble.isHidden = true
        bubble.name = "extras.bubble"
    }
}

final class PropState {
    let name: String
    let art: ArtDef
    let artName: String
    let layer = CALayer()
    var x: CGFloat = 0       // Bottom-center, stage points.
    var y: CGFloat = 0
    var visible = false
    var frame: String
    var flip = false
    var follow: (role: String, side: FollowSide, gap: Double, offset: PointExpr?)?
    var shakeUntil: TimeInterval = 0
    var shakeAmount: Double = 1

    init(name: String, artName: String, art: ArtDef, z: Double) {
        self.name = name
        self.artName = artName
        self.art = art
        frame = art.defaultFrame
        layer.actions = BuddyStage.noActions
        layer.magnificationFilter = .nearest
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.zPosition = CGFloat(z)
        layer.isHidden = true
        layer.name = "extras.prop"
    }
}

final class Performance {
    let def: ActivityDef
    unowned let director: ActivityDirector
    private(set) var actors: [String: CastMember] = [:]
    private(set) var props: [String: PropState] = [:]
    private var root: TrackRun!
    private var background: [TrackRun] = []
    private(set) var casting = true
    private var castingTime: TimeInterval = 0
    private(set) var signals: Set<Signal> = []
    private var incoming: Set<Signal> = []
    private(set) var heldKeys: Set<String> = []
    private var grabs: [String: (id: UInt32?, count: Int)] = [:]
    var clock: TimeInterval = 0
    /// Fills `{placeholders}` in `say` text: {count}, {s}, {app}, {project}, {tool}, …
    let vars: [String: String]
    /// The stretch of window edge the first buddy started on (`ledge.left`, `ledge.right`, `ledge`).
    private(set) var ledge: (range: ClosedRange<CGFloat>, y: CGFloat)?

    var stage: BuddyStage { director.stage }
    var P: CGFloat { stage.pixel }
    var catalog: ExtrasCatalog { director.catalog }

    init(def: ActivityDef, director: ActivityDirector, buddies: [String: Buddy], vars: [String: String] = [:]) {
        self.def = def
        self.director = director
        self.vars = def.vars.merging(vars) { $1 }
        for (role, b) in buddies { actors[role] = CastMember(buddy: b, role: role) }
        // Props from this activity and anything it calls.
        var specs = def.props
        var seen: Set<String> = [def.id]
        func collect(_ steps: [Step]) {
            director.catalog.forEachStep(steps) { step in
                if case .call(let id) = step, !seen.contains(id), let target = director.catalog.activities[id] {
                    seen.insert(id)
                    specs.merge(target.props) { a, _ in a }
                    collect(target.steps)
                }
            }
        }
        collect(def.steps)
        for (name, spec) in specs {
            guard let art = director.catalog.art[spec.art] else { continue }
            let p = PropState(name: name, artName: spec.art, art: art, z: spec.z)
            props[name] = p
            director.host?.addSublayer(p.layer)
        }
        for a in actors.values {
            director.host?.addSublayer(a.bubble)
            if !def.stayOnWindows { a.buddy.comeDownToFloor() }
        }
    }

    // MARK: Signals and keys

    func signal(_ s: Signal) { incoming.insert(s) }

    func key(_ name: String, down: Bool) {
        if down {
            heldKeys.insert(name)
            incoming.insert(.key(name))
        } else {
            heldKeys.remove(name)
        }
    }

    func matches(_ c: Condition) -> Bool {
        switch c {
        case .click(let role):
            return signals.contains { if case .click(let r) = $0 { return role == nil || r == role } else { return false } }
        case .key(let k): return signals.contains(.key(KeyNames.canonical(k)))
        case .again: return signals.contains(.again)
        case .never: return false
        }
    }

    func grabKey(_ raw: String) {
        let k = KeyNames.canonical(raw)
        if var g = grabs[k] {
            g.count += 1
            grabs[k] = g
        } else {
            grabs[k] = (director.grab(k), 1)
        }
    }

    func releaseKey(_ raw: String) {
        let k = KeyNames.canonical(raw)
        guard var g = grabs[k] else { return }
        g.count -= 1
        if g.count <= 0 {
            if let id = g.id { director.release(id) }
            grabs[k] = nil
            heldKeys.remove(k)
        } else {
            grabs[k] = g
        }
    }

    // MARK: Frame

    /// Returns true when the activity is over.
    func tick(_ dt: TimeInterval) -> Bool {
        clock += dt
        signals = incoming
        incoming = []
        if casting {
            castingTime += dt
            // Wait for guests to land and window-sitters to hop down (but not forever).
            let ready = actors.values.allSatisfy { $0.buddy.isSettled && ($0.buddy.platform == 0 || def.stayOnWindows || castingTime > 4) }
            guard ready || castingTime > 6 else { return false }
            for a in actors.values {
                a.buddy.beginScript()
                a.x = a.buddy.pos.x
                a.y = def.stayOnWindows ? a.buddy.pos.y : stage.groundY
                a.startX = a.x
                a.startY = a.y
                a.facing = a.buddy.facing
            }
            if def.stayOnWindows, let first = actors[def.starRole] ?? actors.values.first,
               first.buddy.platform > 0, let w = stage.windowPlatforms[first.buddy.platform],
               let seg = w.segments.first(where: { $0.contains(first.x) }) {
                ledge = (seg, w.origin.y)
            }
            casting = false
            root = TrackRun(steps: def.steps, who: nil, perf: self)
            signals = []
        }
        // Someone was taken away (dismissed, or the session setting changed).
        for a in actors.values where !a.left && !a.buddy.isScripted {
            if a.buddy.isMain { return true }
            a.left = true
            a.bubble.removeFromSuperlayer()
        }
        for a in actors.values {
            a.walking = false
            a.airborne = false
        }
        root.advance(dt)
        for t in background { t.advance(dt) }
        background.removeAll(where: \.done)
        for a in actors.values where !a.left {
            a.clipTime += dt
            a.legClock += dt
        }
        layout()
        return root.done
    }

    func fill(_ text: String) -> String {
        var out = text
        for (k, v) in vars { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }

    func spawn(_ steps: [Step], who: String?) {
        background.append(TrackRun(steps: steps, who: who, perf: self))
    }

    // MARK: Geometry

    func actor(_ who: String?) -> CastMember? {
        let a = actors[who ?? def.starRole] ?? (who == nil ? actors.values.first : nil)
        return a?.left == true ? nil : a
    }

    func width(_ p: PropState) -> CGFloat { CGFloat(p.art.width) * P }
    func height(_ p: PropState) -> CGFloat { CGFloat(p.art.height) * P }

    func evalX(_ e: PosExpr?, for a: CastMember?) -> CGFloat? {
        guard let e else { return nil }
        let off = CGFloat(e.offset) * P
        guard let base = e.base else { return off }
        let w = stage.bounds.width, half = 9 * P
        if base.hasSuffix("%"), let v = Double(base.dropLast()) { return w * CGFloat(v) / 100 + off }
        switch base {
        case "left": return off
        case "right": return w + off
        case "center", "middle": return w / 2 + off
        case "here": return (a?.x ?? w / 2) + off
        case "start": return (a?.startX ?? w / 2) + off
        case "cursor": return (stage.mouse?.x ?? w / 2) + off
        case "offleft": return -half * 3 + off
        case "offright": return w + half * 3 + off
        case "main": return (stage.mainBuddy?.pos.x ?? w / 2) + off
        // The window edge it started on; on the floor, the screen edges stand in.
        case "ledge": return (ledge.map { ($0.range.lowerBound + $0.range.upperBound) / 2 } ?? w / 2) + off
        case "ledge.left": return (ledge?.range.lowerBound ?? 0) + off
        case "ledge.right": return (ledge?.range.upperBound ?? w) + off
        default: break
        }
        let parts = base.split(separator: ".", maxSplits: 1).map(String.init)
        if let other = actors[parts[0]] { return other.x + off }
        if let p = props[parts[0]] {
            switch parts.count > 1 ? parts[1] : "x" {
            case "left": return p.x - width(p) / 2 + off
            case "right": return p.x + width(p) / 2 + off
            default: return p.x + off
            }
        }
        return off
    }

    func evalY(_ e: PosExpr?, for a: CastMember?) -> CGFloat? {
        guard let e else { return nil }
        let off = CGFloat(e.offset) * P
        let floor = stage.groundY
        guard let base = e.base else { return floor + off }
        if base.hasSuffix("%"), let v = Double(base.dropLast()) { return stage.bounds.height * CGFloat(v) / 100 + off }
        switch base {
        case "floor", "ground": return floor + off
        case "start": return (a?.startY ?? floor) + off
        case "top": return stage.bounds.height + off
        case "here": return (a?.y ?? floor) + off
        case "cursor": return (stage.mouse?.y ?? floor) + off
        case "ledge": return (ledge?.y ?? floor) + off
        default: break
        }
        let parts = base.split(separator: ".", maxSplits: 1).map(String.init)
        let suffix = parts.count > 1 ? parts[1] : "y"
        if let other = actors[parts[0]] { return other.y + (suffix == "head" ? 9 * P : 0) + off }
        if let p = props[parts[0]] {
            switch suffix {
            case "top": return p.y + height(p) + off
            case "center": return p.y + height(p) / 2 + off
            default: return p.y + off
            }
        }
        return floor + off
    }

    // MARK: Drawing

    private func layout() {
        let P = self.P
        for p in props.values {
            if let f = p.follow, let a = actors[f.role] {
                let w = width(p)
                switch f.side {
                case .behind: p.x = a.x - a.facing * (9 * P + CGFloat(f.gap) * P + w / 2)
                case .ahead: p.x = a.x + a.facing * (9 * P + CGFloat(f.gap) * P + w / 2)
                case .offset:
                    p.x = a.x + a.facing * CGFloat(f.offset?.x?.offset ?? 0) * P
                    p.y = a.y + CGFloat(f.offset?.y?.offset ?? 0) * P
                }
            }
        }
        for a in actors.values where !a.left {
            if let ride = a.riding, let p = props[ride.prop] {
                a.x = p.x - width(p) / 2 + CGFloat(ride.offset?.x?.offset ?? Double(p.art.width) / 2) * P
                a.y = p.y + CGFloat(ride.offset?.y?.offset ?? Double(p.art.height)) * P
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in props.values {
            p.layer.isHidden = !p.visible
            guard p.visible else { continue }
            if let img = catalog.image(art: p.artName, frame: p.frame), (p.layer.contents as AnyObject?) !== img { p.layer.contents = img }
            p.layer.bounds = CGRect(x: 0, y: 0, width: width(p), height: height(p))
            var shake: CGFloat = 0
            if clock < p.shakeUntil && !stage.reduceMotion { shake = sin(clock * 45) * P * 0.5 * CGFloat(p.shakeAmount) }
            p.layer.position = CGPoint(x: (p.x + shake).rounded(), y: p.y.rounded())
            p.layer.setAffineTransform(p.flip ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        }
        for a in actors.values where !a.left { apply(a) }
        CATransaction.commit()
    }

    /// The pose this actor shows right now: its clip frame over its base pose, plus walking legs.
    private func apply(_ a: CastMember) {
        var spec = a.basePose
        if let clip = a.clip, !clip.frames.isEmpty {
            let (i, frac) = frameIndex(clip, a.clipTime)
            var frame = clip.frames[i].pose
            if clip.tween, frac > 0 {
                let next = clip.frames[(i + 1) % clip.frames.count].pose
                if i + 1 < clip.frames.count || clip.loop {
                    func mix(_ a: Double?, _ b: Double?) -> Double? { a == nil && b == nil ? nil : (a ?? 0) + ((b ?? 0) - (a ?? 0)) * frac }
                    frame.angle = mix(frame.angle, next.angle)
                    frame.dx = mix(frame.dx, next.dx)
                    frame.dy = mix(frame.dy, next.dy)
                }
            }
            spec = frame.over(spec)
            if i != a.clipLastFrame {
                a.clipLastFrame = i
                if let fx = clip.frames[i].effect { playEffect(fx, at: a) }
            }
        }
        var p = Pose()
        p.look = a.walking ? 1 : 0
        if a.walking && spec.legs == nil {
            let i = Int(a.legClock * 10) % 4
            p.legs = [.stepA, .stand, .stepB, .stand][i]
            p.bob = i % 2
        }
        if a.airborne {
            p.arms = .up
            p.eyes = .wide
        }
        if a.crouching { p.legs = .tucked }
        if let v = spec.legs { p.legs = v }
        if let v = spec.eyes { p.eyes = v }
        if let v = spec.arms { p.arms = v }
        if let v = spec.prop { p.prop = v }
        if let v = spec.look { p.look = v }
        if let v = spec.bob { p.bob = v }
        if let v = spec.squash { p.squash = v }
        switch spec.hat {
        case "none"?: p.hat = .none
        case let name? where name != "keep": p.hat = Hat(rawValue: name) ?? a.buddy.hat
        default: p.hat = a.buddy.hat
        }
        var acc = a.buddy.accessories
        for x in a.extraAccessories + (spec.accessories ?? []) where !acc.contains(x) { acc.append(x) }
        p.accessories = acc

        let hidden = a.hidden || spec.hidden == true
        a.buddy.scriptImage = spec.art.flatMap { catalog.spriteImage(art: $0) }
        a.buddy.scriptAngle = CGFloat(spec.angle ?? 0) * .pi / 180
        let x = a.x + CGFloat(spec.dx ?? 0) * a.facing * P
        let y = a.y + CGFloat(spec.dy ?? 0) * P
        a.buddy.script(x: x, y: y, facing: a.facing, pose: hidden ? .hidden : .custom(p))

        // Speech bubble.
        if let text = a.sayText, clock < a.sayUntil, !hidden {
            if a.bubble.isHidden || a.bubbleShowing != text {
                let c = SpeechBubble.render(text, maxWidth: 84)
                a.bubble.contents = c.cgImage()
                a.bubbleShowing = text
                a.bubble.bounds = CGRect(x: 0, y: 0, width: CGFloat(c.width) * stage.boardScale, height: CGFloat(c.height) * stage.boardScale)
            }
            a.bubble.isHidden = false
            let half = a.bubble.bounds.width / 2
            let bx = min(max(x, half + 4), stage.bounds.width - half - 4)
            // Above its head, but never off the top of the screen (a window near the menu bar).
            let by = min(y + 14 * P, stage.bounds.height - a.bubble.bounds.height - 2)
            a.bubble.position = CGPoint(x: bx.rounded(), y: by.rounded())
        } else {
            a.bubble.isHidden = true
            if clock >= a.sayUntil { a.sayText = nil }
        }
    }

    private func frameIndex(_ clip: Clip, _ t: Double) -> (Int, Double) {
        let total = clip.duration
        guard total > 0 else { return (0, 0) }
        var local = clip.loop ? t.truncatingRemainder(dividingBy: total) : min(t, total - 0.0001)
        for (i, f) in clip.frames.enumerated() {
            if local < f.time { return (i, local / f.time) }
            local -= f.time
        }
        return (clip.frames.count - 1, 0)
    }

    // MARK: Effects

    func playEffect(_ fx: EffectSpec, at a: CastMember?, prop: PropState? = nil) {
        let P = self.P
        let origin: CGPoint
        if let prop {
            origin = CGPoint(x: prop.x, y: prop.y + height(prop))
        } else if let a {
            origin = CGPoint(x: a.x, y: a.y + 10 * P)
        } else {
            return
        }
        let s = P / 4
        switch fx.kind {
        case "confetti":
            stage.confetti(at: origin, colors: nil)
        case "hearts", "zzz", "notes", "stars", "sparkle", "snow", "float":
            for i in 0..<max(1, fx.count) {
                let delay = Double(i) * (fx.kind == "stars" || fx.kind == "sparkle" ? 0 : 0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak stage = self.stage] in
                    guard let stage else { return }
                    let image: CGImage?
                    var dx = CGFloat.random(in: -10...10) * s, dy = 40 * s, time = fx.time, scale: CGFloat = 1
                    var start = origin
                    var grow: (CGFloat, CGFloat)?
                    switch fx.kind {
                    case "hearts": image = BuddyArt.heart
                    case "zzz":
                        image = BuddyArt.zee
                        dx = 16 * s
                        grow = (0.6, 1.1)
                        start.x += 5 * P
                    case "notes": image = BuddyArt.notes.randomElement()
                    case "stars", "sparkle":
                        image = BuddyArt.star
                        let angle = Double(i) / Double(max(1, fx.count)) * 2 * .pi
                        dx = CGFloat(cos(angle)) * (fx.kind == "stars" ? 30 : 14) * s
                        dy = CGFloat(sin(angle)) * (fx.kind == "stars" ? 20 : 10) * s + 6 * s
                        time = fx.kind == "stars" ? 0.45 : 0.35
                        scale = fx.kind == "stars" ? 0.6 : 0.5
                    case "snow":
                        image = BuddyArt.snowflake
                        start = CGPoint(x: origin.x + .random(in: -40...40) * s, y: origin.y + 30 * s)
                        dx = .random(in: -8...8) * s
                        dy = -40 * s
                        scale = 0.6
                    default:
                        image = fx.art.flatMap { ExtrasCatalog.current.image(art: $0) }
                        dx = CGFloat(fx.dx) * P * (Bool.random() ? 1 : -1) * 0.5
                        dy = CGFloat(fx.dy) * P
                    }
                    if let image { stage.floatingEffect(image, at: start, dx: dx, dy: dy, duration: time, scale: scale, grow: grow) }
                }
            }
        default:
            break
        }
    }

    // MARK: Cleanup

    func cleanUp(greet: Bool) {
        root?.cancel()
        background.forEach { $0.cancel() }
        for (_, g) in grabs { if let id = g.id { director.release(id) } }
        grabs = [:]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in props.values { p.layer.removeFromSuperlayer() }
        for a in actors.values {
            a.bubble.removeFromSuperlayer()
            guard !a.left else { continue }
            a.left = true
            if a.buddy.isGuest {
                a.buddy.endScript(greet: false)
                a.buddy.beginLeaving()
            } else {
                a.buddy.endScript(greet: greet)
            }
        }
        CATransaction.commit()
    }

    /// A buddy bows out early (`leave`).
    func dismiss(_ a: CastMember) {
        guard !a.left else { return }
        a.left = true
        a.bubble.removeFromSuperlayer()
        a.buddy.endScript(greet: false)
        if a.buddy.isGuest { a.buddy.beginLeaving() }
    }
}

// MARK: - Tracks

/// A running list of steps (the main script, a `together` lane, or an `async` side job).
final class TrackRun {
    private struct Frame {
        var steps: [Step]
        var index = 0
        var who: String?
        var timesLeft: Int?
        var until: [Condition] = []
        var endTime: TimeInterval?
        var isLoop = false
        var grabbedKeys: [String] = []
    }

    private var stack: [Frame] = []
    private var current: StepRun?
    private(set) var done = false
    unowned let perf: Performance

    init(steps: [Step], who: String?, perf: Performance) {
        self.perf = perf
        stack = [Frame(steps: steps, who: who)]
    }

    var who: String? { stack.last?.who }

    func push(_ steps: [Step], who: String? = nil) {
        guard stack.count < 64 else { return }
        stack.append(Frame(steps: steps, who: who ?? self.who))
    }

    func pushLoop(_ steps: [Step], times: Int?, until: [Condition], seconds: Double?) {
        guard stack.count < 64 else { return }
        var f = Frame(steps: steps, who: who, timesLeft: times.map { $0 - 1 }, until: until,
                      endTime: seconds.map { perf.clock + $0 }, isLoop: true)
        for c in until { if case .key(let k) = c { perf.grabKey(k); f.grabbedKeys.append(k) } }
        stack.append(f)
    }

    private func pop() {
        stack.popLast()?.grabbedKeys.forEach(perf.releaseKey)
    }

    func cancel() {
        current?.cancel()
        current = nil
        while !stack.isEmpty { pop() }
        done = true
    }

    func advance(_ dt: TimeInterval) {
        guard !done else { return }
        // A loop's `until`/`for` ends it at once, even mid-step.
        if let i = stack.firstIndex(where: { f in
            f.isLoop && (f.until.contains(where: perf.matches) || (f.endTime.map { perf.clock >= $0 } ?? false))
        }) {
            current?.cancel()
            current = nil
            while stack.count > i { pop() }
        }
        var dt = dt
        var budget = 200
        while budget > 0 {
            budget -= 1
            if let run = current {
                if run.tick(dt, self) { current = nil } else { return }
                dt = 0
                continue
            }
            guard var top = stack.last else { done = true; return }
            if top.index >= top.steps.count {
                if top.isLoop, (top.timesLeft ?? 1) > 0, !top.steps.isEmpty {
                    top.index = 0
                    if let t = top.timesLeft { top.timesLeft = t - 1 }
                    stack[stack.count - 1] = top
                    return  // One pass per frame at most, so empty loops can't spin.
                }
                pop()
                continue
            }
            let step = top.steps[top.index]
            stack[stack.count - 1].index += 1
            current = begin(step)
        }
    }

    // MARK: Steps

    /// Does an instant step now, or returns the ongoing run for a timed one.
    private func begin(_ step: Step) -> StepRun? {
        let perf = self.perf
        func actor(_ who: String?) -> CastMember? { perf.actor(who ?? self.who) }
        switch step {
        case .walk(let who, let to, let speed, let backwards, let clip):
            guard let a = actor(who), let x = perf.evalX(to, for: a) else { return nil }
            return WalkRun(actor: a, x: x, speed: CGFloat(speed) * perf.P, backwards: backwards,
                           clip: clip.flatMap { perf.catalog.clips[$0] })
        case .hop(let who, let to, let height, let time):
            guard let a = actor(who) else { return nil }
            let target = CGPoint(x: perf.evalX(to?.x, for: a) ?? a.x, y: perf.evalY(to?.y, for: a) ?? a.y)
            return HopRun(actor: a, to: target, height: CGFloat(height) * perf.P, time: max(0.1, time))
        case .place(let who, let at):
            guard let a = actor(who) else { return nil }
            if let x = perf.evalX(at.x, for: a) { a.x = x }
            if let y = perf.evalY(at.y, for: a) { a.y = y }
        case .face(let who, let target):
            guard let a = actor(who) else { return nil }
            switch target {
            case "left": a.facing = -1
            case "right": a.facing = 1
            case "turn": a.facing = -a.facing
            case "cursor": if let m = perf.stage.mouse { a.facing = m.x >= a.x ? 1 : -1 }
            default:
                if let x = perf.evalX(PosExpr(base: target, offset: 0), for: a), abs(x - a.x) > 1 { a.facing = x >= a.x ? 1 : -1 }
            }
        case .pose(let who, let spec):
            actor(who)?.basePose = spec
        case .play(let who, let id, let times):
            guard let a = actor(who), let clip = perf.catalog.clips[id] else { return nil }
            a.clip = clip
            a.clipTime = 0
            a.clipLastFrame = -1
            if clip.loop && times == nil { return nil }  // Keeps looping while the script moves on.
            return WaitRun(seconds: clip.duration * Double(max(1, times ?? 1))) { [weak a] in
                if a?.clip?.id == id { a?.clip = nil }
            }
        case .stopClip(let who):
            actor(who)?.clip = nil
        case .wait(let s):
            return WaitRun(seconds: s)
        case .hide(let who, let hide):
            actor(who)?.hidden = hide
        case .say(let who, let text, let time):
            guard let a = actor(who) else { return nil }
            a.sayText = perf.fill(text)
            a.sayUntil = perf.clock + time
            return WaitRun(seconds: time)
        case .effect(let fx, let at):
            let name = at ?? who
            if let name, let p = perf.props[name] {
                perf.playEffect(fx, at: nil, prop: p)
            } else {
                perf.playEffect(fx, at: actor(name))
            }
        case .prop(let op):
            return propStep(op)
        case .ride(let who, let prop, let offset):
            guard let a = actor(who) else { return nil }
            a.riding = prop.map { ($0, offset) }
        case .wear(let who, let id, let on):
            guard let a = actor(who) else { return nil }
            if on { if !a.extraAccessories.contains(id) { a.extraAccessories.append(id) } } else { a.extraAccessories.removeAll { $0 == id } }
        case .together(let tracks):
            return TogetherRun(tracks: tracks.map { TrackRun(steps: $0.steps, who: $0.who ?? who, perf: perf) })
        case .loop(let steps, let times, let until, let seconds):
            pushLoop(steps, times: times, until: until, seconds: seconds)
        case .waitFor(let c, let timeout, let then, let orElse):
            return WaitForRun(conditions: c, timeout: timeout, then: then, orElse: orElse, perf: perf)
        case .random(let choices):
            if let pick = choices.randomElement() { push(pick) }
        case .call(let id):
            if let target = perf.catalog.activities[id] { push(target.steps) }
        case .puppet(let who, let spec):
            guard let a = actor(who) else { return nil }
            return PuppetRun(actor: a, spec: spec, perf: perf)
        case .leave(let who):
            if let a = actor(who) { perf.dismiss(a) }
        case .when(let cond, let a, let b):
            push(ExtrasConditions.evaluate(cond, stage: perf.stage) ? a : b)
        case .async(let inner):
            perf.spawn([inner], who: who)
        case .openApp(let app):
            perf.director.openApp(app)
        }
        return nil
    }

    private func propStep(_ op: PropOp) -> StepRun? {
        guard let p = perf.props[op.name] else { return nil }
        let star = perf.actor(who)
        if let show = op.show {
            if !p.visible && show.x == nil && show.y == nil { p.x = perf.stage.bounds.width / 2; p.y = perf.stage.groundY }
            if let x = perf.evalX(show.x, for: star) { p.x = x }
            if let y = perf.evalY(show.y, for: star) { p.y = y }
            if !p.visible && show.y == nil { p.y = perf.stage.groundY }
            p.visible = true
        }
        if op.hide { p.visible = false; p.follow = nil }
        if let f = op.frame { p.frame = f }
        if let z = op.z { p.layer.zPosition = CGFloat(z) }
        if let flip = op.flip { p.flip = flip }
        if let follow = op.follow {
            if let role = follow { p.follow = (role, op.side, op.gap, op.offset) } else { p.follow = nil }
        }
        if let s = op.shake { p.shakeUntil = perf.clock + s; p.shakeAmount = 1 }
        if let m = op.move {
            let to = CGPoint(x: perf.evalX(m.x, for: star) ?? p.x, y: perf.evalY(m.y, for: star) ?? p.y)
            var time = op.time ?? 0.6
            if let speed = op.speed, speed > 0 { time = Double(hypot(to.x - p.x, to.y - p.y) / (CGFloat(speed) * perf.P)) }
            return PropMoveRun(prop: p, to: to, time: max(0.01, time), ease: op.ease)
        }
        return nil
    }
}

// MARK: - Step runs

protocol StepRun: AnyObject {
    /// Returns true when finished.
    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool
    func cancel()
}

extension StepRun {
    func cancel() {}
}

final class WaitRun: StepRun {
    private var left: TimeInterval
    private let onEnd: (() -> Void)?
    init(seconds: TimeInterval, onEnd: (() -> Void)? = nil) {
        left = seconds
        self.onEnd = onEnd
    }
    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        left -= dt
        if left <= 0 { onEnd?(); return true }
        return false
    }
    func cancel() { onEnd?() }
}

final class WalkRun: StepRun {
    let actor: CastMember
    let x: CGFloat
    let speed: CGFloat
    let backwards: Bool
    let clip: Clip?
    private var started = false

    init(actor: CastMember, x: CGFloat, speed: CGFloat, backwards: Bool, clip: Clip?) {
        self.actor = actor
        self.x = x
        self.speed = max(1, speed)
        self.backwards = backwards
        self.clip = clip
    }

    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        if !started, let clip {
            started = true
            actor.clip = clip
            actor.clipTime = 0
        }
        let dx = x - actor.x
        let step = speed * CGFloat(dt)
        if abs(dx) <= step {
            actor.x = x
            end()
            return true
        }
        let dir: CGFloat = dx > 0 ? 1 : -1
        actor.x += dir * step
        actor.facing = backwards ? -dir : dir
        actor.walking = true
        return false
    }

    private func end() { if let clip, actor.clip?.id == clip.id { actor.clip = nil } }
    func cancel() { end() }
}

final class HopRun: StepRun {
    let actor: CastMember
    let from: CGPoint
    let to: CGPoint
    let height: CGFloat
    let time: TimeInterval
    private var t: TimeInterval = 0

    init(actor: CastMember, to: CGPoint, height: CGFloat, time: TimeInterval) {
        self.actor = actor
        from = CGPoint(x: actor.x, y: actor.y)
        self.to = to
        self.height = height
        self.time = time
        if abs(to.x - from.x) > 1 { actor.facing = to.x > from.x ? 1 : -1 }
    }

    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        t += dt
        let k = CGFloat(min(1, t / time))
        actor.x = from.x + (to.x - from.x) * k
        actor.y = from.y + (to.y - from.y) * k + height * 4 * k * (1 - k)
        actor.airborne = k < 1
        return k >= 1
    }
}

final class PropMoveRun: StepRun {
    let prop: PropState
    let from: CGPoint
    let to: CGPoint
    let time: TimeInterval
    let ease: String
    private var t: TimeInterval = 0

    init(prop: PropState, to: CGPoint, time: TimeInterval, ease: String) {
        self.prop = prop
        from = CGPoint(x: prop.x, y: prop.y)
        self.to = to
        self.time = time
        self.ease = ease
    }

    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        t += dt
        let raw = CGFloat(min(1, t / time))
        let k: CGFloat
        switch ease {
        case "linear": k = raw
        case "in": k = raw * raw
        case "out": k = 1 - (1 - raw) * (1 - raw)
        default: k = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        }
        prop.x = from.x + (to.x - from.x) * k
        prop.y = from.y + (to.y - from.y) * k
        return raw >= 1
    }
}

final class TogetherRun: StepRun {
    let tracks: [TrackRun]
    init(tracks: [TrackRun]) { self.tracks = tracks }
    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        for t in tracks { t.advance(dt) }
        return tracks.allSatisfy(\.done)
    }
    func cancel() { tracks.forEach { $0.cancel() } }
}

final class WaitForRun: StepRun {
    let conditions: [Condition]
    let timeout: TimeInterval?
    let then: [Step]
    let orElse: [Step]
    unowned let perf: Performance
    private var t: TimeInterval = 0
    private var released = false

    init(conditions: [Condition], timeout: TimeInterval?, then: [Step], orElse: [Step], perf: Performance) {
        self.conditions = conditions
        self.timeout = timeout
        self.then = then
        self.orElse = orElse
        self.perf = perf
        for c in conditions { if case .key(let k) = c { perf.grabKey(k) } }
    }

    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        t += dt
        if conditions.contains(where: perf.matches) {
            release()
            if !then.isEmpty { track.push(then) }
            return true
        }
        if let timeout, t >= timeout {
            release()
            if !orElse.isEmpty { track.push(orElse) }
            return true
        }
        return false
    }

    private func release() {
        guard !released else { return }
        released = true
        for c in conditions { if case .key(let k) = c { perf.releaseKey(k) } }
    }

    func cancel() { release() }
}

/// Hands a buddy to the arrow keys: ← → walk, ↑ (or space) jumps, ↓ crouches, Esc hands it back.
final class PuppetRun: StepRun {
    let actor: CastMember
    let spec: PuppetSpec
    unowned let perf: Performance
    private var elapsed: TimeInterval = 0
    private var idle: TimeInterval = 0
    private var vy: CGFloat = 0
    private var inAir = false
    private var sub: TrackRun?
    private var keys: [String] = []
    private var ended = false

    static let movementKeys = ["left", "right", "up", "down", "space", "escape"]

    init(actor: CastMember, spec: PuppetSpec, perf: Performance) {
        self.actor = actor
        self.spec = spec
        self.perf = perf
        keys = Array(Set(Self.movementKeys + spec.keys.keys.map(KeyNames.canonical)))
        keys.forEach(perf.grabKey)
        actor.sayText = spec.hint ?? "Arrows to move · Esc to stop"
        actor.sayUntil = perf.clock + 3
    }

    func tick(_ dt: TimeInterval, _ track: TrackRun) -> Bool {
        elapsed += dt
        let pressed = { (k: String) in self.perf.signals.contains(.key(k)) }
        if pressed("escape") || elapsed > spec.timeout || idle > spec.idleTimeout { finish(); return true }
        if !perf.heldKeys.isEmpty || perf.signals.contains(where: { if case .key = $0 { true } else { false } }) { idle = 0 } else { idle += dt }

        if let s = sub {
            s.advance(dt)
            if s.done { sub = nil }
            return false
        }
        for (k, steps) in spec.keys where pressed(KeyNames.canonical(k)) {
            let s = TrackRun(steps: steps, who: actor.role, perf: perf)
            sub = s
            s.advance(0)
            if s.done { sub = nil }
            return false
        }

        let P = perf.P
        let held = perf.heldKeys
        let dir: CGFloat = (held.contains("right") ? 1 : 0) - (held.contains("left") ? 1 : 0)
        let half = 9 * P
        actor.x = min(max(actor.x + dir * CGFloat(spec.speed) * P * CGFloat(dt), half), perf.stage.bounds.width - half)
        if dir != 0 { actor.facing = dir }
        actor.crouching = held.contains("down") && !inAir
        let floor = perf.stage.groundY
        let gravity = 2200 * P / 4
        let jumpKey = spec.keys["space"] == nil ? pressed("space") : false
        if !inAir && (pressed("up") || jumpKey) {
            vy = sqrt(2 * gravity * CGFloat(spec.jump) * P)
            inAir = true
        }
        if inAir {
            vy -= gravity * CGFloat(dt)
            actor.y += vy * CGFloat(dt)
            if actor.y <= floor {
                actor.y = floor
                inAir = false
                vy = 0
            }
        }
        actor.airborne = inAir
        actor.walking = dir != 0 && !inAir
        return false
    }

    private func finish() {
        guard !ended else { return }
        ended = true
        sub?.cancel()
        keys.forEach(perf.releaseKey)
        actor.crouching = false
        actor.y = perf.stage.groundY
    }

    func cancel() { finish() }
}

// MARK: - Speech bubble

enum SpeechBubble {
    private static var cache: [String: PixelCanvas] = [:]

    /// A white pixel box with dark text and a little tail at the bottom.
    static func render(_ text: String, maxWidth: Int) -> PixelCanvas {
        let key = "\(maxWidth)|\(text)"
        if let c = cache[key] { return c }
        let lines = PixelFont.wrap(text, maxWidth: maxWidth, maxLines: 3)
        let textW = max(PixelFont.glyphWidth, lines.map { PixelFont.width(of: $0) }.max() ?? 0)
        let lineH = PixelFont.glyphHeight + 2
        let w = textW + 6, boxH = lines.count * lineH + 3, h = boxH + 3
        var c = PixelCanvas(width: w, height: h)
        c.fill(1, 3, w - 2, boxH, Palette.outline)
        c.fill(0, 4, w, boxH - 2, Palette.outline)
        c.fill(1, 4, w - 2, boxH - 2, Palette.white)
        // Tail
        let tx = w / 2
        c.fill(tx - 1, 2, 3, 2, Palette.outline)
        c.set(tx, 3, Palette.white)
        c.set(tx, 1, Palette.outline)
        for (i, line) in lines.enumerated() {
            let lw = PixelFont.width(of: line)
            PixelFont.draw(line, on: &c, x: (w - lw) / 2, top: h - 3 - i * lineH, color: Palette.eye)
        }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = c
        return c
    }
}
