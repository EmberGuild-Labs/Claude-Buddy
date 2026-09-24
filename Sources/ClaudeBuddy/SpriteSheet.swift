import AppKit

/// `--render-sprites <file.png>` writes a contact sheet of the buddy's frames (for docs and art review).
enum SpriteSheet {
    static let poses: [Pose] = [
        Pose(),
        Pose(legs: .stepA, bob: 0), Pose(legs: .stand, bob: 1), Pose(legs: .stepB, bob: 0),
        Pose(legs: .tucked), Pose(legs: .tucked, eyes: .closed),
        Pose(arms: .typeA, prop: .keyboard, look: 1), Pose(arms: .typeB, prop: .keyboard, look: 1),
        Pose(arms: .hammerUp, prop: .hammerUp, look: 1), Pose(arms: .hammerDown, prop: .hammerDown, look: 1),
        Pose(eyes: .wide, arms: .holdOut, prop: .magnifier, look: 1),
        Pose(eyes: .wide, prop: .antennaA, bob: 1), Pose(eyes: .wide, prop: .antennaB),
        Pose(eyes: .wide, arms: .waveHigh), Pose(eyes: .wide, arms: .waveLow),
        Pose(eyes: .happy, arms: .up), Pose(eyes: .dizzy), Pose(squash: true),
    ]

    static func write(to url: URL, scale: Int = 6) {
        let cols = 6
        let cellW = BuddyArt.width + 2, cellH = BuddyArt.height + 2
        let rows = (poses.count + cols - 1) / cols
        var sheet = PixelCanvas(width: cols * cellW, height: rows * cellH + 16)
        sheet.fill(0, 0, sheet.width, sheet.height, RGBA(hex: 0x3A3A40))
        for (i, pose) in poses.enumerated() {
            let x = (i % cols) * cellW + 1
            let y = (rows - 1 - i / cols) * cellH + 16 + 1
            sheet.fill(x, y, BuddyArt.width, BuddyArt.height, RGBA(hex: 0x4A4A52))
            sheet.draw(BuddyArt.render(pose), x: x, y: y)
        }
        // Bubbles and effects along the bottom strip.
        var bx = 2
        for c in [thinkCanvas(), alertCanvas()] { sheet.draw(c, x: bx, y: 2); bx += c.width + 3 }
        _ = bx
        let png = NSBitmapImageRep(cgImage: sheet.scaled(by: scale).cgImage()).representation(using: .png, properties: [:])!
        try? png.write(to: url)
    }

    private static func thinkCanvas() -> PixelCanvas { canvas(of: BuddyArt.thinkBubble(dots: 3)) }
    private static func alertCanvas() -> PixelCanvas { canvas(of: BuddyArt.alertBubble) }

    private static func canvas(of img: CGImage) -> PixelCanvas {
        var c = PixelCanvas(width: img.width, height: img.height)
        let rep = NSBitmapImageRep(cgImage: img)
        for y in 0..<img.height {
            for x in 0..<img.width {
                guard let col = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), col.alphaComponent > 0.5 else { continue }
                var p = RGBA(hex: 0)
                p.r = UInt8(col.redComponent * 255); p.g = UInt8(col.greenComponent * 255); p.b = UInt8(col.blueComponent * 255)
                c.set(x, img.height - 1 - y, p)
            }
        }
        return c
    }
}
