import AppKit

/// `--render-extras out.png` draws every accessory, prop, and clip frame (built-in plus your
/// packs folder) on one sheet. `--check-packs` lists what loaded and any problems.
enum ExtrasPreview {
    static func render(to url: URL, scale: Int = 4) {
        let catalog = ExtrasCatalog.load()
        ExtrasCatalog.current = catalog
        let bg = RGBA(hex: 0x3A3A40), cell = RGBA(hex: 0x4A4A52), label = RGBA(hex: 0xD6D8DE)
        var sections: [(String, [PixelCanvas])] = []

        let accessories = catalog.accessories.values.sorted { $0.id < $1.id }
        sections.append(("ACCESSORIES", accessories.map { BuddyArt.render(Pose(accessories: [$0.id])) }))

        var props: [PixelCanvas] = []
        for (name, art) in catalog.art.sorted(by: { $0.key < $1.key }) where !name.hasPrefix("builtin.") {
            for f in art.frames.keys.sorted() { if let c = art.frames[f] { props.append(c) } }
        }
        sections.append(("ART", props))

        for clip in catalog.clips.values.sorted(by: { $0.id < $1.id }) {
            let frames = clip.frames.prefix(10).map { frame -> PixelCanvas in
                if let art = frame.pose.art, let a = catalog.art[art], let c = a.frames[a.defaultFrame] {
                    var out = PixelCanvas(width: BuddyArt.width, height: BuddyArt.height)
                    out.draw(c, x: (BuddyArt.width - c.width) / 2, y: 0)
                    return out
                }
                return BuddyArt.render(pose(frame.pose))
            }
            sections.append(("CLIP " + clip.id, frames))
        }

        let pad = 2, width = 360
        var rows: [(String, [PixelCanvas], Int)] = []
        for (title, items) in sections {
            // Wrap long rows.
            var line: [PixelCanvas] = [], x = 0
            for c in items {
                if x + c.width + pad > width, !line.isEmpty {
                    rows.append((title, line, line.map(\.height).max() ?? 0))
                    line = []; x = 0
                }
                line.append(c); x += c.width + pad
            }
            rows.append((title, line, line.map(\.height).max() ?? 0))
        }
        let totalH = rows.reduce(0) { $0 + $1.2 + 12 } + pad
        var sheet = PixelCanvas(width: width, height: totalH)
        sheet.fill(0, 0, width, totalH, bg)
        var top = totalH - 1
        var lastTitle = ""
        for (title, items, h) in rows {
            if title != lastTitle { PixelFont.draw(title, on: &sheet, x: pad, top: top - 1, color: label) }
            lastTitle = title
            top -= 10
            var x = pad
            for c in items {
                sheet.fill(x, top - h, c.width, h, cell)
                sheet.draw(c, x: x, y: top - h)
                x += c.width + pad
            }
            top -= h + 2
        }
        let png = NSBitmapImageRep(cgImage: sheet.scaled(by: scale).cgImage()).representation(using: .png, properties: [:])!
        try? png.write(to: url)
        print("Wrote \(url.path)")
    }

    /// `--film <activity> out.png`: runs an activity offscreen on a fake clock and saves a contact
    /// sheet of frames (every `every` seconds), nudging it along like a person would.
    static func film(_ id: String, to url: URL, every: Double = 0.5, columns: Int = 4) {
        _ = NSApplication.shared
        ExtrasCatalog.current = ExtrasCatalog.load()
        let size = NSSize(width: 720, height: 220)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let stage = BuddyStage(frame: NSRect(origin: .zero, size: size))
        stage.cursorReactions = false
        stage.windowsEnabled = false
        stage.groundY = 16
        stage.pixel = 3
        window.contentView = stage
        stage.isRunning = false
        stage.director.grabsRealKeys = false
        stage.director.opensApps = false
        stage.layer?.backgroundColor = CGColor(srgbRed: 0.23, green: 0.25, blue: 0.3, alpha: 1)
        let step = 1.0 / 30
        for _ in 0..<60 { stage.advance(step) }
        // Activities that start on a window get a pretend Finder window, with a buddy dropped onto it.
        var preferred: Buddy?
        if ExtrasCatalog.current.activities[id]?.stayOnWindows == true {
            stage.windowsEnabled = true
            stage.windowPlatforms = [1: WindowPlatform(origin: CGPoint(x: 180, y: 120), segments: [180...560], owner: "com.apple.finder")]
            stage.layer?.addSublayer(fakeWindow(CGRect(x: 180, y: 40, width: 380, height: 80)))
            preferred = stage.summonGuest(hat: .topHat)
            if let g = preferred { g.isGuest = false }
            for _ in 0..<90 { stage.advance(step) }
        }
        let result = stage.director.start(ExtrasCatalog.current.activities[id] ?? ActivityDef(id: id, title: id, cast: [], props: [:], steps: [], inMenu: false, greetAtEnd: false, pack: ""), preferred: preferred)
        guard result == .started else { print("Couldn't start \(id): \(result)"); return }

        var frames: [CGImage] = []
        var t = 0.0, nextShot = 0.0
        while t < 90 && frames.count < 64 {
            stage.advance(step)
            t += step
            if Int(t * 30) % 180 == 179, let main = stage.mainBuddy {  // Every 6 s: ⌥-click / press again.
                stage.director.clicked(main)
                stage.director.start(id)
                stage.director.keyEvent("escape", down: true)
                stage.director.keyEvent("escape", down: false)
            }
            if t >= nextShot {
                nextShot += every
                if let img = snapshot(stage) { frames.append(img) }
            }
            if !stage.director.isActive { break }
        }
        let w = Int(size.width), h = Int(size.height), gap = 4
        let rows = (frames.count + columns - 1) / columns
        let W = columns * (w + gap) + gap, H = rows * (h + gap) + gap
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .none
        for (i, img) in frames.enumerated() {
            let col = i % columns, row = i / columns
            ctx.draw(img, in: CGRect(x: gap + col * (w + gap), y: H - (row + 1) * (h + gap), width: w, height: h))
        }
        if let out = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("Wrote \(frames.count) frames of \(id) (\(String(format: "%.1f", t)) s) to \(url.path)")
        }
        _ = window
    }

    private static func fakeWindow(_ r: CGRect) -> CALayer {
        let l = CALayer()
        l.frame = r
        l.backgroundColor = CGColor(gray: 0.92, alpha: 1)
        l.cornerRadius = 6
        l.zPosition = -5
        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: r.height - 14, width: r.width, height: 14)
        bar.backgroundColor = CGColor(gray: 0.8, alpha: 1)
        l.addSublayer(bar)
        return l
    }

    private static func snapshot(_ stage: BuddyStage) -> CGImage? {
        guard let layer = stage.layer else { return nil }
        let w = Int(stage.bounds.width), h = Int(stage.bounds.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    static func pose(_ s: PoseSpec) -> Pose {
        var p = Pose()
        if let v = s.legs { p.legs = v }
        if let v = s.eyes { p.eyes = v }
        if let v = s.arms { p.arms = v }
        if let v = s.prop { p.prop = v }
        if let v = s.look { p.look = v }
        if let v = s.bob { p.bob = v }
        if let v = s.squash { p.squash = v }
        p.accessories = s.accessories ?? []
        return p
    }

    static func checkPacks() -> Int32 {
        let catalog = ExtrasCatalog.load()
        print("Packs folder: \(ExtrasCatalog.packsFolder.path)")
        for p in catalog.packs {
            print("• \(p.name) (\(p.id))\(p.file.map { " — \($0.lastPathComponent)" } ?? ""): "
                  + "\(p.activities.count) activities, \(p.accessories.count) accessories, \(p.clips.count) clips, "
                  + "\(p.bindings.count) bindings, \(p.triggers.count) triggers")
        }
        for t in catalog.triggers { print("  trigger: \(ExtrasController.describe(t))") }
        if catalog.problems.isEmpty {
            print("No problems.")
            return 0
        }
        print("Problems:")
        catalog.problems.forEach { print("  - \($0)") }
        return 1
    }
}
