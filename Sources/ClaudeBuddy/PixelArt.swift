import AppKit

/// An opaque-or-clear RGBA color for pixel art.
struct RGBA: Hashable {
    var r, g, b, a: UInt8

    init(hex: UInt32, a: UInt8 = 255) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        self.a = a
    }

    static let clear = RGBA(hex: 0, a: 0)
}

enum Palette {
    static let body = RGBA(hex: 0xD97757)       // Claude clay orange
    static let bodyDark = RGBA(hex: 0xB65E42)
    static let bodyLight = RGBA(hex: 0xEE9E82)
    static let eye = RGBA(hex: 0x2B1B16)
    static let white = RGBA(hex: 0xFFFFFF)
    static let outline = RGBA(hex: 0x2B1B16)
    static let steel = RGBA(hex: 0x9AA0AC)
    static let steelDark = RGBA(hex: 0x5A5F6B)
    static let wood = RGBA(hex: 0x9A6634)
    static let glass = RGBA(hex: 0xBFE8FF)
    static let keyboard = RGBA(hex: 0x3C3F4A)
    static let key = RGBA(hex: 0xD6D8DE)
    static let heart = RGBA(hex: 0xFF5C7C)
    static let star = RGBA(hex: 0xFFD447)
    static let zzz = RGBA(hex: 0x9DB4FF)
    static let signalA = RGBA(hex: 0xFFD447)
    static let signalB = RGBA(hex: 0x5CE1FF)
    static let cream = RGBA(hex: 0xF4F1EA)
    static let creamDark = RGBA(hex: 0xE2DCCD)
    static let black = RGBA(hex: 0x000000)
}

/// A tiny bitmap with a bottom-left origin (y grows upward, like SpriteKit).
struct PixelCanvas {
    let width: Int
    let height: Int
    private(set) var pixels: [RGBA]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: .clear, count: width * height)
    }

    subscript(x: Int, y: Int) -> RGBA {
        pixels[(height - 1 - y) * width + x]
    }

    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[(height - 1 - y) * width + x] = c
    }

    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) {
            for xx in x..<(x + w) { set(xx, yy, c) }
        }
    }

    /// Stamps rows written top-to-bottom; `y` is where the bottom row lands.
    /// Characters missing from `map` are transparent.
    mutating func stamp(_ rows: [String], x: Int, y: Int, _ map: [Character: RGBA]) {
        for (ri, row) in rows.enumerated() {
            let yy = y + rows.count - 1 - ri
            for (ci, ch) in row.enumerated() {
                if let c = map[ch] { set(x + ci, yy, c) }
            }
        }
    }

    /// Copies every non-transparent pixel of `other` onto this canvas.
    mutating func draw(_ other: PixelCanvas, x: Int, y: Int) {
        for yy in 0..<other.height {
            for xx in 0..<other.width where other[xx, yy].a > 0 {
                set(x + xx, y + yy, other[xx, yy])
            }
        }
    }

    static func from(_ rows: [String], _ map: [Character: RGBA]) -> PixelCanvas {
        var c = PixelCanvas(width: rows.map(\.count).max() ?? 0, height: rows.count)
        c.stamp(rows, x: 0, y: 0, map)
        return c
    }

    /// Nearest-neighbour upscale by an integer factor.
    func scaled(by n: Int) -> PixelCanvas {
        var c = PixelCanvas(width: width * n, height: height * n)
        for y in 0..<height {
            for x in 0..<width { c.fill(x * n, y * n, n, n, self[x, y]) }
        }
        return c
    }

    func cgImage() -> CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(pixels.count * 4)
        for p in pixels {
            // Premultiplied alpha: our pixels are fully opaque or fully clear.
            bytes += p.a == 0 ? [0, 0, 0, 0] : [p.r, p.g, p.b, p.a]
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}
