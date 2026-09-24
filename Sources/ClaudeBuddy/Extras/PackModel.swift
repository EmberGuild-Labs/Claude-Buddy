import AppKit

// The shape of an Extras pack, parsed from JSON. See docs/PACKS.md for the authoring guide.
//
// Everything here is plain data. `ActivityDirector` performs activities, `AccessoryArt` draws
// accessories, `TriggerEngine` watches the clock and apps, and `ExtrasController` wires keys.

/// A position along one axis, like `"right-20"`, `"bed.left+15"`, `"floor"` or `"40%"`.
/// Numbers are art pixels (one buddy pixel, 4 points at Medium size).
struct PosExpr: Equatable {
    /// `nil` = a plain number measured from the left edge (x) or the floor (y).
    var base: String?
    var offset: Double

    static func number(_ n: Double) -> PosExpr { PosExpr(base: nil, offset: n) }

    /// Accepts a number or a string: `base`, `base+n`, `base-n+m`, `n`, `n%`.
    static func parse(_ any: Any?) -> PosExpr? {
        if let n = any as? NSNumber, !(any is Bool) { return .number(n.doubleValue) }
        guard let text = any as? String else { return nil }
        let chars = Array(text.replacingOccurrences(of: " ", with: ""))
        guard !chars.isEmpty else { return nil }
        var i = 0
        var base = ""
        func isNameChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "." || c == "%" || c == ":" }
        // A base is letters/digits/dots/%, plus hyphens that sit inside a word ("fishing-rod").
        while i < chars.count {
            let c = chars[i]
            if isNameChar(c) {
                base.append(c)
            } else if c == "-", !base.isEmpty, i + 1 < chars.count, chars[i + 1].isLetter {
                base.append(c)
            } else {
                break
            }
            i += 1
        }
        var offset = 0.0
        while i < chars.count {
            let sign: Double
            switch chars[i] {
            case "+": sign = 1
            case "-": sign = -1
            default: return nil
            }
            i += 1
            var num = ""
            while i < chars.count, chars[i].isNumber || chars[i] == "." { num.append(chars[i]); i += 1 }
            guard let v = Double(num) else { return nil }
            offset += sign * v
        }
        if base.isEmpty { return PosExpr(base: nil, offset: offset) }
        if let v = Double(base) { return PosExpr(base: nil, offset: v + offset) }
        if base.hasSuffix("%"), Double(base.dropLast()) == nil { return nil }
        return PosExpr(base: base, offset: offset)
    }
}

struct PointExpr: Equatable {
    var x: PosExpr?
    var y: PosExpr?

    static func parse(_ any: Any?) -> PointExpr? {
        if let d = any as? [String: Any] {
            let p = PointExpr(x: PosExpr.parse(d["x"]), y: PosExpr.parse(d["y"]))
            return p.x == nil && p.y == nil ? nil : p
        }
        // A bare value is an x position.
        return PosExpr.parse(any).map { PointExpr(x: $0, y: nil) }
    }
}

/// Part of a buddy pose; anything left nil keeps whatever is underneath.
struct PoseSpec: Equatable {
    var legs: Pose.Legs?
    var eyes: Pose.Eyes?
    var arms: Pose.Arms?
    var prop: Pose.Prop?
    var look: Int?
    var bob: Int?
    var squash: Bool?
    /// "keep" (default), "none", or a built-in hat name.
    var hat: String?
    var accessories: [String]?
    /// Replaces the whole sprite with pack art.
    var art: String?
    /// Degrees; positive rotates forward (the way it faces).
    var angle: Double?
    /// Offset from where the buddy stands, in art pixels.
    var dx: Double?
    var dy: Double?
    var hidden: Bool?

    /// `self` on top of `base`.
    func over(_ base: PoseSpec) -> PoseSpec {
        PoseSpec(legs: legs ?? base.legs, eyes: eyes ?? base.eyes, arms: arms ?? base.arms, prop: prop ?? base.prop,
                 look: look ?? base.look, bob: bob ?? base.bob, squash: squash ?? base.squash, hat: hat ?? base.hat,
                 accessories: (base.accessories ?? []) + (accessories ?? []), art: art ?? base.art,
                 angle: angle ?? base.angle, dx: dx ?? base.dx, dy: dy ?? base.dy, hidden: hidden ?? base.hidden)
    }

    static let presets: [String: PoseSpec] = [
        "stand": PoseSpec(),
        "sit": PoseSpec(legs: .tucked),
        "sleep": PoseSpec(legs: .tucked, eyes: .closed),
        "cheer": PoseSpec(eyes: .happy, arms: .up),
        "jump": PoseSpec(eyes: .wide, arms: .up),
        "wave": PoseSpec(eyes: .happy, arms: .waveHigh),
        "surprised": PoseSpec(eyes: .wide),
        "dizzy": PoseSpec(eyes: .dizzy),
        "hold": PoseSpec(arms: .holdOut),
    ]
}

struct EffectSpec: Equatable {
    /// hearts, confetti, stars, zzz, notes, snow, sparkle, or float (custom art).
    var kind: String
    var art: String?
    var count: Int
    var dx: Double
    var dy: Double
    var time: Double
}

struct ClipFrame: Equatable {
    var pose: PoseSpec
    var time: Double
    var effect: EffectSpec?
}

struct Clip: Equatable {
    let id: String
    var frames: [ClipFrame]
    var loop: Bool
    /// Blend angle and offsets smoothly between frames.
    var tween: Bool
    var duration: Double { frames.reduce(0) { $0 + $1.time } }
}

/// What's waited for by `waitFor` and `loop … until`.
enum Condition: Equatable {
    case click(role: String?)
    case key(String)
    case again
    case never

    static func parse(_ any: Any?) -> Condition? {
        guard let s = (any as? String)?.lowercased() else { return nil }
        if s == "click" { return .click(role: nil) }
        if s.hasPrefix("click:") { return .click(role: String(s.dropFirst(6))) }
        if s.hasPrefix("key:") { return KeyNames.code(for: String(s.dropFirst(4))) == nil ? nil : .key(String(s.dropFirst(4))) }
        if s == "again" { return .again }
        if s == "never" || s == "forever" { return .never }
        return nil
    }

    /// One condition, or a list where any of them will do: ["click", "again"].
    static func parseList(_ any: Any?) -> [Condition]? {
        if let list = any as? [Any] {
            let parsed = list.compactMap(parse)
            return parsed.count == list.count && !parsed.isEmpty ? parsed : nil
        }
        return parse(any).map { [$0] }
    }
}

/// Where a prop goes relative to the buddy it follows.
enum FollowSide: String { case behind, ahead, offset }

struct PropOp: Equatable {
    var name: String
    var show: PointExpr?
    var hide = false
    var frame: String?
    var z: Double?
    var flip: Bool?
    var follow: String??          // .some(nil) = stop following
    var side = FollowSide.behind
    var gap: Double = 1
    var offset: PointExpr?
    var shake: Double?
    var move: PointExpr?
    var time: Double?
    var speed: Double?
    var ease = "inOut"
}

struct PuppetSpec: Equatable {
    var speed: Double = 40
    var jump: Double = 18
    var timeout: Double = 180
    var idleTimeout: Double = 45
    var hint: String?
    var keys: [String: [Step]] = [:]
}

/// One line of an activity script.
indirect enum Step: Equatable {
    case walk(who: String?, to: PosExpr, speed: Double, backwards: Bool, clip: String?)
    case hop(who: String?, to: PointExpr?, height: Double, time: Double)
    case place(who: String?, at: PointExpr)
    case face(who: String?, target: String)
    case pose(who: String?, PoseSpec)
    case play(who: String?, clip: String, times: Int?)
    case stopClip(who: String?)
    case wait(Double)
    case hide(who: String?, Bool)
    case say(who: String?, text: String, time: Double)
    case effect(EffectSpec, at: String?)
    case prop(PropOp)
    case ride(who: String?, prop: String?, offset: PointExpr?)
    case wear(who: String?, String, Bool)
    case together([Track])
    case loop([Step], times: Int?, until: [Condition], seconds: Double?)
    case waitFor([Condition], timeout: Double?, orElse: [Step])
    case random([[Step]])
    case call(String)
    case puppet(who: String?, PuppetSpec)
    case leave(who: String?)
    case when(String, then: [Step], orElse: [Step])
    /// Runs in the background while the script moves on.
    case async(Step)
}

struct Track: Equatable {
    var who: String?
    var steps: [Step]
}

struct RoleSpec: Equatable {
    enum Who: String { case main, other, any }
    enum IfMissing: String { case summon, unavailable, skip }
    var name: String
    var who: Who
    var ifMissing: IfMissing
    var hat: Hat?
}

struct PropSpec: Equatable {
    var art: String
    var z: Double
}

struct ActivityDef: Equatable {
    let id: String
    var title: String
    var cast: [RoleSpec]
    var props: [String: PropSpec]
    var steps: [Step]
    var inMenu: Bool
    /// End with a little wave (default) or go straight back to normal.
    var greetAtEnd: Bool
    var pack: String

    var starRole: String { cast.first?.name ?? "star" }
}

/// A run request: another activity, inline steps, or just something to say.
struct ActionSpec: Equatable {
    var run: String?
    var steps: [Step]?
    var say: String?

    var label: String { run ?? (say.map { "say “\($0)”" } ?? "custom steps") }
}

struct BindingDef: Equatable {
    var keys: String?
    var sequence: [String]?
    var action: ActionSpec
    var pack: String
}

struct TriggerDef: Equatable {
    enum Kind: Equatable {
        case at(hour: Int, minute: Int)
        case every(seconds: Double)
        case app(event: String, match: String)
        case startup
        case wake
        case claude(event: String, tool: String?)
    }
    var kind: Kind
    var days: Set<Int>?          // Calendar weekdays, 1 = Sunday
    var between: (Int, Int)?     // Minutes since midnight, start…end
    var cooldown: Double
    var chance: Double
    /// Wait this long after the trigger fires (e.g. let the "finished" celebration play first).
    var delay: Double = 0
    /// A condition checked when it's time to run (`busy`, `not:music`, …), like an `if` step.
    var condition: String?
    var action: ActionSpec
    var pack: String
    var index: Int

    static func == (a: TriggerDef, b: TriggerDef) -> Bool {
        a.kind == b.kind && a.days == b.days && a.between?.0 == b.between?.0 && a.between?.1 == b.between?.1
            && a.cooldown == b.cooldown && a.chance == b.chance && a.action == b.action && a.pack == b.pack && a.index == b.index
            && a.delay == b.delay && a.condition == b.condition
    }

    /// Stable across launches, for remembering "already fired today".
    var key: String { "\(pack)#\(index)" }
}

struct ArtDef {
    var width: Int
    var height: Int
    var frames: [String: PixelCanvas]
    var defaultFrame: String
}

struct AccessoryDef {
    enum Slot: String { case head, face, held, back, body }
    var id: String
    var title: String
    var slot: Slot
    var canvas: PixelCanvas
    var dx: Int
    var dy: Int
    var pack: String
}

struct Pack {
    var id: String
    var name: String
    var file: URL?
    var art: [String: ArtDef] = [:]
    var accessories: [String: AccessoryDef] = [:]
    var clips: [String: Clip] = [:]
    var activities: [String: ActivityDef] = [:]
    var bindings: [BindingDef] = []
    var triggers: [TriggerDef] = []
    var problems: [String] = []
}

// MARK: - Parsing

/// Reads a pack's JSON into a `Pack`, collecting readable problems instead of failing outright.
struct PackParser {
    private(set) var problems: [String] = []
    private let packID: String
    private let baseURL: URL?
    private var palette: [Character: RGBA] = [:]

    static func parse(data: Data, file: URL?, fallbackID: String) -> Pack {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] else {
            var p = Pack(id: fallbackID, name: fallbackID, file: file)
            p.problems = ["Not valid JSON (check for a missing comma or quote)."]
            return p
        }
        let id = json["id"] as? String ?? fallbackID
        var parser = PackParser(packID: id, baseURL: file?.deletingLastPathComponent())
        return parser.pack(json, file: file)
    }

    private init(packID: String, baseURL: URL?) {
        self.packID = packID
        self.baseURL = baseURL
    }

    private mutating func problem(_ s: String) { problems.append(s) }

    private mutating func pack(_ json: [String: Any], file: URL?) -> Pack {
        var pack = Pack(id: packID, name: json["name"] as? String ?? packID, file: file)
        palette = colors(json["palette"], context: "palette")
        for (name, value) in json["art"] as? [String: Any] ?? [:] {
            if let a = art(value, context: "art \(name)") { pack.art[name] = a }
        }
        for (name, value) in json["accessories"] as? [String: Any] ?? [:] {
            if let a = accessory(name, value) { pack.accessories[name] = a }
        }
        for (name, value) in json["clips"] as? [String: Any] ?? [:] {
            if let c = clip(name, value) { pack.clips[name] = c }
        }
        for (name, value) in json["activities"] as? [String: Any] ?? [:] {
            if let a = activity(name, value) { pack.activities[name] = a }
        }
        for (i, value) in (json["bindings"] as? [Any] ?? []).enumerated() {
            if let b = binding(value, context: "binding \(i + 1)") { pack.bindings.append(b) }
        }
        for (i, value) in (json["triggers"] as? [Any] ?? []).enumerated() {
            if let t = trigger(value, index: i) { pack.triggers.append(t) }
        }
        let known: Set = ["id", "name", "version", "author", "description", "palette", "art", "accessories", "clips",
                          "activities", "bindings", "triggers", "$schema", "comment", "_comment"]
        for key in json.keys where !known.contains(key) { problem("Unknown top-level key “\(key)”.") }
        pack.problems = problems
        return pack
    }

    // MARK: Colors and art

    static let namedColors: [String: RGBA] = [
        "body": Palette.body, "bodyDark": Palette.bodyDark, "bodyLight": Palette.bodyLight, "eye": Palette.eye,
        "white": Palette.white, "black": Palette.black, "outline": Palette.outline, "steel": Palette.steel,
        "steelDark": Palette.steelDark, "wood": Palette.wood, "glass": Palette.glass, "heart": Palette.heart,
        "star": Palette.star, "cream": Palette.cream, "red": HatPalette.red, "green": HatPalette.green,
        "blue": HatPalette.blue, "yellow": HatPalette.yellow, "pink": HatPalette.pink, "gold": HatPalette.gold,
        "brown": HatPalette.brown, "tan": HatPalette.tan, "purple": HatPalette.purple, "cyan": HatPalette.cyan,
    ]

    static func color(_ s: String) -> RGBA? {
        if let named = namedColors[s] { return named }
        var hex = s.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let v = UInt32(hex, radix: 16) else { return nil }
        return hex.count == 8 ? RGBA(hex: v >> 8, a: UInt8(v & 0xFF)) : RGBA(hex: v)
    }

    private mutating func colors(_ any: Any?, context: String) -> [Character: RGBA] {
        var map: [Character: RGBA] = [:]
        for (k, v) in any as? [String: String] ?? [:] {
            guard k.count == 1, let ch = k.first else { problem("\(context): color keys must be one character (“\(k)”)."); continue }
            if let c = Self.color(v) { map[ch] = c } else { problem("\(context): “\(v)” isn't a color (use #RRGGBB or a name like “body”).") }
        }
        return map
    }

    /// Rows of characters (top row first), each character mapped to a color; "." and " " are clear.
    private mutating func canvas(rows any: Any?, colors: [Character: RGBA], context: String) -> PixelCanvas? {
        if let rows = any as? [String], !rows.isEmpty {
            let map = palette.merging(colors) { $1 }
            for row in rows {
                for ch in row where ch != "." && ch != " " && map[ch] == nil {
                    problem("\(context): no color for “\(ch)”.")
                    return nil
                }
            }
            return PixelCanvas.from(rows, map)
        }
        if let file = any as? String {
            guard let baseURL else { problem("\(context): PNG art only works in pack files."); return nil }
            let url = baseURL.appendingPathComponent(file)
            guard let c = PixelCanvas.load(png: url) else { problem("\(context): couldn't read \(file)."); return nil }
            return c
        }
        problem("\(context): needs “rows” (a list of strings) or “png”.")
        return nil
    }

    private mutating func art(_ any: Any?, context: String) -> ArtDef? {
        guard let d = any as? [String: Any] else { problem("\(context): should be an object."); return nil }
        let local = colors(d["colors"], context: context)
        var frames: [String: PixelCanvas] = [:]
        var first: String?
        if let rowsOrPNG = d["rows"] ?? d["png"] {
            if let c = canvas(rows: rowsOrPNG, colors: local, context: context) { frames["default"] = c; first = "default" }
        }
        if let fs = d["frames"] as? [String: Any] {
            for (name, v) in fs.sorted(by: { $0.key < $1.key }) {
                if let c = canvas(rows: v, colors: local, context: "\(context) frame \(name)") {
                    frames[name] = c
                    first = first ?? name
                }
            }
        }
        guard let first, let size = frames[first] else {
            if frames.isEmpty && problems.last?.hasPrefix(context) != true { problem("\(context): has no pixels.") }
            return nil
        }
        let w = frames.values.map(\.width).max() ?? size.width, h = frames.values.map(\.height).max() ?? size.height
        let initial = (d["frame"] as? String).flatMap { frames[$0] != nil ? $0 : nil } ?? first
        return ArtDef(width: w, height: h, frames: frames, defaultFrame: initial)
    }

    private mutating func accessory(_ id: String, _ any: Any?) -> AccessoryDef? {
        let ctx = "accessory \(id)"
        guard let d = any as? [String: Any] else { problem("\(ctx): should be an object."); return nil }
        guard let slot = AccessoryDef.Slot(rawValue: d["slot"] as? String ?? "head") else {
            problem("\(ctx): slot must be head, face, held, back or body."); return nil
        }
        guard let c = canvas(rows: d["rows"] ?? d["png"], colors: colors(d["colors"], context: ctx), context: ctx) else { return nil }
        let off = d["offset"] as? [Int] ?? []
        return AccessoryDef(id: id, title: d["title"] as? String ?? id, slot: slot, canvas: c,
                            dx: off.first ?? 0, dy: off.count > 1 ? off[1] : 0, pack: packID)
    }

    // MARK: Poses and clips

    private mutating func poseSpec(_ any: Any?, context: String) -> PoseSpec? {
        if let name = any as? String {
            guard let p = PoseSpec.presets[name] else {
                problem("\(context): unknown pose “\(name)” (try \(PoseSpec.presets.keys.sorted().joined(separator: ", "))).")
                return nil
            }
            return p
        }
        guard let d = any as? [String: Any] else { problem("\(context): pose should be a name or an object."); return nil }
        return poseFields(d, context: context)
    }

    private mutating func poseFields(_ d: [String: Any], context: String) -> PoseSpec {
        var p = PoseSpec()
        func pick<T: RawRepresentable & CaseIterable>(_ key: String, _: T.Type) -> T? where T.RawValue == String {
            guard let raw = d[key] as? String else { return nil }
            if let v = T(rawValue: raw) { return v }
            problem("\(context): \(key) “\(raw)” isn't one of \(T.allCases.map(\.rawValue).joined(separator: ", ")).")
            return nil
        }
        p.legs = pick("legs", Pose.Legs.self)
        p.eyes = pick("eyes", Pose.Eyes.self)
        p.arms = pick("arms", Pose.Arms.self)
        p.prop = pick("prop", Pose.Prop.self)
        p.look = (d["look"] as? NSNumber)?.intValue
        p.bob = (d["bob"] as? NSNumber)?.intValue
        p.squash = d["squash"] as? Bool
        if let h = d["hat"] as? String {
            if h == "keep" || h == "none" || Hat(rawValue: h) != nil { p.hat = h } else { problem("\(context): unknown hat “\(h)”.") }
        }
        if let a = d["accessories"] as? [String] { p.accessories = a } else if let a = d["accessories"] as? String { p.accessories = [a] }
        p.art = d["art"] as? String
        p.angle = (d["angle"] as? NSNumber)?.doubleValue
        p.dx = (d["dx"] as? NSNumber)?.doubleValue
        p.dy = (d["dy"] as? NSNumber)?.doubleValue
        p.hidden = d["hidden"] as? Bool
        return p
    }

    private mutating func effect(_ any: Any?, context: String) -> EffectSpec? {
        let kinds: Set = ["hearts", "confetti", "stars", "zzz", "notes", "snow", "sparkle", "float"]
        var d = any as? [String: Any] ?? [:]
        if let s = any as? String { d = ["kind": s] }
        guard let kind = d["kind"] as? String ?? d["effect"] as? String, kinds.contains(kind) else {
            problem("\(context): effect should be one of \(kinds.sorted().joined(separator: ", ")).")
            return nil
        }
        if kind == "float" && d["art"] == nil { problem("\(context): a float effect needs “art”."); return nil }
        return EffectSpec(kind: kind, art: d["art"] as? String, count: (d["count"] as? NSNumber)?.intValue ?? 3,
                          dx: (d["dx"] as? NSNumber)?.doubleValue ?? 4, dy: (d["dy"] as? NSNumber)?.doubleValue ?? 10,
                          time: (d["time"] as? NSNumber)?.doubleValue ?? 1.2)
    }

    private mutating func clip(_ id: String, _ any: Any?) -> Clip? {
        let ctx = "clip \(id)"
        guard let d = any as? [String: Any], let frames = d["frames"] as? [Any], !frames.isEmpty else {
            problem("\(ctx): needs a list of “frames”."); return nil
        }
        let defaultTime = (d["frameTime"] as? NSNumber)?.doubleValue ?? (d["fps"] as? NSNumber).map { 1 / max(0.5, $0.doubleValue) } ?? 0.12
        var out: [ClipFrame] = []
        for (i, f) in frames.enumerated() {
            let fctx = "\(ctx) frame \(i + 1)"
            let fd: [String: Any]
            if let s = f as? String {
                guard let preset = PoseSpec.presets[s] else { problem("\(fctx): unknown pose “\(s)”."); continue }
                out.append(ClipFrame(pose: preset, time: defaultTime, effect: nil))
                continue
            } else if let obj = f as? [String: Any] { fd = obj } else { problem("\(fctx): should be an object."); continue }
            var pose = PoseSpec()
            if let preset = fd["pose"] { pose = poseSpec(preset, context: fctx) ?? pose }
            pose = poseFields(fd, context: fctx).over(pose)
            let fx = fd["effect"].flatMap { effect($0, context: fctx) }
            out.append(ClipFrame(pose: pose, time: max(0.02, (fd["time"] as? NSNumber)?.doubleValue ?? defaultTime), effect: fx))
        }
        guard !out.isEmpty else { return nil }
        return Clip(id: id, frames: out, loop: d["loop"] as? Bool ?? false, tween: d["tween"] as? Bool ?? false)
    }

    // MARK: Activities

    private mutating func activity(_ id: String, _ any: Any?) -> ActivityDef? {
        let ctx = "activity \(id)"
        var d = any as? [String: Any] ?? [:]
        if let list = any as? [Any] { d = ["steps": list] }  // Shorthand: just the steps.
        guard let rawSteps = d["steps"] as? [Any] else { problem("\(ctx): needs “steps”."); return nil }
        var cast: [RoleSpec] = []
        if let list = d["cast"] as? [Any] {
            for (i, r) in list.enumerated() {
                var rd = r as? [String: Any] ?? [:]
                if let name = r as? String { rd = ["role": name] }
                let name = rd["role"] as? String ?? rd["name"] as? String ?? (i == 0 ? "star" : "friend\(i)")
                let who = RoleSpec.Who(rawValue: rd["who"] as? String ?? (i == 0 ? "main" : "other"))
                let missing = RoleSpec.IfMissing(rawValue: rd["ifMissing"] as? String ?? "summon")
                if who == nil { problem("\(ctx): role \(name): who must be main, other or any.") }
                if missing == nil { problem("\(ctx): role \(name): ifMissing must be summon, unavailable or skip.") }
                cast.append(RoleSpec(name: name, who: who ?? .any, ifMissing: missing ?? .summon,
                                     hat: (rd["hat"] as? String).flatMap(Hat.init(rawValue:))))
            }
        }
        if cast.isEmpty { cast = [RoleSpec(name: "star", who: .main, ifMissing: .summon, hat: nil)] }
        if Set(cast.map(\.name)).count != cast.count { problem("\(ctx): role names must be different.") }
        var props: [String: PropSpec] = [:]
        for (name, v) in d["props"] as? [String: Any] ?? [:] {
            if let artName = v as? String { props[name] = PropSpec(art: artName, z: -1); continue }
            guard let pd = v as? [String: Any], let artName = pd["art"] as? String else { problem("\(ctx): prop \(name) needs “art”."); continue }
            props[name] = PropSpec(art: artName, z: zValue(pd["z"]) ?? -1)
        }
        let steps = self.steps(rawSteps, context: ctx)
        return ActivityDef(id: id, title: d["title"] as? String ?? id, cast: cast, props: props, steps: steps,
                           inMenu: d["menu"] as? Bool ?? true, greetAtEnd: (d["endWith"] as? String ?? "wave") != "none", pack: packID)
    }

    private func zValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        switch any as? String {
        case "front": return 2
        case "back", "behind": return -1
        case "over": return 1
        default: return nil
        }
    }

    mutating func steps(_ list: [Any], context: String) -> [Step] {
        list.enumerated().compactMap { i, s in step(s, context: "\(context) step \(i + 1)") }
    }

    private static let actionKeys = ["walk", "run", "hop", "place", "face", "pose", "play", "stop", "wait", "hide", "show", "say",
                                     "effect", "prop", "ride", "wear", "unwear", "together", "loop", "waitFor", "random", "call",
                                     "puppet", "leave", "if"]

    private mutating func step(_ any: Any, context ctx: String) -> Step? {
        guard let d = any as? [String: Any] else { problem("\(ctx): should be an object like {\"walk\": \"center\"}."); return nil }
        let actions = Self.actionKeys.filter { d[$0] != nil }
        guard let action = actions.first else {
            problem("\(ctx): no action (use one of \(Self.actionKeys.joined(separator: ", "))).")
            return nil
        }
        // “prop” can be combined with prop-only keys, and "hide"/"show" belong to it there.
        if actions.count > 1 && action != "prop" && !(actions.contains("prop")) {
            problem("\(ctx): one action per step (found \(actions.joined(separator: ", "))).")
        }
        let who = d["who"] as? String
        let num = { (key: String) in (d[key] as? NSNumber)?.doubleValue }
        var result: Step?
        switch actions.contains("prop") ? "prop" : action {
        case "walk", "run":
            guard let to = PosExpr.parse(d[action]) else { problem("\(ctx): \(action) needs a position like \"center\" or \"left+20\"."); return nil }
            result = .walk(who: who, to: to, speed: num("speed") ?? (action == "run" ? 60 : 30),
                           backwards: d["backwards"] as? Bool ?? false, clip: d["clip"] as? String)
        case "hop":
            let to = d["hop"] is Bool ? nil : PointExpr.parse(d["hop"])
            if !(d["hop"] is Bool) && to == nil && !(d["hop"] as? String == "here") { problem("\(ctx): hop needs true or a position."); return nil }
            result = .hop(who: who, to: to, height: num("height") ?? 14, time: num("time") ?? 0.5)
        case "place":
            guard let at = PointExpr.parse(d["place"]) else { problem("\(ctx): place needs a position."); return nil }
            result = .place(who: who, at: at)
        case "face":
            guard let t = d["face"] as? String else { problem("\(ctx): face needs left, right, cursor, turn, or a role/prop name."); return nil }
            result = .face(who: who, target: t)
        case "pose":
            guard let p = poseSpec(d["pose"], context: ctx) else { return nil }
            result = .pose(who: who, p)
        case "play":
            guard let c = d["play"] as? String else { problem("\(ctx): play needs a clip name."); return nil }
            result = .play(who: who, clip: c, times: (d["times"] as? NSNumber)?.intValue)
        case "stop":
            result = .stopClip(who: who)
        case "wait":
            guard let s = num("wait") else { problem("\(ctx): wait needs seconds."); return nil }
            result = .wait(max(0, s))
        case "hide", "show":
            result = .hide(who: who, action == "hide")
        case "say":
            guard let text = d["say"] as? String else { problem("\(ctx): say needs text."); return nil }
            result = .say(who: who, text: text, time: num("time") ?? min(6, 1.2 + Double(text.count) * 0.06))
        case "effect":
            guard let fx = effect(d["effect"] is String ? d : d["effect"], context: ctx) else { return nil }
            result = .effect(fx, at: d["at"] as? String ?? who)
        case "prop":
            result = propStep(d, context: ctx)
        case "ride":
            result = .ride(who: who, prop: d["ride"] as? String, offset: PointExpr.parse(d["offset"]))
        case "wear", "unwear":
            guard let a = d[action] as? String else { problem("\(ctx): \(action) needs an accessory name."); return nil }
            result = .wear(who: who, a, action == "wear")
        case "together":
            guard let list = d["together"] as? [Any], !list.isEmpty else { problem("\(ctx): together needs a list of tracks."); return nil }
            result = .together(list.enumerated().compactMap { i, t in track(t, context: "\(ctx) track \(i + 1)") })
        case "loop":
            guard let list = d["loop"] as? [Any] else { problem("\(ctx): loop needs a list of steps."); return nil }
            let until = d["until"].flatMap { u -> [Condition]? in
                let c = Condition.parseList(u)
                if c == nil { problem("\(ctx): until should be click, click:<role>, key:<name>, again, never, or a list of those.") }
                return c
            } ?? []
            let times = (d["times"] as? NSNumber)?.intValue
            if times == nil && until.isEmpty && num("for") == nil { problem("\(ctx): loop needs times, until, or for (seconds).") ; return nil }
            result = .loop(steps(list, context: ctx), times: times, until: until, seconds: num("for"))
        case "waitFor":
            guard let c = Condition.parseList(d["waitFor"]) else { problem("\(ctx): waitFor should be click, click:<role>, key:<name>, again, never, or a list of those."); return nil }
            result = .waitFor(c, timeout: num("timeout"), orElse: steps(d["else"] as? [Any] ?? [], context: ctx + " else"))
        case "random":
            guard let options = d["random"] as? [Any], !options.isEmpty else { problem("\(ctx): random needs a list of choices."); return nil }
            result = .random(options.enumerated().map { i, o in
                if let list = o as? [Any] { return steps(list, context: "\(ctx) choice \(i + 1)") }
                return step(o, context: "\(ctx) choice \(i + 1)").map { [$0] } ?? []
            })
        case "call":
            guard let id = d["call"] as? String else { problem("\(ctx): call needs an activity name."); return nil }
            result = .call(id)
        case "puppet":
            let pd = d["puppet"] as? [String: Any] ?? [:]
            var spec = PuppetSpec()
            if let v = pd["speed"] as? NSNumber { spec.speed = v.doubleValue }
            if let v = pd["jump"] as? NSNumber { spec.jump = v.doubleValue }
            if let v = pd["timeout"] as? NSNumber { spec.timeout = v.doubleValue }
            if let v = pd["idleTimeout"] as? NSNumber { spec.idleTimeout = v.doubleValue }
            spec.hint = pd["hint"] as? String
            for (key, v) in pd["keys"] as? [String: Any] ?? [:] {
                guard KeyNames.code(for: key) != nil else { problem("\(ctx): puppet key “\(key)” isn't a key name."); continue }
                if ["left", "right", "up", "down", "escape"].contains(key.lowercased()) {
                    problem("\(ctx): puppet key “\(key)” is taken by the movement controls."); continue
                }
                if let list = v as? [Any] { spec.keys[key.lowercased()] = steps(list, context: "\(ctx) key \(key)") }
                else if let one = step(v, context: "\(ctx) key \(key)") { spec.keys[key.lowercased()] = [one] }
            }
            result = .puppet(who: who, spec)
        case "leave":
            result = .leave(who: who)
        case "if":
            guard let cond = d["if"] as? String, ExtrasConditions.isKnown(cond) else {
                problem("\(ctx): if should be one of \(ExtrasConditions.names.joined(separator: ", ")) (or not:<name>).")
                return nil
            }
            result = .when(cond, then: steps(d["then"] as? [Any] ?? [], context: ctx + " then"),
                           orElse: steps(d["else"] as? [Any] ?? [], context: ctx + " else"))
        default:
            return nil
        }
        if d["async"] as? Bool == true, let r = result { return .async(r) }
        return result
    }

    private mutating func track(_ any: Any, context: String) -> Track? {
        if let list = any as? [Any] { return Track(who: nil, steps: steps(list, context: context)) }
        if let d = any as? [String: Any], let list = d["steps"] as? [Any] {
            return Track(who: d["who"] as? String, steps: steps(list, context: context))
        }
        return step(any, context: context).map { Track(who: nil, steps: [$0]) }
    }

    private mutating func propStep(_ d: [String: Any], context ctx: String) -> Step? {
        guard let name = d["prop"] as? String else { problem("\(ctx): prop needs a prop name."); return nil }
        var op = PropOp(name: name)
        if let s = d["show"] {
            op.show = s as? Bool == true ? PointExpr(x: nil, y: nil) : PointExpr.parse(s)
            if op.show == nil { problem("\(ctx): show should be true or a position.") }
        }
        op.hide = d["hide"] as? Bool ?? false
        op.frame = d["frame"] as? String
        op.z = zValue(d["z"])
        op.flip = d["flip"] as? Bool
        if d.keys.contains("follow") {
            op.follow = .some(d["follow"] as? String)
            if let side = d["side"] as? String {
                if let s = FollowSide(rawValue: side) { op.side = s } else { problem("\(ctx): side should be behind, ahead or offset.") }
            }
            if d["offset"] != nil && d["side"] == nil { op.side = .offset }
            op.gap = (d["gap"] as? NSNumber)?.doubleValue ?? 1
        }
        op.offset = PointExpr.parse(d["offset"])
        op.shake = (d["shake"] as? NSNumber)?.doubleValue
        if let m = d["move"] {
            op.move = PointExpr.parse(m)
            if op.move == nil { problem("\(ctx): move needs a position.") }
        }
        op.time = (d["time"] as? NSNumber)?.doubleValue
        op.speed = (d["speed"] as? NSNumber)?.doubleValue
        op.ease = d["ease"] as? String ?? "inOut"
        return .prop(op)
    }

    // MARK: Bindings and triggers

    private mutating func actionSpec(_ d: [String: Any], context: String) -> ActionSpec? {
        let a = ActionSpec(run: d["run"] as? String, steps: (d["steps"] as? [Any]).map { steps($0, context: context) },
                           say: d["say"] as? String)
        if a.run == nil && a.steps == nil && a.say == nil { problem("\(context): needs “run”, “steps”, or “say”."); return nil }
        return a
    }

    private mutating func binding(_ any: Any, context: String) -> BindingDef? {
        guard let d = any as? [String: Any], let action = actionSpec(d, context: context) else {
            if !(any is [String: Any]) { problem("\(context): should be an object.") }
            return nil
        }
        let keys = d["keys"] as? String
        if let keys, KeyCombo.parse(keys) == nil {
            problem("\(context): “\(keys)” isn't a shortcut (like \"ctrl+opt+f\").")
            return nil
        }
        var sequence: [String]?
        if let seq = d["sequence"] as? String {
            let parts = seq.lowercased().split(separator: " ").map(String.init)
            if let bad = parts.first(where: { KeyNames.code(for: $0) == nil }) {
                problem("\(context): “\(bad)” in the sequence isn't a key name.")
                return nil
            }
            if parts.contains("escape") { problem("\(context): escape is reserved (it stops the current activity)."); return nil }
            sequence = parts
        }
        if keys == nil && sequence == nil { problem("\(context): needs “keys” (a shortcut) or “sequence” (after the leader key)."); return nil }
        return BindingDef(keys: keys, sequence: sequence, action: action, pack: packID)
    }

    private static let dayNames: [String: Int] = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]

    static func duration(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        guard var s = (any as? String)?.lowercased().trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        var unit = 1.0
        if s.hasSuffix("h") { unit = 3600; s.removeLast() } else if s.hasSuffix("m") { unit = 60; s.removeLast() }
        else if s.hasSuffix("s") { s.removeLast() }
        return Double(s).map { $0 * unit }
    }

    static func clockTime(_ s: String) -> (Int, Int)? {
        var text = s.lowercased().replacingOccurrences(of: " ", with: "")
        var pm: Bool?
        if text.hasSuffix("am") { pm = false; text.removeLast(2) } else if text.hasSuffix("pm") { pm = true; text.removeLast(2) }
        let parts = text.split(separator: ":").map { Int($0) }
        guard let h0 = parts.first ?? nil, parts.count <= 2 else { return nil }
        let m = parts.count == 2 ? (parts[1] ?? -1) : 0
        var h = h0
        if let pm {
            guard (1...12).contains(h) else { return nil }
            h = h % 12 + (pm ? 12 : 0)
        }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private mutating func trigger(_ any: Any, index: Int) -> TriggerDef? {
        let ctx = "trigger \(index + 1)"
        guard let d = any as? [String: Any] else { problem("\(ctx): should be an object."); return nil }
        guard let action = actionSpec(d, context: ctx) else { return nil }
        var kind: TriggerDef.Kind?
        if let at = d["at"] as? String {
            guard let (h, m) = Self.clockTime(at) else { problem("\(ctx): “\(at)” isn't a time (like \"14:30\" or \"2:30pm\")."); return nil }
            kind = .at(hour: h, minute: m)
        } else if d["every"] != nil {
            guard let s = Self.duration(d["every"]), s >= 60 else { problem("\(ctx): every should be at least \"1m\" (like \"45m\" or \"2h\")."); return nil }
            kind = .every(seconds: s)
        } else if let when = d["when"] as? String {
            switch when {
            case "app-open", "app-launch", "app-activate", "app-quit":
                guard let app = d["app"] as? String, !app.isEmpty else { problem("\(ctx): \(when) needs “app” (a name like \"Xcode\" or a bundle ID)."); return nil }
                kind = .app(event: when, match: app)
            case "startup": kind = .startup
            case "wake": kind = .wake
            case "claude":
                guard let e = d["event"] as? String else { problem("\(ctx): claude triggers need “event” (like \"Stop\")."); return nil }
                kind = .claude(event: e, tool: d["tool"] as? String)
            default:
                problem("\(ctx): when should be app-open, app-launch, app-activate, app-quit, startup, wake, or claude.")
                return nil
            }
        }
        guard let kind else { problem("\(ctx): needs “at”, “every”, or “when”."); return nil }
        var days: Set<Int>?
        if let dd = d["days"] {
            let names: [String]
            switch dd {
            case let s as String where s == "weekdays": names = ["mon", "tue", "wed", "thu", "fri"]
            case let s as String where s == "weekends": names = ["sat", "sun"]
            case let s as String: names = [s]
            case let list as [String]: names = list
            default: names = []
            }
            let nums = names.compactMap { Self.dayNames[String($0.lowercased().prefix(3))] }
            if nums.count != names.count || nums.isEmpty { problem("\(ctx): days should be weekdays, weekends, or a list like [\"mon\", \"wed\"].") }
            days = Set(nums)
        }
        var between: (Int, Int)?
        if let b = d["between"] as? String {
            let parts = b.split(separator: "-").map(String.init)
            if parts.count == 2, let s = Self.clockTime(parts[0]), let e = Self.clockTime(parts[1]) {
                between = (s.0 * 60 + s.1, e.0 * 60 + e.1)
            } else {
                problem("\(ctx): between should look like \"09:00-17:00\".")
            }
        }
        let defaultCooldown: Double
        switch kind {
        case .app(let e, _) where e == "app-activate" || e == "app-open": defaultCooldown = 600
        case .claude: defaultCooldown = 30
        default: defaultCooldown = 0
        }
        let condition = d["if"] as? String
        if let condition, !ExtrasConditions.isKnown(condition) {
            problem("\(ctx): if should be one of \(ExtrasConditions.names.joined(separator: ", ")) (or not:<name>).")
            return nil
        }
        var t = TriggerDef(kind: kind, days: days, between: between, cooldown: Self.duration(d["cooldown"]) ?? defaultCooldown,
                           chance: min(1, max(0, (d["chance"] as? NSNumber)?.doubleValue ?? 1)), action: action, pack: packID, index: index)
        t.delay = max(0, Self.duration(d["delay"]) ?? 0)
        t.condition = condition
        return t
    }
}

/// Named conditions for `if` steps.
enum ExtrasConditions {
    static let names = ["music", "alone", "night", "morning", "afternoon", "evening", "weekend", "busy", "reduce-motion", "chance:<0-1>"]

    static func isKnown(_ s: String) -> Bool {
        let name = s.hasPrefix("not:") ? String(s.dropFirst(4)) : s
        if name.hasPrefix("chance:") { return Double(name.dropFirst(7)) != nil }
        return names.contains(name)
    }

    static func evaluate(_ s: String, stage: BuddyStage, now: Date = Date()) -> Bool {
        if s.hasPrefix("not:") { return !evaluate(String(s.dropFirst(4)), stage: stage, now: now) }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        switch s {
        case "music": return stage.musicPlaying
        case "alone": return stage.buddies.filter { !$0.isLeaving }.count <= 1
        case "night": return hour >= 21 || hour < 6
        case "morning": return (6..<12).contains(hour)
        case "afternoon": return (12..<17).contains(hour)
        case "evening": return (17..<21).contains(hour)
        case "weekend": return cal.isDateInWeekend(now)
        case "busy": return stage.buddies.contains { $0.info.map { $0.activity != .idle } ?? false }
        case "reduce-motion": return stage.reduceMotion
        default:
            if s.hasPrefix("chance:"), let p = Double(s.dropFirst(7)) { return Double.random(in: 0..<1) < p }
            return false
        }
    }
}

extension PixelCanvas {
    /// Reads a PNG pixel-for-pixel (for pack art drawn in an image editor).
    static func load(png url: URL) -> PixelCanvas? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return from(image: img)
    }

    static func from(image img: CGImage) -> PixelCanvas? {
        let w = img.width, h = img.height
        guard w > 0, h > 0, w <= 512, h <= 512 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var c = PixelCanvas(width: w, height: h)
        for row in 0..<h {
            for x in 0..<w {
                let i = (row * w + x) * 4
                guard bytes[i + 3] >= 128 else { continue }
                // Row 0 of the bitmap is the top of the image; canvas y grows upward.
                c.set(x, h - 1 - row, RGBA(hex: UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2])))
            }
        }
        return c
    }
}

extension PackParser {
    /// Steps sent over HTTP (`/claude-buddy/do`), acted out by the main buddy as "star".
    static func adHocSteps(_ list: [Any]) -> ([Step], [String]) {
        var parser = PackParser(packID: "adhoc", baseURL: nil)
        let steps = parser.steps(list, context: "step")
        return (steps, parser.problems)
    }
}
