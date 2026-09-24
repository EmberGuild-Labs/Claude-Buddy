import AppKit
import QuartzCore

/// Pixel art for the nap: a wardrobe that rises from the floor, and a bed on little wheels.
enum NapArt {
    private static let woodDark = RGBA(hex: 0x5A3A1E)
    private static let wood = RGBA(hex: 0x9A6634)
    private static let woodLight = RGBA(hex: 0xB8834E)
    private static let inside = RGBA(hex: 0x2B1B16)
    private static let knob = RGBA(hex: 0xF5C542)
    private static let wheel = RGBA(hex: 0x3C3F4A)
    private static let sheet = RGBA(hex: 0xF4F1EA)
    private static let sheetShade = RGBA(hex: 0xD9D2C3)
    private static let blanket = RGBA(hex: 0x5B8DEF)
    private static let blanketLight = RGBA(hex: 0x9DB4FF)

    /// Canvas is 24 wide: the wardrobe body spans x 6…23; an open door swings out to x 0…4.
    static let closetWidth = 24, closetHeight = 28
    static let closetCenter = 15

    static let closetClosed: CGImage = closet(open: false)
    static let closetOpen: CGImage = closet(open: true)

    private static func closet(open: Bool) -> CGImage {
        var c = PixelCanvas(width: closetWidth, height: closetHeight)
        let x0 = 6, w = 18
        c.fill(x0, 1, w, 27, woodDark)
        c.fill(x0 + 1, 2, w - 2, 23, wood)
        c.fill(x0, 25, w, 3, woodDark)          // Crown
        c.fill(x0 + 1, 26, w - 2, 1, woodLight)
        c.fill(x0 + 1, 0, 3, 1, woodDark)       // Feet
        c.fill(x0 + w - 4, 0, 3, 1, woodDark)
        if open {
            c.fill(x0 + 3, 3, 12, 21, inside)
            c.fill(x0 + 4, 20, 10, 1, woodDark)  // Hanging rod
            for hx in [x0 + 6, x0 + 10] {        // Two hangers
                c.set(hx, 19, woodLight); c.set(hx - 1, 18, woodLight); c.set(hx + 1, 18, woodLight)
            }
            // The door, swung open to the left.
            c.fill(0, 3, 5, 21, woodDark)
            c.fill(1, 4, 3, 19, wood)
            c.set(3, 13, knob)
        } else {
            c.fill(x0 + 3, 3, 12, 21, woodDark)
            c.fill(x0 + 4, 4, 10, 19, wood)
            c.fill(x0 + 5, 15, 8, 6, woodLight)   // Panels
            c.fill(x0 + 5, 5, 8, 8, woodLight)
            c.set(x0 + 12, 13, knob)
        }
        return c.cgImage()
    }

    /// Bed canvas: 30 × 16. Mattress top is at y = 8, so a buddy lying on it has its feet at y = 9.
    static let bedWidth = 30, bedHeight = 16
    static let mattressTop = 9
    /// Where the sleeper lies, measured from the bed's left edge.
    static let sleeperX = 15

    static let bed: CGImage = {
        var c = PixelCanvas(width: bedWidth, height: bedHeight)
        c.fill(2, 0, 2, 2, wheel)                 // Wheels
        c.fill(26, 0, 2, 2, wheel)
        c.fill(0, 2, 30, 3, woodDark)             // Frame
        c.fill(1, 3, 28, 1, wood)
        c.fill(27, 2, 3, 11, woodDark)            // Headboard (right)
        c.fill(28, 3, 1, 9, woodLight)
        c.fill(0, 2, 2, 8, woodDark)              // Footboard (left)
        c.fill(2, 5, 25, 4, sheet)                // Mattress
        c.fill(2, 5, 25, 1, sheetShade)
        c.fill(21, 9, 5, 2, sheet)                // Pillow
        c.fill(21, 9, 5, 1, sheetShade)
        return c.cgImage()
    }()

    /// Drawn in front of the sleeping buddy, tucking in its lower half.
    static let blanketImage: CGImage = {
        var c = PixelCanvas(width: bedWidth, height: bedHeight)
        c.fill(6, 6, 16, 5, blanket)
        c.fill(6, 10, 16, 1, blanketLight)
        c.fill(6, 6, 1, 5, blanketLight)
        return c.cgImage()
    }()
}

/// Runs the nap: closet rises → buddy goes in → pulls a bed across the screen → naps →
/// (woken) stretches → hops off → pushes the bed off the right edge.
final class NapDirector {
    enum Phase: String {
        case idle, closetRising, opening, inside, pulling, climbing, napping, stretching, hoppingOff, pushing, rolling
    }

    unowned let stage: BuddyStage
    private(set) var phase = Phase.idle
    /// Bring up the Today billboard once the nap is over.
    var openBoardAfter = false

    private var t: TimeInterval = 0
    private let closet = CALayer()
    private let bed = CALayer()
    private let blanket = CALayer()
    private var closetRise: CGFloat = 0   // 0 = hidden below the floor, 1 = standing
    private var closetSinking = false
    private var bedLeft: CGFloat = 0
    private var hopFrom = CGPoint.zero, hopTo = CGPoint.zero
    private var zClock: TimeInterval = 0

    var isActive: Bool { phase != .idle }
    var isNapping: Bool { phase == .napping }

    init(stage: BuddyStage) {
        self.stage = stage
        for (layer, image, z) in [(closet, NapArt.closetClosed, 2.0), (bed, NapArt.bed, -1.0), (blanket, NapArt.blanketImage, 1.0)] {
            layer.actions = BuddyStage.noActions
            layer.contents = image
            layer.magnificationFilter = .nearest
            layer.zPosition = CGFloat(z)
            layer.isHidden = true
            layer.anchorPoint = .zero
        }
        closet.anchorPoint = CGPoint(x: CGFloat(NapArt.closetCenter) / CGFloat(NapArt.closetWidth), y: 0)
    }

    func attach(to layer: CALayer?) {
        [closet, bed, blanket].forEach { layer?.addSublayer($0) }
    }

    // MARK: - Geometry (points)

    private var P: CGFloat { stage.pixel }
    private var s: CGFloat { P / 4 }
    private var floor: CGFloat { stage.groundY }
    private var closetX: CGFloat { 8 + CGFloat(NapArt.closetCenter) * P }
    private var closetRight: CGFloat { closetX + CGFloat(NapArt.closetWidth - NapArt.closetCenter) * P }
    private var bedW: CGFloat { CGFloat(NapArt.bedWidth) * P }
    private var halfWidth: CGFloat { 9 * P }
    private var bedFinalLeft: CGFloat { stage.bounds.width - halfWidth * 1.8 - bedW - 4 }
    private var sleepSpot: CGPoint {
        CGPoint(x: bedLeft + CGFloat(NapArt.sleeperX) * P, y: floor + CGFloat(NapArt.mattressTop) * P)
    }

    // MARK: - Control

    func start() {
        guard phase == .idle, let main = stage.mainBuddy else { return }
        main.beginScript()
        closetRise = 0
        closetSinking = false
        closet.contents = NapArt.closetClosed
        setPhase(.closetRising)
    }

    /// ⌥-click, the shortcut, or the menu while napping.
    func wake() {
        guard phase == .napping else { return }
        blanket.isHidden = true
        setPhase(.stretching)
    }

    func toggle() {
        if phase == .idle { start() } else if phase == .napping { wake() }
    }

    private func setPhase(_ p: Phase) {
        phase = p
        t = 0
    }

    // MARK: - Frame

    func tick(_ dt: TimeInterval) {
        guard phase != .idle else { return }
        guard let main = stage.mainBuddy else { return finish() }
        t += dt
        let walk = 120 * s, pull = 95 * s

        switch phase {
        case .idle:
            break
        case .closetRising:
            closetRise = min(1, closetRise + CGFloat(dt / 0.7))
            let arrived = move(main, toward: closetX, speed: walk, dt: dt)
            if closetRise >= 1 && arrived { setPhase(.opening) }
        case .opening:
            closet.contents = NapArt.closetOpen
            main.script(x: closetX, y: floor, facing: 1, pose: .stand)
            if t > 0.35 {
                main.script(x: closetX, y: floor, facing: 1, pose: .hidden)
                setPhase(.inside)
            }
        case .inside:
            main.script(x: closetX, y: floor, facing: 1, pose: .hidden)
            if t > 1.0 {
                bedLeft = closetX - bedW / 2
                bed.isHidden = false
                setPhase(.pulling)
            }
        case .pulling:
            bedLeft = min(bedFinalLeft, bedLeft + pull * CGFloat(dt))
            main.script(x: bedLeft + bedW + halfWidth * 0.7, y: floor, facing: 1, pose: .walk)
            if !closetSinking && bedLeft > closetRight { closetSinking = true }
            if bedLeft >= bedFinalLeft {
                hopFrom = main.pos
                hopTo = sleepSpot
                setPhase(.climbing)
            }
        case .climbing:
            let done = hop(main, duration: 0.5, facing: -1)
            if done {
                blanket.isHidden = false
                zClock = 0
                setPhase(.napping)
            }
        case .napping:
            main.script(x: sleepSpot.x, y: sleepSpot.y, facing: 1, pose: .sleep)
            zClock += dt
            if zClock > 1.6 {
                zClock = 0
                stage.floatingEffect(BuddyArt.zee, at: CGPoint(x: sleepSpot.x + 5 * P, y: sleepSpot.y + 8 * P),
                                     dx: 16 * s, dy: 40 * s, duration: 1.8, grow: (0.6, 1.1))
            }
        case .stretching:
            main.script(x: sleepSpot.x, y: sleepSpot.y, facing: 1, pose: .stretch(progress: t / 1.1))
            if t > 1.1 {
                hopFrom = sleepSpot
                hopTo = CGPoint(x: bedLeft - halfWidth * 0.7, y: floor)
                setPhase(.hoppingOff)
            }
        case .hoppingOff:
            if hop(main, duration: 0.45, facing: -1) { setPhase(.pushing) }
        case .pushing:
            bedLeft += 110 * s * CGFloat(dt)
            let x = bedLeft - halfWidth * 0.7
            let stop = stage.bounds.width - halfWidth - 4
            main.script(x: min(x, stop), y: floor, facing: 1, pose: x < stop ? .walk : .stand)
            if x >= stop { setPhase(.rolling) }  // One last shove; the bed rolls off by itself.
        case .rolling:
            bedLeft += 150 * s * CGFloat(dt)
            main.script(x: main.pos.x, y: floor, facing: 1, pose: .stand)
            if bedLeft > stage.bounds.width + 4 { finish() }
        }

        if closetSinking {
            closetRise = max(0, closetRise - CGFloat(dt / 0.6))
            if closetRise == 0 { closet.isHidden = true }
            if closetRise < 1 { closet.contents = NapArt.closetClosed }
        }
        layout()
    }

    private func finish() {
        [closet, bed, blanket].forEach { $0.isHidden = true }
        let hadMain = stage.mainBuddy
        setPhase(.idle)
        hadMain?.endScript()
        if openBoardAfter {
            openBoardAfter = false
            stage.openBoard()
        }
    }

    /// Walks the buddy toward `x`; returns true once it's there.
    private func move(_ b: Buddy, toward x: CGFloat, speed: CGFloat, dt: TimeInterval) -> Bool {
        let dx = x - b.pos.x
        let step = speed * CGFloat(dt)
        if abs(dx) <= step {
            b.script(x: x, y: floor, facing: dx >= 0 ? 1 : -1, pose: .stand)
            return true
        }
        b.script(x: b.pos.x + (dx > 0 ? step : -step), y: floor, facing: dx > 0 ? 1 : -1, pose: .walk)
        return false
    }

    /// A little arcing hop from `hopFrom` to `hopTo`; returns true when it lands.
    private func hop(_ b: Buddy, duration: TimeInterval, facing: CGFloat) -> Bool {
        let k = min(1, t / duration)
        let x = hopFrom.x + (hopTo.x - hopFrom.x) * CGFloat(k)
        let arc = 14 * P * CGFloat(4 * k * (1 - k))
        let y = hopFrom.y + (hopTo.y - hopFrom.y) * CGFloat(k) + arc
        b.script(x: x, y: y, facing: hopTo.x >= hopFrom.x ? 1 : facing, pose: k < 1 ? .jump : .stand)
        return k >= 1
    }

    private func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cw = CGFloat(NapArt.closetWidth) * P, ch = CGFloat(NapArt.closetHeight) * P
        closet.bounds = CGRect(x: 0, y: 0, width: cw, height: ch)
        closet.isHidden = closetRise <= 0
        var shake: CGFloat = 0
        if phase == .inside && t > 0.2 && t < 0.85 && !stage.reduceMotion { shake = sin(t * 45) * P * 0.5 }
        closet.position = CGPoint(x: (closetX + shake).rounded(), y: (floor - ch * (1 - easeOut(closetRise))).rounded())
        let bh = CGFloat(NapArt.bedHeight) * P
        for layer in [bed, blanket] {
            layer.bounds = CGRect(x: 0, y: 0, width: bedW, height: bh)
            layer.position = CGPoint(x: bedLeft.rounded(), y: floor.rounded())
        }
        CATransaction.commit()
    }

    private func easeOut(_ x: CGFloat) -> CGFloat { 1 - (1 - x) * (1 - x) }
}
