import Foundation
import CoreGraphics

enum Hat: String, CaseIterable, Hashable {
    case none, party, topHat, beanie, cowboy, crown, propeller, flower
    case santa, witch, leprechaun, heartBow, flowerCrown

    var title: String {
        switch self {
        case .none: "No Hat"
        case .party: "Party Hat"
        case .topHat: "Top Hat"
        case .beanie: "Beanie"
        case .cowboy: "Cowboy Hat"
        case .crown: "Crown"
        case .propeller: "Propeller Cap"
        case .flower: "Flower"
        case .santa: "Santa Hat"
        case .witch: "Witch Hat"
        case .leprechaun: "Leprechaun Hat"
        case .heartBow: "Heart Bow"
        case .flowerCrown: "Flower Crown"
        }
    }

    /// Hats handed out to session buddies, in order, so each one looks different.
    static let sessionPool: [Hat] = [.party, .topHat, .beanie, .cowboy, .crown, .propeller, .flower]

    /// Draws the hat sitting on a body whose top row is `top - 1` and which spans `left...left + 11`.
    func draw(on c: inout PixelCanvas, left L: Int, top: Int) {
        let t = top
        switch self {
        case .none:
            break
        case .party:
            let a = HatPalette.yellow, b = HatPalette.cyan
            c.fill(L + 3, t, 6, 1, a)
            c.fill(L + 4, t + 1, 4, 1, b)
            c.fill(L + 5, t + 2, 2, 1, a)
            c.fill(L + 5, t + 3, 2, 1, b)
            c.fill(L + 5, t + 4, 2, 1, HatPalette.pink)
        case .topHat, .leprechaun:
            let body = self == .topHat ? HatPalette.black : HatPalette.green
            let band = self == .topHat ? HatPalette.red : HatPalette.darkGreen
            c.fill(L + 1, t, 10, 1, body)
            c.fill(L + 3, t + 1, 6, 4, body)
            c.fill(L + 3, t + 1, 6, 1, band)
            if self == .leprechaun { c.fill(L + 5, t + 1, 2, 1, HatPalette.gold) }
        case .beanie:
            c.fill(L + 1, t, 10, 1, HatPalette.lightBlue)
            c.fill(L + 1, t + 1, 10, 1, HatPalette.blue)
            c.fill(L + 2, t + 2, 8, 1, HatPalette.blue)
            c.fill(L + 4, t + 3, 4, 1, HatPalette.blue)
            c.fill(L + 5, t + 4, 2, 1, Palette.white)
        case .cowboy:
            c.fill(L - 1, t, 14, 1, HatPalette.brown)
            c.set(L - 1, t + 1, HatPalette.brown)
            c.set(L + 12, t + 1, HatPalette.brown)
            c.fill(L + 3, t + 1, 6, 2, HatPalette.tan)
            c.fill(L + 3, t + 1, 6, 1, HatPalette.brown)
            c.fill(L + 3, t + 3, 2, 1, HatPalette.tan)
            c.fill(L + 7, t + 3, 2, 1, HatPalette.tan)
        case .crown:
            c.fill(L + 3, t, 6, 2, HatPalette.gold)
            for x in [L + 3, L + 5, L + 6, L + 8] { c.set(x, t + 2, HatPalette.gold) }
            c.set(L + 5, t + 3, HatPalette.gold)
            c.set(L + 6, t + 3, HatPalette.gold)
            c.set(L + 5, t, HatPalette.red)
            c.set(L + 6, t, HatPalette.red)
        case .propeller:
            c.fill(L + 2, t, 3, 2, HatPalette.red)
            c.fill(L + 5, t, 2, 2, HatPalette.yellow)
            c.fill(L + 7, t, 3, 2, HatPalette.blue)
            c.set(L + 2, t + 1, .clear)
            c.set(L + 9, t + 1, .clear)
            c.fill(L + 5, t + 2, 2, 1, Palette.eye)
            c.fill(L + 2, t + 3, 3, 1, HatPalette.yellow)
            c.fill(L + 5, t + 3, 2, 1, Palette.eye)
            c.fill(L + 7, t + 3, 3, 1, HatPalette.yellow)
        case .flower:
            let cx = L + 8, cy = t + 3
            c.fill(cx, t, 1, 2, HatPalette.green)
            c.set(cx + 1, t + 1, HatPalette.green)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { c.set(cx + dx, cy + dy, HatPalette.pink) }
            c.set(cx, cy, HatPalette.yellow)
        case .santa:
            c.fill(L + 1, t, 10, 1, Palette.white)
            c.fill(L + 2, t + 1, 8, 1, HatPalette.red)
            c.fill(L + 3, t + 2, 7, 1, HatPalette.red)
            c.fill(L + 5, t + 3, 5, 1, HatPalette.red)
            c.fill(L + 8, t + 4, 3, 1, HatPalette.red)
            c.fill(L + 11, t + 2, 2, 2, Palette.white)
            c.set(L + 11, t + 4, HatPalette.red)
        case .witch:
            c.fill(L - 1, t, 14, 1, HatPalette.witch)
            c.fill(L + 2, t + 1, 8, 1, HatPalette.purple)
            c.fill(L + 3, t + 2, 6, 1, HatPalette.witch)
            c.fill(L + 4, t + 3, 4, 1, HatPalette.witch)
            c.fill(L + 5, t + 4, 2, 1, HatPalette.witch)
            c.fill(L + 6, t + 5, 2, 1, HatPalette.witch)
            c.fill(L + 7, t + 6, 2, 1, HatPalette.witch)
        case .heartBow:
            c.stamp(["RR.RR", "RRRRR", ".RRR.", "..R.."], x: L + 6, y: t, ["R": Palette.heart])
        case .flowerCrown:
            c.fill(L + 1, t, 10, 1, HatPalette.green)
            for (x, color) in [(L + 1, HatPalette.pink), (L + 4, HatPalette.yellow), (L + 7, Palette.white), (L + 10, HatPalette.pink)] {
                c.set(x, t, color)
                c.set(x, t + 1, color)
            }
        }
    }
}

enum HatPalette {
    static let yellow = RGBA(hex: 0xFFD447)
    static let cyan = RGBA(hex: 0x5CE1FF)
    static let pink = RGBA(hex: 0xFF7EB6)
    static let black = RGBA(hex: 0x24222A)
    static let red = RGBA(hex: 0xD63B3B)
    static let green = RGBA(hex: 0x3BA55C)
    static let darkGreen = RGBA(hex: 0x1F5E35)
    static let gold = RGBA(hex: 0xF5C542)
    static let blue = RGBA(hex: 0x3F6FD8)
    static let lightBlue = RGBA(hex: 0x7FA6F5)
    static let brown = RGBA(hex: 0x7A4B24)
    static let tan = RGBA(hex: 0xA86F3A)
    static let witch = RGBA(hex: 0x2A2138)
    static let purple = RGBA(hex: 0x8E44AD)
}

/// Seasonal extras for the main buddy.
enum Season {
    struct Look {
        let hat: Hat
        let name: String
        var confetti: [CGColor]?
        var snow = false
    }

    static func look(on date: Date = Date(), installed: Date) -> Look? {
        let cal = Calendar.current
        let m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        let colors = { (hexes: [UInt32]) in hexes.map { h -> CGColor in
            let c = RGBA(hex: h)
            return CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
        } }

        if cal.component(.month, from: installed) == m && cal.component(.day, from: installed) == d
            && cal.component(.year, from: installed) < cal.component(.year, from: date) {
            return Look(hat: .party, name: "Buddy's birthday")
        }
        switch (m, d) {
        case (12, 31), (1, 1): return Look(hat: .party, name: "New Year's")
        case (12, _): return Look(hat: .santa, name: "Holidays", confetti: colors([0xFFFFFF, 0xD63B3B, 0x3BA55C]), snow: true)
        case (10, _): return Look(hat: .witch, name: "Halloween", confetti: colors([0xFF8A1F, 0x8E44AD, 0x24222A, 0x7BD88F]))
        case (2, 7...14): return Look(hat: .heartBow, name: "Valentine's", confetti: colors([0xFF5C7C, 0xFF9EC0, 0xFFFFFF]))
        case (3, 15...17): return Look(hat: .leprechaun, name: "St. Patrick's", confetti: colors([0x3BA55C, 0x7BD88F, 0xF5C542]))
        case (4, _), (5, _): return Look(hat: .flowerCrown, name: "Spring")
        default: return nil
        }
    }
}
