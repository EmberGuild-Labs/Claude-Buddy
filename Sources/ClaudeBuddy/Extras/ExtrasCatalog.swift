import AppKit

/// Everything the loaded packs define, merged. The built-in pack comes first; user packs
/// (in `~/Library/Application Support/ClaudeBuddy/Packs`) come after it in name order, and a
/// later pack's item replaces an earlier one with the same name.
final class ExtrasCatalog {
    /// What the buddies use right now. Swapped wholesale when packs reload.
    static var current = ExtrasCatalog(packs: [BuiltInPack.load()]) {
        didSet { BuddyArt.clearCache() }
    }

    static var packsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBuddy/Packs", isDirectory: true)
    }

    let packs: [Pack]
    private(set) var art: [String: ArtDef] = [:]
    private(set) var accessories: [String: AccessoryDef] = [:]
    private(set) var clips: [String: Clip] = [:]
    private(set) var activities: [String: ActivityDef] = [:]
    private(set) var bindings: [BindingDef] = []
    private(set) var triggers: [TriggerDef] = []
    /// "pack: message" lines for the menu and `--check-packs`.
    private(set) var problems: [String] = []

    private var imageCache: [String: CGImage] = [:]

    init(packs: [Pack]) {
        self.packs = packs
        art = Self.builtinArt
        for pack in packs {
            problems += pack.problems.map { "\(pack.name): \($0)" }
            art.merge(pack.art) { $1 }
            accessories.merge(pack.accessories) { $1 }
            clips.merge(pack.clips) { $1 }
            activities.merge(pack.activities) { $1 }
            bindings += pack.bindings
            triggers += pack.triggers
        }
        validate()
    }

    /// Loads the built-in pack plus every enabled `.json` in the packs folder.
    static func load(from folder: URL = packsFolder, disabled: Set<String> = []) -> ExtrasCatalog {
        var packs = [BuiltInPack.load()]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let fallback = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }
            let pack = PackParser.parse(data: data, file: url, fallbackID: fallback)
            if disabled.contains(pack.id) { continue }
            packs.append(pack)
        }
        return ExtrasCatalog(packs: packs)
    }

    // MARK: - Images

    func image(art name: String, frame: String? = nil) -> CGImage? {
        guard let a = art[name] else { return nil }
        let f = frame.flatMap { a.frames[$0] != nil ? $0 : nil } ?? a.defaultFrame
        let key = "\(name)|\(f)"
        if let i = imageCache[key] { return i }
        guard let canvas = a.frames[f] else { return nil }
        let i = canvas.cgImage()
        imageCache[key] = i
        return i
    }

    /// Pack art standing in for the whole buddy sprite: centered on the buddy's canvas, feet on
    /// the bottom row, so it lines up with the normal frames.
    func spriteImage(art name: String) -> CGImage? {
        let key = "sprite|\(name)"
        if let i = imageCache[key] { return i }
        guard let a = art[name], let canvas = a.frames[a.defaultFrame] else { return nil }
        var c = PixelCanvas(width: BuddyArt.width, height: BuddyArt.height)
        c.draw(canvas, x: (BuddyArt.width - canvas.width) / 2, y: 0)
        let i = c.cgImage()
        imageCache[key] = i
        return i
    }

    /// Art other packs can reuse: the nap's furniture and the effect sprites.
    private static let builtinArt: [String: ArtDef] = {
        func def(_ frames: [String: CGImage], first: String) -> ArtDef {
            let canvases = frames.compactMapValues { PixelCanvas.from(image: $0) }
            let w = canvases.values.map(\.width).max() ?? 1, h = canvases.values.map(\.height).max() ?? 1
            return ArtDef(width: w, height: h, frames: canvases, defaultFrame: first)
        }
        return [
            "builtin.closet": def(["closed": NapArt.closetClosed, "open": NapArt.closetOpen], first: "closed"),
            "builtin.bed": def(["default": NapArt.bed], first: "default"),
            "builtin.blanket": def(["default": NapArt.blanketImage], first: "default"),
            "builtin.heart": def(["default": BuddyArt.heart], first: "default"),
            "builtin.star": def(["default": BuddyArt.star], first: "default"),
            "builtin.zee": def(["default": BuddyArt.zee], first: "default"),
            "builtin.snowflake": def(["default": BuddyArt.snowflake], first: "default"),
            "builtin.note": def(["default": BuddyArt.notes[0]], first: "default"),
        ]
    }()

    // MARK: - Validation

    /// Checks every name a script refers to, and drops activities that can't run.
    private func validate() {
        var broken: Set<String> = []
        for (id, a) in activities.sorted(by: { $0.key < $1.key }) {
            var issues: [String] = []
            let roles = Set(a.cast.map(\.name))
            var props = a.props
            for (_, p) in props where art[p.art] == nil { issues.append("prop art “\(p.art)” doesn't exist") }
            // Props used by called activities come along too.
            var seen: Set<String> = [id]
            func collectCalls(_ steps: [Step]) {
                forEachStep(steps) { step in
                    if case .call(let c) = step, !seen.contains(c) {
                        seen.insert(c)
                        if let target = activities[c] {
                            props.merge(target.props) { a, _ in a }
                            collectCalls(target.steps)
                        }
                    }
                }
            }
            collectCalls(a.steps)
            forEachStep(a.steps) { step in
                issues += check(step, roles: roles, props: Set(props.keys))
            }
            if !issues.isEmpty {
                broken.insert(id)
                let pack = packs.first { $0.id == a.pack }?.name ?? a.pack
                problems += Array(Set(issues)).sorted().map { "\(pack): activity \(id): \($0)" }
            }
        }
        for id in broken { activities[id] = nil }
        for (id, clip) in clips {
            for f in clip.frames {
                if let name = f.pose.art, art[name] == nil { problems.append("clip \(id): art “\(name)” doesn't exist") }
                for acc in f.pose.accessories ?? [] where accessories[acc] == nil {
                    problems.append("clip \(id): accessory “\(acc)” doesn't exist")
                }
            }
        }
        for b in bindings { if let issue = check(b.action) { problems.append("\(b.pack): binding \(b.keys ?? b.sequence?.joined(separator: " ") ?? ""): \(issue)") } }
        for t in triggers { if let issue = check(t.action) { problems.append("\(t.pack): trigger \(t.index + 1): \(issue)") } }
        bindings.removeAll { check($0.action) != nil }
        triggers.removeAll { check($0.action) != nil }
    }

    /// Problems with steps sent over HTTP (their only role is "star", and there are no props).
    func issues(inAdHoc steps: [Step]) -> [String] {
        var out: [String] = []
        forEachStep(steps) { step in
            out += check(step, roles: ["star"], props: [])
            if case .openApp = step { out.append("openApp isn't allowed over HTTP; put it in a pack") }
        }
        return out
    }

    private func check(_ action: ActionSpec) -> String? {
        if let run = action.run, activities[run] == nil { return "runs “\(run)”, which doesn't exist (or has problems)" }
        if let steps = action.steps {
            var issues: [String] = []
            forEachStep(steps) { issues += check($0, roles: ["star"], props: []) }
            if let first = issues.first { return first }
        }
        return nil
    }

    private static let xBases: Set = ["left", "right", "center", "middle", "here", "start", "cursor", "offleft", "offright", "main",
                                      "ledge", "ledge.left", "ledge.right"]
    private static let yBases: Set = ["floor", "ground", "top", "here", "cursor", "start", "ledge"]

    private func check(_ e: PosExpr?, axis: String, roles: Set<String>, props: Set<String>) -> String? {
        guard let base = e?.base else { return nil }
        if base.hasSuffix("%") { return nil }
        if (axis == "x" ? Self.xBases : Self.yBases).contains(base) { return nil }
        let parts = base.split(separator: ".", maxSplits: 1).map(String.init)
        let name = parts[0], suffix = parts.count > 1 ? parts[1] : nil
        if roles.contains(name) {
            let ok: Set = axis == "x" ? ["x"] : ["y", "head", "feet"]
            return suffix == nil || ok.contains(suffix!) ? nil : "“\(base)”: a buddy has .\(ok.sorted().joined(separator: ", ."))"
        }
        if props.contains(name) {
            let ok: Set = axis == "x" ? ["x", "left", "right", "center"] : ["y", "top", "bottom", "center"]
            return suffix == nil || ok.contains(suffix!) ? nil : "“\(base)”: a prop has .\(ok.sorted().joined(separator: ", ."))"
        }
        return "“\(base)” isn't a position, role, or prop"
    }

    private func check(_ step: Step, roles: Set<String>, props: Set<String>) -> [String] {
        var out: [String] = []
        func role(_ who: String?) { if let who, !roles.contains(who) { out.append("“\(who)” isn't one of the cast (\(roles.sorted().joined(separator: ", ")))") } }
        func prop(_ name: String?) { if let name, !props.contains(name) { out.append("prop “\(name)” isn't in “props”") } }
        func point(_ p: PointExpr?) {
            if let e = check(p?.x, axis: "x", roles: roles, props: props) { out.append(e) }
            if let e = check(p?.y, axis: "y", roles: roles, props: props) { out.append(e) }
        }
        func pose(_ p: PoseSpec) {
            if let a = p.art, art[a] == nil { out.append("art “\(a)” doesn't exist") }
            for acc in p.accessories ?? [] where accessories[acc] == nil { out.append("accessory “\(acc)” doesn't exist") }
        }
        func condition(_ list: [Condition]) { for c in list { if case .click(let r) = c { role(r) } } }
        switch step {
        case .walk(let who, let to, _, _, let clip):
            role(who)
            if let e = check(to, axis: "x", roles: roles, props: props) { out.append(e) }
            if let clip, clips[clip] == nil { out.append("clip “\(clip)” doesn't exist") }
        case .hop(let who, let to, _, _): role(who); point(to)
        case .place(let who, let at): role(who); point(at)
        case .face(let who, let t):
            role(who)
            if !["left", "right", "turn", "cursor"].contains(t) && !roles.contains(t) && !props.contains(t) {
                out.append("face “\(t)”: use left, right, turn, cursor, or a role/prop name")
            }
        case .pose(let who, let p): role(who); pose(p)
        case .play(let who, let clip, _):
            role(who)
            if clips[clip] == nil { out.append("clip “\(clip)” doesn't exist") }
        case .stopClip(let who), .hide(let who, _), .say(let who, _, _), .leave(let who): role(who)
        case .effect(let fx, let at):
            if let at, !roles.contains(at) && !props.contains(at) { out.append("effect at “\(at)”: not a role or prop") }
            if let a = fx.art, art[a] == nil { out.append("art “\(a)” doesn't exist") }
        case .prop(let op):
            prop(op.name)
            point(op.show)
            point(op.move)
            if case .some(.some(let who)) = op.follow { role(who) }
            if let f = op.frame, let p = activitiesPropArt(op.name), art[p]?.frames[f] == nil {
                out.append("prop \(op.name) has no frame “\(f)”")
            }
        case .ride(let who, let p, _): role(who); prop(p)
        case .wear(let who, let acc, _):
            role(who)
            if accessories[acc] == nil { out.append("accessory “\(acc)” doesn't exist") }
        case .loop(_, _, let until, _): condition(until)
        case .waitFor(let c, _, _, _): condition(c)
        case .call(let id): if activities[id] == nil { out.append("calls “\(id)”, which doesn't exist") }
        case .puppet(let who, _): role(who)
        case .together(let tracks): tracks.forEach { role($0.who) }
        case .wait, .random, .when, .async, .openApp: break
        }
        return out
    }

    /// The art a prop name refers to, in whichever activity defines it (for frame checks).
    private func activitiesPropArt(_ name: String) -> String? {
        activities.values.lazy.compactMap { $0.props[name]?.art }.first
    }

    /// Visits every step, including nested ones.
    func forEachStep(_ steps: [Step], _ visit: (Step) -> Void) {
        for s in steps {
            visit(s)
            switch s {
            case .together(let tracks): tracks.forEach { forEachStep($0.steps, visit) }
            case .loop(let inner, _, _, _): forEachStep(inner, visit)
            case .waitFor(_, _, let t, let e): forEachStep(t, visit); forEachStep(e, visit)
            case .random(let choices): choices.forEach { forEachStep($0, visit) }
            case .when(_, let a, let b): forEachStep(a, visit); forEachStep(b, visit)
            case .async(let inner): forEachStep([inner], visit)
            case .puppet(_, let spec): spec.keys.values.forEach { forEachStep($0, visit) }
            default: break
            }
        }
    }
}

/// Draws pack accessories onto a buddy frame (called from `BuddyArt.render`).
enum AccessoryArt {
    static func coversHead(_ ids: [String]) -> Bool {
        guard !ids.isEmpty else { return false }
        let all = ExtrasCatalog.current.accessories
        return ids.contains { all[$0]?.slot == .head }
    }

    static func drawBack(_ ids: [String], on c: inout PixelCanvas, bodyX: Int, bodyWidth: Int, bodyY: Int, top: Int) {
        let all = ExtrasCatalog.current.accessories
        for id in ids {
            guard let a = all[id], a.slot == .back else { continue }
            c.draw(a.canvas, x: bodyX + bodyWidth / 2 - a.canvas.width / 2 + a.dx, y: bodyY + a.dy)
        }
    }

    static func drawFront(_ ids: [String], on c: inout PixelCanvas, bodyX: Int, bodyWidth: Int, bodyY: Int, top: Int,
                          eyeY: Int, handX: Int, handY: Int) {
        let all = ExtrasCatalog.current.accessories
        let center = bodyX + bodyWidth / 2
        for slot in [AccessoryDef.Slot.body, .face, .head, .held] {
            for id in ids {
                guard let a = all[id], a.slot == slot else { continue }
                let w = a.canvas.width, h = a.canvas.height
                switch slot {
                case .head: c.draw(a.canvas, x: center - w / 2 + a.dx, y: top + a.dy)
                case .face: c.draw(a.canvas, x: center - w / 2 + a.dx, y: eyeY + 1 - h / 2 + a.dy)
                case .body: c.draw(a.canvas, x: center - w / 2 + a.dx, y: bodyY + a.dy)
                case .held: c.draw(a.canvas, x: handX + a.dx, y: handY + a.dy)
                case .back: break
                }
            }
        }
    }
}
