# Claude Buddy: notes for Claude Code

A macOS menu-bar app (Swift Package, AppKit + Core Animation, no dependencies). A pixel-art buddy
walks along the bottom of the screen and reacts to Claude Code hook events sent to
`http://127.0.0.1:47823/claude-buddy/event`.

## Installing for a user

1. `./scripts/install.sh`: builds, installs to `/Applications`, adds the hooks to
   `~/.claude/settings.json` (backs the file up first; idempotent; keeps existing hooks), and launches.
   Use `--no-hooks` to skip the settings change.
2. Verify: `curl -s http://127.0.0.1:47823/claude-buddy/ping` should print `claude-buddy ok`.
3. Tell the user to restart their other Claude Code sessions (hooks load when a session starts), and
   that holding ⌥ Option while clicking the buddy pets it.

If `swift` is missing, the user needs to run `xcode-select --install` themselves (it opens a GUI prompt).

Uninstall: `/Applications/ClaudeBuddy.app/Contents/MacOS/ClaudeBuddy --uninstall-hooks`, quit the
app from its menu, then delete `/Applications/ClaudeBuddy.app`.

## Developing

- Build: `swift build`. App bundle: `./scripts/build-app.sh [--install] [--universal] [--zip]`.
- Preview art: `.build/debug/ClaudeBuddy --render-sprites /tmp/sprites.png`
- Fake an event: `echo '{"hook_event_name":"Stop","session_id":"x"}' | curl -s --data-binary @- http://127.0.0.1:47823/claude-buddy/event`
- Test hook editing only on a scratch file: `ClaudeBuddy --install-hooks /path/to/copy.json`.
- Keep CPU around 1%: don't move the window per frame, and don't reintroduce SpriteKit (see README "Performance").
