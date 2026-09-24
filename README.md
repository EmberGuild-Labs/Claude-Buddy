# Claude Buddy

A tiny pixel-art Claude critter that lives along the bottom of your Mac's screen. It wanders over whatever apps you have open without ever stealing focus or clicks, and it comes alive when you're working with **Claude Code**: pacing while Claude thinks, typing when it runs commands, hammering when it edits code, waving when Claude needs your permission, and doing a victory backflip when a task finishes.

![Buddy sprite sheet](docs/sprites.png)

## Features

- **Stays out of your way.** A transparent, click-through overlay that never becomes the active window. Your keyboard and mouse keep going to the app you're using.
- **Knows where the floor is.** It walks on top of the Dock normally, and drops to the very bottom of the screen when the front app is full-screen or maximized.
- **Reacts to Claude Code** through Claude Code hooks:

  | Claude Code event | Buddy |
  |---|---|
  | Session starts | Wakes up and waves |
  | You send a prompt | Paces around with a thought bubble 💭 |
  | `Bash` | Types on a little keyboard |
  | `Edit` / `Write` | Swings a hammer (with sparks) |
  | `Read` / `Grep` / `Glob` | Inspects things with a magnifying glass |
  | `WebFetch` / `WebSearch` / MCP tools | Antennae pop up and beam signals |
  | Needs your permission | Stops, faces your cursor, waves, and shows a "!" bubble |
  | Task finished | Jumps, backflips, and bursts into confetti 🎉 |
  | Tool error | Dizzy, with stars circling its head |
  | Nothing for 5 minutes | Sits, then falls asleep 💤 |

- **Pettable.** Hold **⌥ Option** and click the buddy to pet it (hearts ❤️). Hold ⌥ and drag to pick it up, then flick to throw it. It bounces off the screen edges.
- **Multiple sessions.** It tracks every Claude Code session and shows the most important state (needs-you > working > thinking > idle).
- **Light on resources.** Uses about 1% CPU. See "Performance" below.
- Respects **Reduce Motion** (no flips or wobble, fewer hops).

## Requirements

- macOS 14 Sonoma or later (built and tested on macOS 27)
- Swift 5.10+ toolchain (Xcode or Command Line Tools)
- Claude Code (CLI or desktop app) for the reactions. Without it the buddy still wanders.

## Setup

1. **Build and install** the app into `/Applications`:

   ```bash
   ./scripts/build-app.sh --install
   ```

   Leave off `--install` to only build `build/ClaudeBuddy.app`.

2. **Launch it:**

   ```bash
   open /Applications/ClaudeBuddy.app
   ```

   A small buddy icon appears in the menu bar and the buddy drops in along the bottom of the screen.

3. **Connect Claude Code.** From the menu-bar icon, choose **Install Claude Code Hooks…**. This adds hook entries to `~/.claude/settings.json` after backing the file up (`settings.json.claude-buddy-backup-<timestamp>`). Your other settings and hooks are left alone. **Restart any Claude Code sessions that are already open**, because hooks are read when a session starts.

   Command-line alternative:

   ```bash
   /Applications/ClaudeBuddy.app/Contents/MacOS/ClaudeBuddy --install-hooks
   ```

4. *(Optional)* Turn on **Launch at Login** from the menu.

## Usage

Menu-bar menu:

| Item | What it does |
|---|---|
| Status lines | What Claude is doing, whether hooks are installed, where the floor is, and server status |
| Show Buddy | Hide or show the buddy (hiding also pauses its frame loop) |
| Quiet Mode | Ignore Claude Code events; the buddy just wanders |
| Size | Small / Medium / Large |
| Display | Walk on the main display, or follow the mouse between displays |
| Try an Animation | Preview every reaction without Claude Code |
| Install / Remove Claude Code Hooks | Add or remove the hooks in `~/.claude/settings.json` |
| Launch at Login | Start automatically |

**Petting:** hold ⌥ while hovering the buddy. The cursor turns into a hand. Click to pet, or drag to carry and flick to throw.

### Uninstalling

1. Menu → **Remove Claude Code Hooks…** (or run `ClaudeBuddy --uninstall-hooks`)
2. Quit the app and delete `/Applications/ClaudeBuddy.app`

## How it works

```
Claude Code ──hook (curl)──▶ 127.0.0.1:47823 ──▶ ClaudeActivity ──▶ BuddyStage (brain + physics + Core Animation)
                                                                          ▲
                              OverlayController (window, floor detection)─┘
```

| File | Role |
|---|---|
| `main.swift` | App delegate, plus command-line flags (`--install-hooks`, `--uninstall-hooks`, `--render-icon`, `--render-sprites`) |
| `Overlay.swift` | The click-through `NSPanel` and floor placement (Dock top vs. screen bottom) |
| `BuddyStage.swift` | Behavior state machine, physics, poses, effects, ⌥-petting |
| `BuddyArt.swift` / `PixelArt.swift` | All pixel art is drawn in code, from part-based `Pose`s, and cached |
| `ClaudeActivity.swift` | Merges hook events from all sessions into one state |
| `EventServer.swift` | Minimal HTTP server bound to `127.0.0.1` only (Network.framework) |
| `HookInstaller.swift` | Safely edits `~/.claude/settings.json` (idempotent, backs up first) |
| `MenuController.swift` | Menu-bar UI and demos |

### The hook

Every hooked event runs:

```bash
curl -s -m 1 -o /dev/null -H 'Content-Type: application/json' -H 'Expect:' \
  --data-binary @- http://127.0.0.1:47823/claude-buddy/event >/dev/null 2>&1 || true
```

- It **never prints anything**. Output from `UserPromptSubmit` and `SessionStart` hooks gets added to Claude's context, so staying silent matters.
- It **always exits 0** and times out after 1 s, so it can't block or fail Claude Code, even if the buddy isn't running.
- `-H 'Expect:'` stops curl from waiting on a `100-continue` for large payloads (such as `Read` results).

Hooked events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SubagentStop`.

Health check: `curl http://127.0.0.1:47823/claude-buddy/ping` returns `claude-buddy ok`.

## Notes and decisions

- **Native Swift/AppKit, no Electron.** It's small, has no dependencies, and gives the window-level control a desktop pet needs.
- **Hooks instead of guessing.** Claude Code hooks give exact, low-latency events (which tool, which session) with no screen scraping or process polling. The server listens on loopback only.
- **Why the window never ignores you:** it's a non-activating `NSPanel` at status-bar level, on all Spaces including full-screen ones, with `ignoresMouseEvents = true`. The frame loop polls ⌥ and the cursor position. Neither needs Accessibility or Input Monitoring permission. Only while ⌥ is held over the buddy does the window accept the mouse, so you can pet it.
- **Floor detection:** every 0.75 s, and on app or Space switches, it reads the frontmost app's window bounds with `CGWindowListCopyWindowInfo`. Reading bounds needs no Screen Recording permission. If a window fills the usable screen area, the floor becomes the screen's bottom edge; otherwise it's the top of the Dock. When the floor changes, the buddy falls or hops to the new floor.
- **Performance:**
  - The first version used SpriteKit and sat at around 6% CPU, because the Metal render loop costs something every frame even for a tiny scene.
  - Switching to plain Core Animation layers moved compositing to the WindowServer.
  - A "small window that follows the buddy" experiment was *worse* (about 5%): moving a window every frame is expensive. So the window spans the screen width and never moves.
  - The frame rate adapts: 30 fps while moving, 15 while standing, 10 while asleep.
  - Result: about 1% CPU idle or pacing, with brief spikes during confetti.
- **Tool flicker:** fast tools like `Read` start and finish within milliseconds. The buddy remembers the last tool for a few seconds and finishes each 2–4 s "bit" before switching, so animations don't stutter.
- **Permission prompts:** the buddy waves until the next event for that session arrives. After you approve a long-running command, it may keep waving until that command finishes, because no hook fires in between.
- **Art:** an original Claude-inspired critter in Claude's clay orange (`#D97757`), drawn procedurally so new poses are a few lines of code. `--render-sprites file.png` writes a contact sheet.

## Development

```bash
swift build                                     # debug build
.build/debug/ClaudeBuddy                        # run without bundling
.build/debug/ClaudeBuddy --render-sprites out.png
echo '{"hook_event_name":"Stop","session_id":"x"}' | \
  curl -s --data-binary @- http://127.0.0.1:47823/claude-buddy/event   # trigger a celebration
```

The single-instance check and Launch at Login only work from the bundled `.app`.

## Ideas for later

- Speech bubbles showing the tool name or a snippet of Claude's message
- Optional sound effects
- One buddy per Claude Code session
- Auto-hide while screen sharing
