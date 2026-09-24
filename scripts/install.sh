#!/usr/bin/env bash
# Claude Buddy installer: builds from source, installs to /Applications,
# connects Claude Code (hooks in ~/.claude/settings.json), and launches it.
#
#   curl -fsSL https://raw.githubusercontent.com/EmberGuild-Labs/Claude-Buddy/main/scripts/install.sh | bash
#
# Options: --no-hooks   skip connecting Claude Code
set -euo pipefail

REPO_URL="https://github.com/EmberGuild-Labs/Claude-Buddy.git"
HOOKS=1
for arg in "$@"; do
  case "$arg" in
    --no-hooks) HOOKS=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;38;5;173m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Claude Buddy only runs on macOS."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 14 )) || fail "macOS 14 (Sonoma) or newer is required; this Mac has $(sw_vers -productVersion)."
if ! command -v swift >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  fail "Apple's developer tools are needed to build. Run:  xcode-select --install   then run this installer again."
fi

# Use this checkout if we're running from inside one; otherwise clone a fresh copy.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/../Package.swift" ]]; then
  SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  SRC="$(mktemp -d)/Claude-Buddy"
  say "Downloading Claude Buddy…"
  git clone --quiet --depth 1 "$REPO_URL" "$SRC"
fi

say "Building (about a minute the first time)…"
"$SRC/scripts/build-app.sh" --install

if [[ $HOOKS == 1 ]]; then
  say "Connecting Claude Code…"
  /Applications/ClaudeBuddy.app/Contents/MacOS/ClaudeBuddy --install-hooks
fi

say "Launching…"
open /Applications/ClaudeBuddy.app
sleep 2
if curl -fsS -m 2 http://127.0.0.1:47823/claude-buddy/ping >/dev/null 2>&1; then
  say "Claude Buddy is running — look at the bottom of your screen and in the menu bar."
else
  say "Installed. If you don't see the buddy, open /Applications/ClaudeBuddy.app."
fi
[[ $HOOKS == 1 ]] && say "Restart any open Claude Code sessions so they pick up the new hooks."
say "Tip: hold ⌥ Option and click the buddy to pet it."
