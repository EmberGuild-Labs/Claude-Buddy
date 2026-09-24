import AppKit

/// `ClaudeBuddy --self-test`: runs the buddies off-screen on a simulated clock and checks the
/// behaviors that are hard to eyeball — sessions, window ledges, riding, games, piggyback,
/// and dancing. Exits non-zero if anything fails.
enum SelfTest {
    static func run() -> Int32 {
        _ = NSApplication.shared
        let size = NSSize(width: 1440, height: 900)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let stage = BuddyStage(frame: NSRect(origin: .zero, size: size))
        let activity = ClaudeActivity()
        stage.cursorReactions = false
        stage.groundY = 80
        stage.sessionsProvider = { activity.liveSessions }
        activity.onPulse = { p, sid in stage.pulse(p, session: sid) }
        window.contentView = stage  // Adds the main buddy.
        stage.isRunning = false     // We drive the clock ourselves.

        var failures = 0
        func simulate(_ seconds: Double, until done: () -> Bool = { false }) {
            for _ in 0..<Int(seconds * 30) {
                stage.advance(1.0 / 30)
                if done() { return }
            }
        }
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print(ok ? "PASS" : "FAIL", name, ok ? "" : detail())
            if !ok { failures += 1 }
        }
        func status(_ b: Buddy) -> [String: Any] { b.status }
        func mode(_ b: Buddy) -> String { (status(b)["mode"] as? String ?? "").components(separatedBy: "(")[0] }
        func event(_ name: String, _ sid: String, _ extra: [String: Any] = [:]) {
            activity.handle(["hook_event_name": name, "session_id": sid, "cwd": "/p/\(sid)"].merging(extra) { $1 })
        }
        var game: String { stage.status["game"] as? String ?? "" }

        // 1. The main buddy settles on the floor.
        simulate(3)
        let main = stage.buddies[0]
        check("main buddy stands on the floor", main.onGround && main.platform == 0 && main.pos.y == 80,
              "\(status(main))")

        // 2. A second session drops in a buddy — onto a window ledge spanning the screen.
        stage.windowPlatforms = [101: WindowPlatform(origin: CGPoint(x: 0, y: 500), segments: [0...1440])]
        event("SessionStart", "a")  // The main buddy takes the first session…
        event("SessionStart", "b")  // …and this one gets an extra buddy.
        simulate(4)
        check("extra buddy appears for a second session", stage.buddies.count == 2, "count=\(stage.buddies.count)")
        guard stage.buddies.count == 2 else { return 1 }
        let extra = stage.buddies[1]
        check("extra buddy wears a hat", extra.hat != .none)
        check("extra buddy lands on the window ledge", extra.platform == 101 && extra.pos.y == 500, "\(status(extra))")

        // 3. It rides along when the window moves…
        let before = extra.pos
        stage.windowPlatforms = [101: WindowPlatform(origin: CGPoint(x: 25, y: 540), segments: [25...1440])]
        simulate(0.1)
        check("buddy rides a moving window", extra.pos.y == 540 && abs(extra.pos.x - before.x - 25) < 8,
              "before=\(before) after=\(extra.pos)")

        // …and falls to the floor when the window goes away.
        stage.windowPlatforms = [:]
        simulate(3, until: { extra.onGround && extra.platform == 0 })
        check("buddy falls when its window closes", extra.platform == 0 && extra.pos.y == 80, "\(status(extra))")

        // 4. Sessions finishing close together start a conga line.
        event("SessionStart", "c")
        simulate(4)
        event("Stop", "b")
        event("Stop", "c")
        simulate(12, until: { game == "conga" })
        check("conga line starts when sessions finish together", game == "conga", "\(stage.status)")
        simulate(12, until: { game == "none" })
        check("conga line ends", game == "none")

        // 5. Tag: someone is "it", and it gets passed around.
        simulate(2)
        var itChanges = 0
        var lastIt = -1
        var elapsed = 0.0
        var lastChangeAt = -10.0
        var quickestTagBack = Double.infinity
        // Buddies mid-reaction (e.g. a high-five) sit games out, so keep trying like the stage does.
        simulate(10, until: { stage.startTag() })
        check("game of tag starts", game == "tag", "\(stage.status)")
        simulate(15, until: {
            elapsed += 1.0 / 30
            let it = stage.status["tagIt"] as? Int ?? -1
            if it != lastIt && lastIt != -1 && it != -1 {
                itChanges += 1
                quickestTagBack = min(quickestTagBack, elapsed - lastChangeAt)
                lastChangeAt = elapsed
            }
            if it != -1 { lastIt = it }
            return game == "none"
        })
        check("tag gets passed at least once", itChanges >= 1, "changes=\(itChanges)")
        check("no instant tag-backs (new \"it\" counts first)", quickestTagBack >= 1.2, "quickest=\(quickestTagBack)s")
        check("tag ends", game == "none")

        // 6. Piggyback: drop one buddy onto another's head.
        simulate(1)
        let rider = stage.buddies[1], carrier = stage.buddies[2]
        simulate(6, until: { carrier.onGround && mode(carrier) != "walk" })
        rider.grab(at: rider.pos, time: 0)
        rider.drag(to: CGPoint(x: rider.pos.x, y: rider.pos.y + 20), time: 0.02)
        rider.drag(to: CGPoint(x: carrier.pos.x, y: carrier.pos.y + 160), time: 0.3)
        for i in 1...10 {  // Hold still over it, then let go.
            rider.drag(to: CGPoint(x: carrier.pos.x, y: carrier.pos.y + 160), time: 0.3 + Double(i) * 0.03)
        }
        rider.release()
        simulate(2, until: { rider.status["riding"] as? Bool == true })
        check("buddy rides piggyback when dropped on another", rider.status["riding"] as? Bool == true,
              "rider=\(status(rider)) carrier=\(status(carrier))")
        simulate(16, until: { rider.status["riding"] == nil && rider.onGround })
        check("rider hops off after a while", rider.status["riding"] == nil, "rider=\(status(rider)) carrier=\(status(carrier)) game=\(game)")

        // 7. Music makes idle buddies dance.
        stage.musicPlaying = true
        simulate(30, until: { stage.buddies.contains { mode($0) == "dance" } })
        check("buddies dance when music plays", stage.buddies.contains { mode($0) == "dance" })
        stage.musicPlaying = false

        // 8. A session ending sends its buddy off-screen.
        let count = stage.buddies.count
        event("SessionEnd", "c")
        simulate(25, until: { stage.buddies.count < count })
        check("buddy leaves when its session ends", stage.buddies.count == count - 1, "count=\(stage.buddies.count)")

        // 9. Menu demos make every buddy act it out.
        simulate(3)
        stage.demo(.waiting, seconds: 4)
        let everyone = { stage.buddies.filter { !$0.isLeaving } }
        simulate(3, until: { everyone().allSatisfy { mode($0) == "alert" } })
        check("every buddy waves in the permission demo", everyone().allSatisfy { mode($0) == "alert" },
              "\(everyone().map(mode))")
        simulate(3)

        // 10. Dismissing extra buddies: they leave and don't come back, but new sessions still get one.
        event("SessionStart", "e")
        simulate(4)
        stage.dismissExtras()
        simulate(30, until: { stage.buddies.count == 1 })
        check("dismiss sends every extra buddy away", stage.buddies.count == 1 && stage.buddies[0].isMain,
              "count=\(stage.buddies.count)")
        simulate(2)
        check("dismissed sessions don't get a buddy back", stage.buddies.count == 1)
        event("SessionStart", "f")
        simulate(4)
        check("a new session still gets a buddy", stage.buddies.count == 2, "count=\(stage.buddies.count)")

        // 11. Canvas: address cleanup, parsing, reminders, and the buddy's sign. Sample data only.
        check("Canvas address is cleaned up and forced to https",
              CanvasClient.normalize("http://Canvas.Example.edu/courses/12?x=1")?.absoluteString == "https://canvas.example.edu"
                && CanvasClient.normalize("school.instructure.com")?.absoluteString == "https://school.instructure.com"
                && CanvasClient.normalize("not a url") == nil)
        check("Canvas pagination link is followed",
              CanvasClient.nextLink(#"<https://s.instructure.com/api/v1/x?page=1>; rel="current", <https://s.instructure.com/api/v1/x?page=2>; rel="next""#)?
                .absoluteString == "https://s.instructure.com/api/v1/x?page=2")

        let base = URL(string: "https://school.instructure.com")!
        let now = Date()
        let iso = ISO8601DateFormatter()
        let sampleCourses: [[String: Any]] = [
            ["id": 7, "name": "AP Chemistry - Period 3", "enrollments": [["type": "student", "computed_current_score": 91.5, "computed_current_grade": "A-"]]],
        ]
        let samplePlanner: [[String: Any]] = [
            ["plannable_type": "assignment", "plannable_id": 1, "course_id": 7, "html_url": "/courses/7/assignments/1",
             "plannable": ["title": "Lab Report", "due_at": iso.string(from: now.addingTimeInterval(40 * 60))],
             "submissions": ["submitted": false, "missing": false, "late": false]],
            ["plannable_type": "assignment", "plannable_id": 2, "course_id": 7, "context_name": "AP Chemistry - Period 3",
             "plannable": ["title": "Worksheet", "due_at": iso.string(from: now.addingTimeInterval(5 * 3600))],
             "submissions": ["submitted": true]],
            ["plannable_type": "quiz", "plannable_id": 3, "course_id": 7,
             "plannable": ["title": "Unit Quiz", "due_at": iso.string(from: now.addingTimeInterval(20 * 3600))],
             "submissions": false, "planner_override": ["marked_complete": false]],
        ]
        let sampleMissing: [[String: Any]] = [
            ["id": 9, "name": "Old Essay", "course_id": 7, "due_at": iso.string(from: now.addingTimeInterval(-3 * 86_400)),
             "html_url": "https://school.instructure.com/courses/7/assignments/9"],
        ]
        let grades = CanvasClient.parseGrades(sampleCourses)
        let names = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0.name) })
        let upcoming = CanvasClient.parsePlanner(samplePlanner, base: base, courseNames: names)
        let missingItems = CanvasClient.parseMissing(sampleMissing, base: base, courseNames: names)
        check("Canvas planner items parse with course names, status, and links",
              upcoming.count == 3 && upcoming[0].title == "Lab Report" && upcoming[0].course == "AP Chemistry - Period 3"
                && upcoming[0].url?.absoluteString == "https://school.instructure.com/courses/7/assignments/1"
                && upcoming[1].submitted && !upcoming[0].submitted, "\(upcoming)")
        check("Canvas grades and missing work parse",
              grades.first?.grade == "A-" && grades.first?.score == 91.5 && missingItems.first?.missing == true
                && missingItems.first?.course == "AP Chemistry - Period 3")

        let snap = SchoolSnapshot(userName: "Sam", upcoming: upcoming, missing: missingItems, grades: grades, fetchedAt: now)
        var fired = Set<String>()
        let first = ReminderPlanner.due(now: now, snapshot: snap, fired: fired)
        let shown = first.filter { !$0.text.isEmpty }
        fired.formUnion(first.map(\.key))
        check("reminders: missing work, the 1-hour warning, and the next-day quiz (not submitted work)",
              shown.contains { $0.text == "Missing: Old Essay" && $0.urgent }
                && shown.contains { $0.text.hasPrefix("AP Chemistry: Lab Report — due in") && $0.urgent }
                && shown.contains { $0.text.hasPrefix("AP Chemistry: Unit Quiz") && !$0.urgent }
                && !shown.contains { $0.text.contains("Worksheet") }, "\(shown.map(\.text))")
        check("reminders don't repeat", ReminderPlanner.due(now: now.addingTimeInterval(60), snapshot: snap, fired: fired)
                .filter { !$0.text.isEmpty }.isEmpty)

        var pile = snap
        pile.missing = (1...12).map { var m = SchoolItem(id: "a\($0)", title: "Thing \($0)", course: "", due: nil, url: nil, kind: "assignment"); m.missing = true; return m }
        let flood = ReminderPlanner.due(now: now, snapshot: pile, fired: []).filter { !$0.text.isEmpty }
        check("a pile of missing work becomes one reminder, not twelve",
              flood.filter { $0.text.contains("missing") || $0.text.hasPrefix("Missing") }.count == 1
                && flood.contains { $0.text == "You have 12 missing assignments" }, "\(flood.map(\.text))")

        let main2 = stage.buddies[0]
        stage.showReminder(Reminder(key: "t", text: "Test sign", urgent: false, url: nil))
        simulate(10, until: { main2.signReminder != nil })
        check("the main buddy holds up the reminder sign", main2.signReminder?.text == "Test sign")

        // 12. The pixel billboard: text, layout, and the buddies holding it up.
        check("pixel font: caps, accents folded, unknown → ?",
              String(PixelFont.normalize("Café ✓")) == "CAFE ?" && PixelFont.width(of: "HELLO") == 29)
        check("pixel font: long titles are shortened to fit",
              PixelFont.fit("Discussion: Industrial Revolution", maxWidth: 60).hasSuffix("..")
                && PixelFont.width(of: PixelFont.fit("Discussion: Industrial Revolution", maxWidth: 60)) <= 60)
        let boardData = Billboard.Data(connected: true, snapshot: BoardPreview.sampleSnapshot(now: now))
        let rendered = Billboard.render(boardData, state: Billboard.State(), now: now)
        check("billboard has tabs, a close button, and clickable assignments",
              rendered.regions.filter { if case .tab = $0.action { return true }; return false }.count == 3
                && rendered.regions.contains { $0.action == .close }
                && rendered.regions.contains { if case .open = $0.action { return true }; return false })
        let notConnected = Billboard.render(Billboard.Data(connected: false), state: Billboard.State(), now: now)
        check("billboard offers to connect Canvas when it isn't connected",
              notConnected.regions.contains { $0.action == .connect })

        stage.boardDataProvider = { boardData }
        simulate(2)
        stage.openBoard()
        simulate(6, until: { stage.boardVisible })
        check("billboard goes up once its holders are in place", stage.boardVisible
                && stage.boardHolders.allSatisfy(\.isHoldingBoard), "holders=\(stage.boardHolders.map { mode($0) })")
        check("two buddies hold it when there's a helper around",
              stage.boardHolders.count == min(2, stage.buddies.filter { !$0.isLeaving }.count),
              "holders=\(stage.boardHolders.count) buddies=\(stage.buddies.count)")
        stage.performBoard(.tab(.grades))
        stage.performBoard(.close)
        simulate(2)
        check("closing the billboard frees the holders",
              !stage.boardOpen && !stage.buddies.contains(where: \.isHoldingBoard))

        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}

/// `ClaudeBuddy --render-board out.png [tab]` draws the Today billboard with sample data.
enum BoardPreview {
    static func sampleSnapshot(now: Date = Date()) -> SchoolSnapshot {
        func item(_ id: String, _ title: String, _ course: String, hours: Double, submitted: Bool = false, kind: String = "assignment") -> SchoolItem {
            var i = SchoolItem(id: id, title: title, course: course, due: now.addingTimeInterval(hours * 3600),
                               url: URL(string: "https://school.instructure.com/courses/1/assignments/\(id)"), kind: kind)
            i.submitted = submitted
            return i
        }
        var missing = item("m", "Chapter 4 Reading Questions", "English 11 - Period 2", hours: -50)
        missing.missing = true
        return SchoolSnapshot(userName: "Sam", upcoming: [
            item("1", "Lab Report: Titration", "AP Chemistry - Period 3", hours: 0.7),
            item("2", "Worksheet 3.2", "Algebra II - Period 1", hours: 2, submitted: true),
            item("3", "Unit 2 Quiz", "US History - Period 5", hours: 20, kind: "quiz"),
            item("4", "Essay Draft: The Great Gatsby", "English 11 - Period 2", hours: 70),
            item("5", "Discussion: Industrial Revolution", "US History - Period 5", hours: 96, kind: "discussion_topic"),
            item("6", "Spanish Vocab Quiz", "Spanish III", hours: 26, kind: "quiz"),
        ], missing: [missing], grades: [
            CourseGrade(id: 1, name: "AP Chemistry - Period 3", score: 91.5, grade: "A-"),
            CourseGrade(id: 2, name: "Algebra II - Period 1", score: 84.2, grade: "B"),
            CourseGrade(id: 3, name: "English 11 - Period 2", score: 77.0, grade: "C+"),
            CourseGrade(id: 4, name: "Spanish III", score: nil, grade: nil),
        ], fetchedAt: now.addingTimeInterval(-120))
    }

    static func render(to url: URL, tab: Billboard.Tab, scale: Int = 2) {
        let data = Billboard.Data(connected: true, snapshot: sampleSnapshot())
        // Pretend the pointer is over the first assignment row to show the ► cursor.
        let state = Billboard.State(tab: tab, pointer: CGPoint(x: 40, y: CGFloat(Billboard.height - 5 - 24 - 15)))
        let board = Billboard.render(data, state: state, now: Date()).canvas
        // Buddies are drawn at 2× the board's pixel size (buddy pixel = 4 pt, board pixel = 2 pt).
        let holder = BuddyArt.render(Pose(arms: .up, hat: .none)).scaled(by: 2)
        let helper = BuddyArt.render(Pose(arms: .up, hat: .topHat)).scaled(by: 2)
        let floor = 8, hands = floor + 22
        var sheet = PixelCanvas(width: board.width + 16, height: board.height + hands + 6)
        sheet.fill(0, 0, sheet.width, sheet.height, RGBA(hex: 0x6B8CAE))
        sheet.fill(0, 0, sheet.width, floor, RGBA(hex: 0x4A6A8C))
        sheet.draw(holder, x: 8 + Int(Double(board.width) * 0.22) - holder.width / 2, y: floor)
        sheet.draw(helper, x: 8 + Int(Double(board.width) * 0.78) - helper.width / 2, y: floor)
        sheet.draw(board, x: 8, y: hands)
        let png = NSBitmapImageRep(cgImage: sheet.scaled(by: scale).cgImage()).representation(using: .png, properties: [:])
        try? png?.write(to: url)
    }
}
