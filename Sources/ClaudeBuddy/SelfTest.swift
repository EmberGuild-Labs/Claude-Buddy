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

        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
