import AppKit

/// Renders the pixel-art app icon at every size an .iconset needs.
enum IconRenderer {
    static func writeIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let art = BuddyArt.appIconCanvas().cgImage()
        let sizes: [(String, Int)] = [
            ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
            ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
            ("512x512", 512), ("512x512@2x", 1024),
        ]
        for (name, px) in sizes {
            guard let ctx = CGContext(
                data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            ctx.interpolationQuality = .none
            ctx.draw(art, in: CGRect(x: 0, y: 0, width: px, height: px))
            guard let image = ctx.makeImage(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: dir.appendingPathComponent("icon_\(name).png"))
        }
    }
}
