import AppKit
import Carbon.HIToolbox
import SQLite3

/// Extras checks for `--self-test`: pack parsing, the script engine (every built-in activity is
/// run start to finish on a fake clock), keys and sequences, triggers, and the HTTP endpoint.
/// Uses its own stage so it can't disturb the main self-test's buddies.
enum ExtrasSelfTest {
    static func run() -> Int {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print(ok ? "PASS" : "FAIL", "extras:", name, ok ? "" : detail())
            if !ok { failures += 1 }
        }
        let savedCatalog = ExtrasCatalog.current
        defer { ExtrasCatalog.current = savedCatalog }

        // MARK: Packs parse cleanly
        let builtin = ExtrasCatalog(packs: [BuiltInPack.load()])
        check("built-in pack has no problems", builtin.problems.isEmpty, builtin.problems.joined(separator: "\n  "))
        check("built-in pack has tricks, props routines, and accessories",
              builtin.activities.count >= 12 && builtin.accessories.count >= 6 && builtin.clips.count >= 8,
              "activities=\(builtin.activities.count) accessories=\(builtin.accessories.count) clips=\(builtin.clips.count)")
        var unprintable: [String] = []
        for a in builtin.activities.values {
            builtin.forEachStep(a.steps) { step in
                // PixelFont turns characters it can't draw into "?".
                if case .say(_, let raw, _) = step {
                    // {placeholders} are filled in before they're shown.
                    let text = raw.replacingOccurrences(of: "\\{[a-z]+\\}", with: "x", options: .regularExpression)
                    guard PixelFont.normalize(text).filter({ $0 == "?" }).count != text.filter({ $0 == "?" }).count else { return }
                    unprintable.append(text)
                }
            }
        }
        check("every built-in speech bubble uses characters the pixel font can draw", unprintable.isEmpty, "\(unprintable)")
        let example = PackParser.parse(data: Data(ExamplePack.json.utf8), file: nil, fallbackID: "example")
        let withExample = ExtrasCatalog(packs: [BuiltInPack.load(), example])
        check("example pack has no problems", withExample.problems.isEmpty, withExample.problems.joined(separator: "\n  "))
        check("example pack defines triggers and bindings", withExample.triggers.count == builtin.triggers.count + 7 && withExample.bindings.count > builtin.bindings.count,
              "triggers=\(withExample.triggers.count)")

        let broken = PackParser.parse(data: Data("{ nope".utf8), file: nil, fallbackID: "broken")
        check("invalid JSON is a readable problem, not a crash", broken.problems.first?.contains("JSON") == true)
        let typo = PackParser.parse(data: Data(#"""
        {"id": "typo", "clips": {}, "activities": {
          "a": {"steps": [{"wlak": "center"}]},
          "b": {"steps": [{"play": "missing-clip"}]},
          "c": {"steps": [{"walk": "nowhere+3"}]},
          "d": {"cast": ["star"], "steps": [{"say": "hi", "who": "ghost"}]}
        }, "bindings": [{"keys": "b", "run": "a"}], "triggers": [{"at": "25:00", "say": "x"}]}
        """#.utf8), file: nil, fallbackID: "typo")
        let typoCatalog = ExtrasCatalog(packs: [typo])
        let probs = typoCatalog.problems.joined(separator: "\n")
        check("pack mistakes are reported by name", probs.contains("no action") && probs.contains("missing-clip")
              && probs.contains("nowhere") && probs.contains("ghost") && probs.contains("isn't a shortcut") && probs.contains("25:00"), probs)
        check("activities with mistakes are left out", typoCatalog.activities["b"] == nil && typoCatalog.activities["c"] == nil
              && typoCatalog.activities["d"] == nil)

        // Packs load from a folder, with PNG art beside them, and can be turned off.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("claude-buddy-packs-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dot = PixelCanvas.from(["RR", "RR", "R."], ["R": Palette.heart])
        try? NSBitmapImageRep(cgImage: dot.cgImage()).representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("dot.png"))
        try? Data(#"{"id": "pngpack", "art": {"dot": {"png": "dot.png"}}, "accessories": {"dot-hat": {"slot": "head", "png": "dot.png"}}}"#.utf8)
            .write(to: folder.appendingPathComponent("a.json"))
        try? Data(ExamplePack.json.utf8).write(to: folder.appendingPathComponent("b.json"))
        try? Data("not json".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let loaded = ExtrasCatalog.load(from: folder)
        check("packs load from the packs folder, PNG art included",
              loaded.packs.map(\.id) == ["builtin", "pngpack", "example"] && loaded.art["dot"]?.width == 2 && loaded.art["dot"]?.height == 3
                && loaded.art["dot"]?.frames["default"]?[1, 0].a == 0 && loaded.accessories["dot-hat"] != nil && loaded.problems.isEmpty,
              "\(loaded.packs.map(\.id)) \(loaded.problems)")
        check("a turned-off pack isn't loaded", ExtrasCatalog.load(from: folder, disabled: ["example"]).triggers.allSatisfy { $0.pack == "builtin" })

        // MARK: Positions, keys, sequences
        check("positions parse", PosExpr.parse("right-20") == PosExpr(base: "right", offset: -20)
              && PosExpr.parse("bed.left+15") == PosExpr(base: "bed.left", offset: 15)
              && PosExpr.parse("fishing-rod") == PosExpr(base: "fishing-rod", offset: 0)
              && PosExpr.parse(40) == PosExpr(base: nil, offset: 40)
              && PosExpr.parse("-8") == PosExpr(base: nil, offset: -8)
              && PosExpr.parse("40%") == PosExpr(base: "40%", offset: 0)
              && PosExpr.parse("center + 10 - 4") == PosExpr(base: "center", offset: 6)
              && PosExpr.parse("left*2") == nil)
        let combo = KeyCombo.parse("ctrl+opt+b")
        check("shortcuts parse", combo?.code == UInt32(kVK_ANSI_B) && combo?.carbonModifiers == UInt32(controlKey | optionKey)
              && combo?.title == "⌃⌥B" && KeyCombo.parse("b") == nil && KeyCombo.parse("f5") != nil
              && KeyCombo.parse("cmd+shift+space")?.code == UInt32(kVK_Space) && KeyCombo.parse("ctrl+banana") == nil)
        let m = SequenceMatcher(sequences: [["up", "up", "down", "down"], ["f"], ["f", "f"]])
        check("sequences match exactly, wait on prefixes, and reject strays",
              m.match(["up"]) == .partial && m.match(["up", "up", "down", "down"]) == .run(0)
                && m.match(["f"]) == .runUnlessMore(1) && m.match(["f", "f"]) == .run(2) && m.match(["x"]) == .none
                && m.match(["up", "down"]) == .none)
        let leader = LeaderListener()
        leader.grabKeys = false
        leader.matcher = m
        var ran: [Int] = []
        var shown: [String?] = []
        leader.onMatch = { ran.append($0) }
        leader.onDisplay = { shown.append($0) }
        leader.begin()
        ["up", "up", "down", "down"].forEach(leader.key)
        leader.begin()
        leader.key("x")
        leader.begin()
        leader.key("f")
        leader.expire()  // Nothing more typed: "f" runs.
        check("leader key runs sequences and shows what's typed", ran == [0, 1] && shown.contains("▲ ▲ ▼ ▼") && shown.contains("?"),
              "ran=\(ran) shown=\(shown)")

        // MARK: Accessories
        ExtrasCatalog.current = builtin
        let plain = BuddyArt.render(Pose(hat: .crown))
        let wizard = BuddyArt.render(Pose(hat: .crown, accessories: ["wizard-hat"]))
        let wizardNoHat = BuddyArt.render(Pose(accessories: ["wizard-hat"]))
        check("a head accessory replaces the hat", wizard.pixels != plain.pixels && wizard.pixels == wizardNoHat.pixels)
        let glasses = BuddyArt.render(Pose(hat: .crown, accessories: ["sunglasses", "cape"]))
        check("face and back accessories keep the hat", glasses.pixels != plain.pixels
              && glasses.pixels != BuddyArt.render(Pose(accessories: ["sunglasses", "cape"])).pixels)

        // MARK: The engine, on a stage of our own
        let size = NSSize(width: 1440, height: 900)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let stage = BuddyStage(frame: NSRect(origin: .zero, size: size))
        stage.cursorReactions = false
        stage.groundY = 80
        window.contentView = stage
        stage.isRunning = false
        stage.director.grabsRealKeys = false
        stage.director.opensApps = false
        let director = stage.director
        func simulate(_ seconds: Double, until done: () -> Bool = { false }) {
            for _ in 0..<Int(seconds * 30) {
                stage.advance(1.0 / 30)
                if done() { return }
            }
        }
        simulate(3)
        guard let main = stage.mainBuddy else { check("stage has a main buddy", false); return failures }

        check("handshake needs a second buddy (ifMissing: unavailable)",
              director.start("handshake") == .unavailable("Needs 2 buddies"), "\(director.start("handshake"))")
        check("an unknown activity says so", director.start("no-such-thing") == .unknown)

        var sawGuest = false
        var sawHidden = false
        var sawProp = false
        for id in builtin.activities.keys.sorted() where id != "handshake" {
            let result = director.start(id)
            guard result == .started else { check("\(id) starts", false, "\(result)"); continue }
            var t = 0.0
            simulate(120) {
                t += 1.0 / 30
                // Nudge anything that waits: ⌥-click, the shortcut again, and Esc for puppet mode.
                if Int(t * 30) % 60 == 59 {
                    director.clicked(main)
                    director.keyEvent("escape", down: true)
                    director.keyEvent("escape", down: false)
                    director.start(id)
                }
                if stage.buddies.contains(where: { $0.isGuest && $0.isScripted }) { sawGuest = true }
                if let perf = director.performance {
                    if perf.actors.values.contains(where: \.hidden) { sawHidden = true }
                    if perf.props.values.contains(where: \.visible) { sawProp = true }
                }
                return !director.isActive
            }
            simulate(1.5)
            check("\(id) runs to the end and hands the buddy back",
                  !director.isActive && !main.isScripted && main.pos.y == stage.groundY,
                  "active=\(director.isActive) scripted=\(main.isScripted) y=\(main.pos.y) \(director.status)")
        }
        simulate(12)  // Guests walk off.
        let leftovers = stage.layer?.sublayers?.filter { $0.name?.hasPrefix("extras.") == true } ?? []
        check("props and bubbles are cleaned up", leftovers.isEmpty, "\(leftovers.count) left")
        check("seesaw summons a guest when alone, and it leaves afterwards", sawGuest && !stage.buddies.contains { $0.isGuest && !$0.isLeaving })
        check("camping hides the buddy in the tent and shows props", sawHidden && sawProp)

        // Puppet mode: arrows walk, up jumps, Esc ends.
        director.start("puppet")
        simulate(2)
        let x0 = main.pos.x
        director.keyEvent("right", down: true)
        simulate(1)
        director.keyEvent("right", down: false)
        let walked = main.pos.x - x0
        director.keyEvent("up", down: true)
        var peak = main.pos.y
        simulate(0.5) { peak = max(peak, main.pos.y); return false }
        director.keyEvent("up", down: false)
        simulate(1)
        director.keyEvent("f", down: true)
        director.keyEvent("f", down: false)
        simulate(1.5)
        director.keyEvent("escape", down: true)
        director.keyEvent("escape", down: false)
        simulate(5, until: { !director.isActive })
        simulate(1)
        check("puppet: → walks, ↑ jumps, Esc hands it back", walked > 20 && peak > stage.groundY + 20 && !director.isActive && !main.isScripted,
              "walked=\(walked) peak=\(peak)")

        // With a friend around, the handshake picks it instead of summoning.
        let friend = stage.summonGuest(hat: .beanie)!
        simulate(3)
        check("handshake starts once there's a friend", director.start("handshake") == .started)
        simulate(8, until: { !director.isActive })
        check("handshake casts the buddy that was there", !director.isActive && friend.isLeaving)
        simulate(10)

        // The nap and the billboard win over activities.
        director.start("camping")
        simulate(1)
        stage.toggleNap()
        check("the nap shortcut stops an activity", !director.isActive && stage.nap.isActive)
        check("activities wait while napping", director.start("wave") == .busy("Napping"))
        simulate(30, until: { stage.nap.isNapping })
        stage.toggleNap()
        simulate(30, until: { !stage.nap.isActive })
        director.start("fishing")
        simulate(1)
        stage.toggleBoard()
        check("the Today shortcut stops an activity", !director.isActive && stage.boardOpen)
        stage.closeBoard()
        simulate(3)
        check("everyone is back to normal", !main.isScripted && main.pos.y == stage.groundY)

        // The Finder heist: a buddy up on a Finder window gets the idea; it's all pretend.
        let heistPack = PackParser.parse(data: Data(#"{"id": "t", "triggers": [{"when": "on-window", "app": "Finder", "run": "file-heist"}]}"#.utf8),
                                         file: nil, fallbackID: "t")
        let heistController = ExtrasController(stage: stage)
        heistController.useTriggers(ExtrasCatalog(packs: [BuiltInPack.load(), heistPack]).triggers.filter { $0.pack == "t" })
        stage.windowPlatforms = [7: WindowPlatform(origin: CGPoint(x: 0, y: 400), segments: [0...1440], owner: "com.apple.finder")]
        let climber = stage.summonGuest(hat: .topHat)!
        climber.isGuest = false  // Like a session buddy: it stays afterwards.
        simulate(4, until: { climber.platform == 7 && climber.canJoinGame })
        heistController.checkWindows()
        simulate(0.5)
        let heist = director.performance
        let thief = heist?.actors["thief"]
        // Whoever's up on the Finder window does it (the main buddy may have climbed up too).
        let thiefBuddy = thief?.buddy ?? climber
        check("a buddy on a Finder window starts the heist, right there on the window",
              heist?.def.id == "file-heist" && abs((thief?.startY ?? 0) - 400) < 1,
              "activity=\(director.currentID ?? "none") y=\(thief?.startY ?? -1)")
        var sawLoot = false
        simulate(40) {
            if director.performance?.props["loot"]?.visible == true { sawLoot = true }
            return !director.isActive
        }
        simulate(1)
        check("the heist grabs a pretend file, runs off, and brings it back", sawLoot && !director.isActive && !thiefBuddy.isScripted
              && thiefBuddy.pos.y == stage.groundY)
        heistController.checkWindows()
        check("no heist when nobody's on a Finder window", !director.isActive)
        // The ledge dare walks to the real edge of the window it's on, then hangs off it.
        stage.windowPlatforms = [8: WindowPlatform(origin: CGPoint(x: 300, y: 450), segments: [300...900], owner: "com.apple.Terminal")]
        for _ in 0..<5 where !(climber.platform == 8 && climber.canJoinGame) {
            // Drop it onto the window, away from the main buddy so it doesn't land on its head.
            simulate(2, until: { climber.canJoinGame || climber.platform == 8 })
            climber.grab(at: climber.pos, time: 0)
            // Slowly, so it's a gentle drop rather than a throw.
            climber.drag(to: CGPoint(x: main.pos.x < 600 ? 800 : 400, y: 520), time: 5)
            climber.drag(to: CGPoint(x: main.pos.x < 600 ? 800 : 400, y: 520), time: 10)
            climber.release()
            simulate(4, until: { climber.platform == 8 && climber.canJoinGame })
        }
        director.start(builtin.activities["ledge-dare"]!, preferred: climber)
        var reachedEdge = false, hung = false
        simulate(30) {
            if let p = director.performance, let a = p.actors["daredevil"] {
                if abs(a.x - (900 - 6 * stage.pixel)) < 2 && abs(a.y - 450) < 1 { reachedEdge = true }
                if a.x > 900 && a.y < 450 { hung = true }
            }
            return !director.isActive
        }
        check("ledge dare walks to the window's edge and hangs off it", reachedEdge && hung && !director.isActive,
              "edge=\(reachedEdge) hung=\(hung) platform=\(climber.platform)")
        stage.windowPlatforms = [:]
        climber.beginLeaving()
        simulate(10)

        // New texts: {placeholders} and click-to-open.
        director.start(builtin.activities["new-text"]!, vars: ["count": "3", "s": "s"])
        simulate(3)
        check("the text alert fills in the count", director.performance?.actors["star"]?.sayText == "You got 3 new texts!",
              director.performance?.actors["star"]?.sayText ?? "nil")
        director.clicked(main)
        simulate(10, until: { !director.isActive })
        check("clicking the text alert opens Messages", director.openedApps.last == "com.apple.MobileSMS")
        director.start("new-text")
        simulate(3)
        check("placeholders fall back to the activity's defaults", director.performance?.actors["star"]?.sayText == "You got a new text!")
        director.cancel()
        simulate(2)

        // The Messages watcher, against a pretend Messages database.
        let dbURL = folder.appendingPathComponent("chat.db")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func sql(_ statement: String) {
            var db: OpaquePointer?
            sqlite3_open(dbURL.path, &db)
            sqlite3_exec(db, statement, nil, nil, nil)
            sqlite3_close(db)
        }
        sql("CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, is_from_me INTEGER, is_read INTEGER, text TEXT);"
            + "INSERT INTO message (is_from_me, is_read) VALUES (0, 1), (0, 0), (1, 1);")
        let watcher = MessagesWatcher(database: dbURL)
        let first = watcher.check()
        sql("INSERT INTO message (is_from_me, is_read) VALUES (0, 0), (1, 1), (0, 0);")
        let second = watcher.check()
        let third = watcher.check()
        check("the text watcher counts only new incoming messages", first == (.ok, 0) && second == (.ok, 2) && third == (.ok, 0),
              "\(first) \(second) \(third)")
        check("the text watcher says when it can't read Messages",
              MessagesWatcher(database: folder.appendingPathComponent("nope.db")).check().access == .unavailable)

        // MARK: HTTP
        let extras = ExtrasController(stage: stage)
        func post(_ json: String) -> Int { extras.handle(method: "POST", path: "/claude-buddy/do", body: Data(json.utf8))?.0 ?? 0 }
        check("POST /do say", post(#"{"say": "Hello!"}"#) == 200)
        check("POST /do while busy is a 409", post(#"{"run": "bow"}"#) == 409)
        simulate(10, until: { !director.isActive })
        check("POST /do unknown is a 404, bad steps a 400", post(#"{"run": "nope"}"#) == 404 && post(#"{"steps": [{"wlak": 1}]}"#) == 400)
        check("POST /do steps", post(#"{"steps": [{"play": "bow"}, {"effect": "hearts"}]}"#) == 200)
        check("POST /do stop", post(#"{"stop": true}"#) == 200 && !director.isActive)
        check("GET /extras lists activities", extras.handle(method: "GET", path: "/claude-buddy/extras", body: Data())?.1.contains("\"camping\"") == true)
        simulate(2)

        // MARK: Triggers (fake clock, throwaway defaults)
        let suite = "claude-buddy-selftest-\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = TriggerEngine()
        engine.defaults = defaults
        engine.triggers = withExample.triggers
        var fired: [String] = []
        engine.fire = { t, _ in fired.append(t.action.run ?? t.action.say ?? "?") }
        let cal = Calendar.current
        func date(_ weekday: Int, _ h: Int, _ m: Int) -> Date {
            // A date in a known week: 2026-09-20 is a Sunday (weekday 1).
            cal.date(from: DateComponents(year: 2026, month: 9, day: 19 + weekday, hour: h, minute: m))!
        }
        engine.clockTick(date(3, 12, 29))
        check("an “at” trigger waits for its time", !fired.contains("Lunch time!"))
        engine.clockTick(date(3, 12, 31))
        engine.clockTick(date(3, 12, 33))
        check("an “at” trigger fires once that day", fired.filter { $0 == "Lunch time!" }.count == 1, "\(fired)")
        engine.clockTick(date(4, 12, 30))
        check("…and again the next day", fired.filter { $0 == "Lunch time!" }.count == 2)
        engine.clockTick(date(4, 15, 0))
        check("an “at” trigger that's hours late doesn't fire", fired.filter { $0 == "Lunch time!" }.count == 2)
        fired = []
        engine.clockTick(date(7, 17, 1))  // Saturday.
        check("weekday triggers skip the weekend", !fired.contains("stretch"))
        let water = withExample.triggers.first { $0.action.run == "water" }!
        check("“between” and “days” limit when a trigger may fire",
              engine.allowed(water, now: date(3, 10, 0)) && !engine.allowed(water, now: date(3, 19, 0)) && !engine.allowed(water, now: date(1, 10, 0)))
        fired = []
        engine.appEvent("app-activate", name: "Xcode", bundleID: "com.apple.dt.Xcode", now: date(3, 10, 0))
        engine.appEvent("app-activate", name: "Xcode", bundleID: "com.apple.dt.Xcode", now: date(3, 10, 5))
        engine.appEvent("app-launch", name: "Xcode", bundleID: "com.apple.dt.Xcode", now: date(3, 10, 40))
        check("“app-open” fires on launch or activate, with a cooldown", fired == ["hello-app", "hello-app"], "\(fired)")
        engine.appEvent("app-quit", name: "Spotify", bundleID: "com.spotify.client", now: date(3, 11, 0))
        check("apps match by bundle ID too", fired.last == "Aw, the music stopped.")
        check("app names match case-insensitively", TriggerEngine.appMatches("xcode", name: "Xcode", bundleID: nil)
              && !TriggerEngine.appMatches("Xcode", name: "Xcode Helper", bundleID: nil))
        check("times parse in 24h and am/pm", PackParser.clockTime("2:30pm")! == (14, 30) && PackParser.clockTime("12am")! == (0, 0)
              && PackParser.clockTime("09:05")! == (9, 5) && PackParser.clockTime("13pm") == nil)

        _ = window
        return failures
    }
}
