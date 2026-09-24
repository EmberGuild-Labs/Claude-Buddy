import Foundation

/// The Today billboard: a video-game-style menu drawn in pixels, which the buddies hold up.
///
/// `render` is pure: given the data and UI state it returns the pixel canvas plus the
/// clickable regions, so the stage only has to show the image and map clicks.
enum Billboard {
    enum Tab: Int, CaseIterable { case due, missing, grades }

    enum Action: Equatable {
        case tab(Tab), page(Int), open(URL), close, refresh, connect
    }

    struct State: Equatable {
        var tab = Tab.due
        var page = 0
        /// Board-pixel position of the pointer, if it's over the board.
        var pointer: CGPoint?
        var blink = true
    }

    struct Data {
        var connected = false
        var loading = false
        var error: String?
        var snapshot: SchoolSnapshot?
    }

    /// A clickable rectangle, in board pixels (origin bottom-left).
    struct Region {
        let rect: CGRect
        let action: Action
        /// Footer text shown while hovering.
        var detail: String?
    }

    static let width = 176
    static let rowsPerPage = 9
    private static let rowHeight = 10
    static var height: Int { 4 + 12 + 12 + rowsPerPage * rowHeight + 3 + 10 + 4 }

    enum Colors {
        static let outline = RGBA(hex: 0x14111F)
        static let frame = Palette.body
        static let frameLight = Palette.bodyLight
        static let panel = RGBA(hex: 0x231F33)
        static let panelLight = RGBA(hex: 0x352F4A)
        static let text = RGBA(hex: 0xF4F1EA)
        static let dim = RGBA(hex: 0x9A93B0)
        static let red = RGBA(hex: 0xFF6B6B)
        static let green = RGBA(hex: 0x7BD88F)
        static let yellow = RGBA(hex: 0xFFD447)
        static let cyan = RGBA(hex: 0x5CE1FF)
    }

    private enum Row {
        case header(String, RGBA)
        case item(SchoolItem)
        case grade(CourseGrade)
        case message(String, RGBA)
        case button(String, Action)
    }

    static func render(_ data: Data, state: State, now: Date) -> (canvas: PixelCanvas, regions: [Region], pages: Int) {
        let W = width, H = height
        var c = PixelCanvas(width: W, height: H)
        var regions: [Region] = []

        // Frame: dark outline, 2px orange frame with a highlight, dark inner line, dark panel.
        c.fill(1, 0, W - 2, H, Colors.outline)
        c.fill(0, 1, W, H - 2, Colors.outline)
        c.fill(1, 1, W - 2, H - 2, Colors.frame)
        c.fill(2, H - 3, W - 4, 1, Colors.frameLight)
        c.fill(3, 3, W - 6, H - 6, Colors.outline)
        c.fill(4, 4, W - 8, H - 8, Colors.panel)

        let left = 4, right = W - 5
        var top = H - 5  // Current row's top y (y grows upward).

        // Title bar.
        c.fill(left, top - 10, right - left + 1, 11, Colors.frame)
        PixelIcon.star.draw(on: &c, x: left + 2, top: top - 2, tint: Colors.yellow, carve: Colors.frame)
        let date = now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        PixelFont.draw("TODAY · " + date, on: &c, x: left + 12, top: top - 2, color: Colors.text)
        let closeX = right - 9
        PixelIcon.close.draw(on: &c, x: closeX, top: top - 2, tint: hovering(state, x: closeX - 2, y: top - 10, w: 11, h: 11) ? Colors.yellow : Colors.text, carve: Colors.frame)
        regions.append(Region(rect: CGRect(x: closeX - 2, y: top - 10, width: 11, height: 11), action: .close, detail: "CLOSE"))
        top -= 12

        // Tabs.
        let missingCount = data.snapshot?.missing.count ?? 0
        let tabs: [(Tab, String)] = [(.due, "DUE"), (.missing, missingCount > 0 ? "MISSING \(missingCount)" : "MISSING"), (.grades, "GRADES")]
        var tx = left + 2
        for (tab, label) in tabs {
            let w = PixelFont.width(of: label) + 6
            let rect = CGRect(x: tx, y: top - 10, width: w, height: 11)
            let selected = state.tab == tab
            let hover = contains(rect, state.pointer)
            if selected {
                c.fill(tx, top - 10, w, 11, Colors.text)
            } else {
                c.fill(tx, top - 10, w, 1, Colors.panelLight)
            }
            let color = selected ? Colors.panel : (tab == .missing && missingCount > 0 ? Colors.red : (hover ? Colors.text : Colors.dim))
            PixelFont.draw(label, on: &c, x: tx + 3, top: top - 2, color: color)
            regions.append(Region(rect: rect, action: .tab(tab)))
            tx += w + 3
        }
        top -= 12

        // Rows for the current tab.
        let rows = self.rows(for: state.tab, data: data, now: now)
        let pages = max(1, Int(ceil(Double(rows.count) / Double(rowsPerPage))))
        let page = min(state.page, pages - 1)
        var detail: String?
        for row in rows.dropFirst(page * rowsPerPage).prefix(rowsPerPage) {
            let rect = CGRect(x: left, y: top - rowHeight + 1, width: right - left + 1, height: rowHeight)
            let hover = contains(rect, state.pointer)
            switch row {
            case .header(let text, let color):
                PixelFont.draw(text, on: &c, x: left + 3, top: top - 2, color: color)
                c.fill(left + 3 + PixelFont.width(of: text) + 3, top - 5, max(0, right - left - PixelFont.width(of: text) - 9), 1, Colors.panelLight)
            case .message(let text, let color):
                PixelFont.draw(PixelFont.fit(text, maxWidth: right - left - 6), on: &c, x: left + 3, top: top - 2, color: color)
            case .button(let text, let action):
                if hover { c.fill(left + 1, top - rowHeight + 1, right - left - 1, rowHeight, Colors.panelLight) }
                if hover && state.blink { PixelFont.draw("►", on: &c, x: left + 2, top: top - 2, color: Colors.yellow) }
                PixelFont.draw(text, on: &c, x: left + 10, top: top - 2, color: hover ? Colors.yellow : Colors.text)
                regions.append(Region(rect: rect, action: action))
            case .item(let item):
                if hover { c.fill(left + 1, top - rowHeight + 1, right - left - 1, rowHeight, Colors.panelLight) }
                let (icon, tint) = self.icon(for: item)
                if hover && state.blink {
                    PixelFont.draw("►", on: &c, x: left + 2, top: top - 2, color: Colors.yellow)
                } else if !hover {
                    icon.draw(on: &c, x: left + 2, top: top - 2, tint: tint, carve: Colors.panel)
                }
                let due = item.due.map { dueLabel($0, now: now, missing: state.tab == .missing) } ?? ""
                let dueWidth = PixelFont.width(of: due)
                let titleX = left + 12
                let titleColor = item.isDone ? Colors.dim : (hover ? Colors.yellow : Colors.text)
                PixelFont.draw(PixelFont.fit(item.title, maxWidth: right - 3 - dueWidth - 5 - titleX), on: &c, x: titleX, top: top - 2, color: titleColor)
                PixelFont.draw(due, on: &c, x: right - 2 - dueWidth, top: top - 2, color: item.missing ? Colors.red : Colors.dim)
                let info = self.detail(for: item)
                if let url = item.url { regions.append(Region(rect: rect, action: .open(url), detail: info)) }
                if hover { detail = info }
            case .grade(let g):
                if hover { c.fill(left + 1, top - rowHeight + 1, right - left - 1, rowHeight, Colors.panelLight) }
                let text = [g.grade, g.score.map { String(format: "%.1f%%", $0) }].compactMap { $0 }.joined(separator: " ")
                let value = text.isEmpty ? "--" : text
                let vw = PixelFont.width(of: value)
                PixelIcon.star.draw(on: &c, x: left + 2, top: top - 2, tint: gradeColor(g.score), carve: Colors.panel)
                PixelFont.draw(PixelFont.fit(ReminderPlanner.shortCourse(g.name), maxWidth: right - 3 - vw - 5 - (left + 12)), on: &c, x: left + 12, top: top - 2, color: Colors.text)
                PixelFont.draw(value, on: &c, x: right - 2 - vw, top: top - 2, color: gradeColor(g.score))
                if hover { detail = g.name }
            }
            top -= rowHeight
        }

        // Footer: detail line + pager.
        let footerTop = 4 + 10 + 2
        c.fill(left + 2, footerTop, right - left - 3, 1, Colors.panelLight)
        let pagerText = pages > 1 ? "◄ \(page + 1)/\(pages) ►" : ""
        let pagerWidth = PixelFont.width(of: pagerText)
        if pages > 1 {
            let px = right - 2 - pagerWidth
            let prev = CGRect(x: px - 2, y: 4, width: 9, height: 11)
            let next = CGRect(x: px + pagerWidth - 6, y: 4, width: 9, height: 11)
            PixelFont.draw(pagerText, on: &c, x: px, top: footerTop - 3, color: Colors.dim)
            if page > 0 {
                PixelFont.draw("◄", on: &c, x: px, top: footerTop - 3, color: contains(prev, state.pointer) ? Colors.yellow : Colors.text)
                regions.append(Region(rect: prev, action: .page(-1), detail: "PREVIOUS PAGE"))
            }
            if page < pages - 1 {
                PixelFont.draw("►", on: &c, x: px + pagerWidth - 5, top: footerTop - 3, color: contains(next, state.pointer) ? Colors.yellow : Colors.text)
                regions.append(Region(rect: next, action: .page(1), detail: "NEXT PAGE"))
            }
        }
        if detail == nil, let p = state.pointer { detail = regions.last(where: { $0.rect.contains(p) })?.detail }
        let footer = detail ?? footerHint(data, now: now)
        PixelFont.draw(PixelFont.fit(footer, maxWidth: right - left - 8 - (pages > 1 ? pagerWidth + 6 : 0)),
                       on: &c, x: left + 3, top: footerTop - 3, color: detail == nil ? Colors.dim : Colors.cyan)
        if detail == nil && data.connected {
            regions.append(Region(rect: CGRect(x: left, y: 4, width: 60, height: 11), action: .refresh, detail: "REFRESH FROM CANVAS"))
        }
        return (c, regions, pages)
    }

    // MARK: - Content

    private static func rows(for tab: Tab, data: Data, now: Date) -> [Row] {
        guard data.connected else {
            return [.message("CANVAS ISN'T CONNECTED YET.", Colors.text), .message("", Colors.dim),
                    .message("SEE WHAT'S DUE AND GET", Colors.dim), .message("REMINDERS FROM YOUR BUDDY.", Colors.dim),
                    .message("", Colors.dim), .button("CONNECT CANVAS", .connect)]
        }
        guard let snap = data.snapshot else {
            if let error = data.error {
                return [.message("CAN'T REACH CANVAS:", Colors.red)]
                    + PixelFont.wrap(error, maxWidth: width - 16, maxLines: 6).map { .message($0, Colors.dim) }
            }
            return [.message("LOADING...", Colors.dim)]
        }
        switch tab {
        case .due:
            let cal = Calendar.current
            var groups: [(String, [SchoolItem])] = [("TODAY", []), ("TOMORROW", []), ("THIS WEEK", []), ("LATER", [])]
            for item in snap.upcoming {
                guard let due = item.due else { groups[3].1.append(item); continue }
                if due < now && !cal.isDateInToday(due) { continue }
                if cal.isDateInToday(due) { groups[0].1.append(item) }
                else if cal.isDateInTomorrow(due) { groups[1].1.append(item) }
                else if due < now.addingTimeInterval(7 * 86_400) { groups[2].1.append(item) }
                else { groups[3].1.append(item) }
            }
            let rows = groups.filter { !$0.1.isEmpty }.flatMap { [Row.header($0.0, Colors.dim)] + $0.1.map { Row.item($0) } }
            return rows.isEmpty ? [.message("NOTHING DUE FOR 2 WEEKS!", Colors.green)] : rows
        case .missing:
            return snap.missing.isEmpty ? [.message("NO MISSING WORK. NICE!", Colors.green)] : snap.missing.map { .item($0) }
        case .grades:
            return snap.grades.isEmpty ? [.message("NO GRADES TO SHOW.", Colors.dim)] : snap.grades.map { .grade($0) }
        }
    }

    private static func icon(for item: SchoolItem) -> (PixelIcon, RGBA) {
        if item.isDone { return (.done, Colors.green) }
        if item.missing { return (.missing, Colors.red) }
        switch item.kind {
        case "quiz": return (.quiz, Colors.yellow)
        case "discussion_topic": return (.discussion, Colors.cyan)
        case "calendar_event", "planner_note": return (.event, Colors.dim)
        default: return (.todo, item.late ? Colors.yellow : Colors.text)
        }
    }

    private static func detail(for item: SchoolItem) -> String {
        var parts = [item.course.isEmpty ? item.title : ReminderPlanner.shortCourse(item.course)]
        if item.missing { parts.append("MISSING") }
        else if item.submitted { parts.append(item.late ? "SUBMITTED LATE" : "SUBMITTED") }
        else if item.markedDone { parts.append("DONE") }
        else if item.late { parts.append("LATE") }
        return parts.joined(separator: " · ")
    }

    private static func footerHint(_ data: Data, now: Date) -> String {
        guard data.connected else { return "CANVAS · NOT CONNECTED" }
        guard let snap = data.snapshot else { return data.loading ? "LOADING..." : "" }
        let mins = Int(now.timeIntervalSince(snap.fetchedAt) / 60)
        return mins < 1 ? "UPDATED JUST NOW" : "UPDATED \(mins)M AGO"
    }

    /// "2:01PM" today/tomorrow, "FRI" this week, "9/27" otherwise (follows the Mac's 12/24-hour setting).
    static func dueLabel(_ due: Date, now: Date, missing: Bool) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if !missing && (cal.isDateInToday(due) || cal.isDateInTomorrow(due)) {
            f.setLocalizedDateFormatFromTemplate("jmm")
            return f.string(from: due).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{202F}", with: "").uppercased()
        }
        if !missing && due < now.addingTimeInterval(7 * 86_400) {
            f.setLocalizedDateFormatFromTemplate("EEE")
            return f.string(from: due).uppercased()
        }
        f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: due)
    }

    private static func gradeColor(_ score: Double?) -> RGBA {
        guard let score else { return Colors.dim }
        return score >= 90 ? Colors.green : score >= 80 ? Colors.cyan : score >= 70 ? Colors.yellow : Colors.red
    }

    private static func contains(_ rect: CGRect, _ p: CGPoint?) -> Bool { p.map { rect.contains($0) } ?? false }

    private static func hovering(_ state: State, x: Int, y: Int, w: Int, h: Int) -> Bool {
        contains(CGRect(x: x, y: y, width: w, height: h), state.pointer)
    }

    // MARK: - Reminder placard

    /// A small held-up sign in the same pixel style: cream board, dark text, red frame when urgent.
    static func sign(_ text: String, urgent: Bool) -> PixelCanvas {
        let lines = PixelFont.wrap(text, maxWidth: 6 * 22 - 1, maxLines: 3)
        let textWidth = lines.map { PixelFont.width(of: $0) }.max() ?? 0
        let W = textWidth + 12, H = lines.count * 9 + 9
        var c = PixelCanvas(width: W, height: H)
        let frame = urgent ? Colors.red : Colors.frame
        c.fill(1, 0, W - 2, H, Colors.outline)
        c.fill(0, 1, W, H - 2, Colors.outline)
        c.fill(1, 1, W - 2, H - 2, frame)
        c.fill(3, 3, W - 6, H - 6, Colors.outline)
        c.fill(4, 4, W - 8, H - 8, Palette.cream)
        for (i, line) in lines.enumerated() {
            let x = (W - PixelFont.width(of: line)) / 2
            PixelFont.draw(line, on: &c, x: x, top: H - 6 - i * 9, color: Colors.outline)
        }
        return c
    }
}
