import AppKit

/// One frame of the buddy, described by its parts. Frames are drawn on demand and cached.
struct Pose: Hashable {
    enum Legs: String, Hashable, CaseIterable { case stand, stepA, stepB, tucked }
    enum Eyes: String, Hashable, CaseIterable { case open, closed, happy, wide, dizzy }
    enum Arms: String, Hashable, CaseIterable { case down, up, waveHigh, waveLow, typeA, typeB, hammerUp, hammerDown, holdOut }
    enum Prop: String, Hashable, CaseIterable { case none, keyboard, hammerUp, hammerDown, magnifier, antennaA, antennaB }

    var legs = Legs.stand
    var eyes = Eyes.open
    var arms = Arms.down
    var prop = Prop.none
    /// Horizontal eye offset: +1 looks forward, -1 looks back.
    var look = 0
    /// Lifts the body one pixel.
    var bob = 0
    /// Landing squash: wider, shorter body.
    var squash = false
    var hat = Hat.none
    /// Pack accessories (Extras), drawn by `AccessoryArt`. Empty for the built-in looks.
    var accessories: [String] = []
}

/// Procedural pixel art. The buddy faces right; the scene mirrors it to face left.
enum BuddyArt {
    static let width = 32
    static let height = 22
    /// Body centre as a fraction of the canvas height; used as the sprite's rotation anchor.
    static let anchorY: CGFloat = 5.5 / 22

    private static var cache: [Pose: CGImage] = [:]

    static func image(_ pose: Pose) -> CGImage {
        if let i = cache[pose] { return i }
        let i = render(pose).cgImage()
        cache[pose] = i
        return i
    }

    /// Packs were reloaded, so frames with accessories may look different now.
    static func clearCache() { cache.removeAll() }

    static func render(_ p: Pose) -> PixelCanvas {
        var c = PixelCanvas(width: width, height: height)
        let bw = p.squash ? 14 : 12
        let bh = p.squash ? 5 : 7
        let x0 = width / 2 - bw / 2
        let legH = p.legs == .tucked ? 0 : (p.squash ? 1 : 2)
        let y0 = legH + p.bob
        let top = y0 + bh

        // Legs reach from the ground (or one pixel up, when lifted) to the body.
        if p.legs != .tucked {
            for (i, o) in [1, 3, bw - 4, bw - 2].enumerated() {
                let lifted = (p.legs == .stepA && i % 2 == 0) || (p.legs == .stepB && i % 2 == 1)
                let from = lifted ? 1 : 0
                c.fill(x0 + o, from, 1, y0 - from, Palette.body)
            }
        }

        if !p.accessories.isEmpty { AccessoryArt.drawBack(p.accessories, on: &c, bodyX: x0, bodyWidth: bw, bodyY: y0, top: top) }

        // Body
        c.fill(x0, y0, bw, bh, Palette.body)
        c.fill(x0, y0, bw, 1, Palette.bodyDark)
        c.fill(x0 + 1, top - 1, 3, 1, Palette.bodyLight)

        // Arms (left = back arm, right = front arm)
        let lx = x0 - 2, rx = x0 + bw, ay = y0 + 2
        func arm(_ x: Int, _ y: Int, _ w: Int = 2, _ h: Int = 2) { c.fill(x, y, w, h, Palette.body) }
        switch p.arms {
        case .down: arm(lx, ay); arm(rx, ay)
        case .up: arm(lx, top - 2, 2, 4); arm(rx, top - 2, 2, 4)
        case .waveHigh, .hammerUp: arm(lx, ay); arm(rx, top - 2, 2, 4)
        case .waveLow: arm(lx, ay); arm(rx, ay + 2); arm(rx + 2, ay + 3, 1, 2)
        case .typeA: arm(lx, ay); arm(rx, ay - 1, 3, 2)
        case .typeB: arm(lx, ay - 1); arm(rx, ay - 2, 3, 2)
        case .hammerDown: arm(lx, ay); arm(rx, ay, 4, 2)
        case .holdOut: arm(lx, ay); arm(rx, ay + 1, 3, 2)
        }

        // Eyes
        let ey = y0 + (p.squash ? 2 : 3)
        for ex in [x0 + 3 + p.look, x0 + bw - 4 + p.look] {
            switch p.eyes {
            case .open: c.fill(ex, ey, 1, 2, Palette.eye)
            case .closed: c.fill(ex - 1, ey, 3, 1, Palette.eye)
            case .happy:
                c.set(ex - 1, ey, Palette.eye); c.set(ex, ey + 1, Palette.eye); c.set(ex + 1, ey, Palette.eye)
            case .wide:
                c.fill(ex, ey, 2, 2, Palette.eye); c.set(ex, ey + 1, Palette.white)
            case .dizzy:
                for d in [-1, 1] { c.set(ex + d, ey - 1, Palette.eye); c.set(ex + d, ey + 1, Palette.eye) }
                c.set(ex, ey, Palette.eye)
            }
        }

        if !AccessoryArt.coversHead(p.accessories) { p.hat.draw(on: &c, left: x0 + (bw - 12) / 2, top: top) }

        // Props
        switch p.prop {
        case .none: break
        case .keyboard:
            let kx = rx + 1
            c.fill(kx, 0, 8, 2, Palette.keyboard)
            for i in stride(from: 1, to: 8, by: 2) { c.set(kx + i, 1, Palette.key) }
        case .hammerUp:
            c.fill(rx + 1, top + 2, 1, 3, Palette.wood)
            c.fill(rx - 1, top + 5, 5, 2, Palette.steel)
            c.fill(rx - 1, top + 5, 5, 1, Palette.steelDark)
        case .hammerDown:
            c.fill(rx + 4, ay, 3, 1, Palette.wood)
            c.fill(rx + 7, ay - 3, 2, 5, Palette.steel)
            c.fill(rx + 8, ay - 3, 1, 5, Palette.steelDark)
        case .magnifier:
            c.set(rx + 3, ay + 2, Palette.steelDark)
            c.set(rx + 4, ay + 3, Palette.steelDark)
            c.stamp([".KKK.", "KGGGK", "KGWGK", "KGGGK", ".KKK."], x: rx + 4, y: ay + 4,
                    ["K": Palette.steelDark, "G": Palette.glass, "W": Palette.white])
        case .antennaA, .antennaB:
            let a = x0 + 3, b = x0 + bw - 4
            let first = p.prop == .antennaA
            c.fill(a, top, 1, 2, Palette.eye)
            c.fill(b, top, 1, 2, Palette.eye)
            c.set(a, top + 2, first ? Palette.signalA : Palette.signalB)
            c.set(b, top + 2, first ? Palette.signalB : Palette.signalA)
            if first {
                c.set(b + 2, top + 3, Palette.signalB); c.set(b + 3, top + 4, Palette.signalB)
            } else {
                c.set(a - 2, top + 3, Palette.signalA); c.set(a - 3, top + 4, Palette.signalA)
            }
        }
        if !p.accessories.isEmpty {
            AccessoryArt.drawFront(p.accessories, on: &c, bodyX: x0, bodyWidth: bw, bodyY: y0, top: top, eyeY: ey, handX: rx, handY: ay)
        }
        return c
    }

    // MARK: - Effects and bubbles

    private static func roundedBox(_ c: inout PixelCanvas, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        c.fill(x + 1, y, w - 2, h, Palette.outline)
        c.fill(x, y + 1, w, h - 2, Palette.outline)
        c.fill(x + 1, y + 1, w - 2, h - 2, Palette.white)
    }

    private static var thinkCache: [Int: CGImage] = [:]

    /// Thought bubble with 0–3 animated dots.
    /// `tailRight`: the tail points down-right, for a bubble on the buddy's left.
    static func thinkBubble(dots: Int, tailRight: Bool = false) -> CGImage {
        let key = dots + (tailRight ? 100 : 0)
        if let t = thinkCache[key] { return t }
        var c = PixelCanvas(width: 14, height: 9)
        roundedBox(&c, 0, 2, 14, 7)
        for i in 0..<dots { c.fill(2 + i * 4, 4, 2, 2, Palette.body) }
        c.set(tailRight ? 10 : 3, 1, Palette.outline)
        c.set(tailRight ? 12 : 1, 0, Palette.outline)
        let i = c.cgImage()
        thinkCache[key] = i
        return i
    }

    static let alertBubble: CGImage = {
        var c = PixelCanvas(width: 10, height: 13)
        roundedBox(&c, 0, 2, 10, 11)
        c.fill(4, 7, 2, 4, Palette.body)
        c.fill(4, 4, 2, 2, Palette.body)
        c.fill(4, 1, 2, 1, Palette.outline)
        c.set(4, 0, Palette.outline)
        return c.cgImage()
    }()

    static let heart = PixelCanvas.from([
        ".RR.RR.",
        "RRRRRRR",
        "RRRRRRR",
        ".RRRRR.",
        "..RRR..",
        "...R...",
    ], ["R": Palette.heart]).cgImage()

    static let star = PixelCanvas.from([
        ".Y.",
        "YYY",
        ".Y.",
    ], ["Y": Palette.star]).cgImage()

    static let zee = PixelCanvas.from([
        "ZZZZ",
        "..Z.",
        ".Z..",
        "ZZZZ",
    ], ["Z": Palette.zzz]).cgImage()

    static let snowflake = PixelCanvas.from([
        "..W..",
        "W.W.W",
        ".WWW.",
        "W.W.W",
        "..W..",
    ], ["W": Palette.white]).cgImage()

    /// Music notes in a few colors.
    static let notes: [CGImage] = [Palette.signalB, Palette.star, Palette.heart].map { color in
        PixelCanvas.from([
            "..NNN",
            "..N.N",
            "..N.N",
            "NNN..",
            "NNN..",
        ], ["N": color]).cgImage()
    }

    static let confettiColors: [CGColor] = [
        Palette.body, Palette.star, Palette.signalB, Palette.heart, Palette.white, RGBA(hex: 0x7BD88F),
    ].map { CGColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1) }

    // MARK: - Icons

    /// Black silhouette with see-through eyes for the menu bar (template image).
    static func menuBarIcon() -> NSImage {
        var c = PixelCanvas(width: 16, height: 12)
        let k = Palette.black
        c.fill(2, 2, 12, 7, k)
        c.fill(0, 4, 2, 2, k)
        c.fill(14, 4, 2, 2, k)
        for x in [3, 5, 10, 12] { c.fill(x, 0, 1, 2, k) }
        c.fill(5, 5, 1, 2, .clear)
        c.fill(10, 5, 1, 2, .clear)
        let image = NSImage(cgImage: c.scaled(by: 3).cgImage(), size: NSSize(width: 24, height: 18))
        image.isTemplate = true
        return image
    }

    /// 32×32 app icon: the buddy on a cream rounded tile.
    static func appIconCanvas() -> PixelCanvas {
        var c = PixelCanvas(width: 32, height: 32)
        let (x, y, w, h) = (3, 3, 26, 26)
        c.fill(x + 2, y, w - 4, h, Palette.cream)
        c.fill(x, y + 2, w, h - 4, Palette.cream)
        c.fill(x + 1, y + 1, w - 2, h - 2, Palette.cream)
        c.fill(9, 8, 14, 1, Palette.creamDark)
        c.draw(render(Pose(eyes: .open, arms: .up, look: 0)), x: 0, y: 9)
        return c
    }
}
