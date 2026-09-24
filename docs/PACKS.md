# Writing Claude Buddy packs

A **pack** is a JSON file that adds things to Claude Buddy without touching its code:

| Section | What it adds |
|---|---|
| `accessories` | Hats, glasses, capes, things to hold. Chosen from **Extras → Accessories**. |
| `art` | Pixel art for props (tents, beds, ponds) and for custom whole-body sprites. |
| `clips` | Short animations: poses over time, with rotation, bounce, and effects. |
| `activities` | Scripted routines: walking, props, speech, waiting for clicks or keys, puppet control, several buddies at once. |
| `bindings` | Global shortcuts (`ctrl+opt+f`) and **leader-key sequences** (`⌃⌥B`, then `↑ ↑ ↓ ↓`). |
| `triggers` | Run something at a time of day, every N minutes, when an app opens or quits, when the Mac wakes, or when Claude does something. |

Packs live in `~/Library/Application Support/ClaudeBuddy/Packs/`. Open that folder from **Extras → Packs → Open Packs Folder**. After editing a pack, choose **Reload Packs**. Problems appear under **Extras → Packs → Problems**, with the pack, activity, and step number.

The built-in tricks (camping, fishing, the seesaw, puppet mode) are written in this same format, in `Sources/ClaudeBuddy/Extras/BuiltInPack.swift`. They're good examples to copy from. [`example-pack.json`](example-pack.json) shows every section.

## Quick start

```json
{
  "id": "my-pack",
  "name": "My Pack",
  "activities": {
    "hello": {
      "title": "Say Hello",
      "steps": [
        {"face": "cursor"},
        {"say": "Hi there!"},
        {"play": "wave"}
      ]
    }
  },
  "bindings": [{"sequence": "y", "run": "hello"}]
}
```

Save it as `my-pack.json` in the packs folder and reload. Now press **⌃⌥B** then **Y**. It also shows up in **Extras → Tricks & Activities**.

Tools for checking your work (run from a clone of the repo after `swift build`):

```bash
.build/debug/ClaudeBuddy --check-packs                       # what loaded, and any problems
.build/debug/ClaudeBuddy --render-extras /tmp/extras.png     # every accessory, prop, and clip frame
.build/debug/ClaudeBuddy --film camping /tmp/camping.png     # a contact sheet of an activity, frame by frame
```

With the app running, these work too:

```bash
curl -X POST http://127.0.0.1:47823/claude-buddy/extras/reload
curl -X POST -d '{"run": "hello"}' http://127.0.0.1:47823/claude-buddy/do
curl -X POST -d '{"steps": [{"say": "testing"}, {"play": "backflip"}]}' http://127.0.0.1:47823/claude-buddy/do
curl -X POST -d '{"stop": true}' http://127.0.0.1:47823/claude-buddy/do
curl http://127.0.0.1:47823/claude-buddy/extras
```

## Units and coordinates

- **Art pixels.** Every size, position, and speed is in *art pixels*: one pixel of the buddy's art. At Medium size that's 4 screen points, so packs look right at every size.
- **y goes up.** `y` counts up from the floor. The floor is the top of the Dock, or the bottom of the screen when an app is full-screen.
- **The buddy.** It's 12 art pixels wide (about 18 including its arms) and 9 tall. Its position is the point between its feet.
- **Art rows run top to bottom**, as you'd draw them.

## Pixel art

Art is written as rows of characters. Each character maps to a color, and `.` or a space is transparent.

```json
"palette": {"R": "#D63B3B", "K": "#2B1B16"},
"art": {
  "mushroom": {
    "rows": [
      ".RRRR.",
      "RRWRRR",
      "RRRRWR",
      "..KK..",
      "..KK.."
    ],
    "colors": {"W": "white"}
  }
}
```

- **Colors.** Use `#RRGGBB`, `#RRGGBBAA`, or a name: `body`, `bodyDark`, `bodyLight`, `eye`, `white`, `black`, `outline`, `steel`, `steelDark`, `wood`, `glass`, `heart`, `star`, `cream`, `red`, `green`, `blue`, `yellow`, `pink`, `gold`, `brown`, `tan`, `purple`, `cyan`.
- **Where colors come from.** A pack-wide `palette` applies to all of its art. `colors` on one piece adds to it or overrides it.
- **PNG files.** Use `"png": "mushroom.png"` in place of `rows`, with the file next to the pack. Each image pixel becomes one art pixel. Pixels less than half opaque are transparent.
- **Frames.** Give a prop several looks with `frames`, like a closet that's open or closed, or a fire that flickers. Switch between them with a `prop` step.

  ```json
  "fire": {"frames": {"a": [...rows...], "b": [...rows...]}, "frame": "a"}
  ```
- **Built-in art you can reuse:** `builtin.closet` (frames `closed`, `open`), `builtin.bed`, `builtin.blanket`, `builtin.heart`, `builtin.star`, `builtin.zee`, `builtin.snowflake`, `builtin.note`.

## Accessories

```json
"accessories": {
  "wizard-hat": {
    "title": "Wizard Hat",
    "slot": "head",
    "rows": ["...P...", "..PPP..", ".PPPPP.", "PPPPPPP"],
    "colors": {"P": "#6B3FA0"},
    "offset": [0, 0]
  }
}
```

| Slot | Where it goes | Notes |
|---|---|---|
| `head` | Bottom row sits on top of the head, centered. | Replaces the built-in hat while worn. Keep it under about 12 rows. |
| `face` | Centered on the eyes. | Glasses, masks. |
| `body` | Bottom row at the bottom of the body, centered. | Bow ties, belts. Use `offset` to raise it. |
| `held` | Bottom-left corner at the front hand. | Rods, sticks, flags. |
| `back` | Drawn *behind* the body, centered. | Capes, wings, backpacks. |

- **Offsets.** `offset` is `[dx, dy]` in art pixels.
- **Facing.** Art is drawn for a buddy facing right; it flips automatically.
- **Size limit.** The buddy's frame is 32×22 art pixels, so anything outside it is cut off.
- **Wearing them.** The main buddy wears accessories chosen from the menu, one per slot. Activities can add more for a while with `wear` / `unwear`.

## Poses

A pose sets any of these fields. Fields you leave out keep whatever was there before.

| Field | Values |
|---|---|
| `legs` | `stand`, `stepA`, `stepB`, `tucked` (sitting) |
| `eyes` | `open`, `closed`, `happy`, `wide`, `dizzy` |
| `arms` | `down`, `up`, `waveHigh`, `waveLow`, `typeA`, `typeB`, `hammerUp`, `hammerDown`, `holdOut` |
| `prop` | `none`, `keyboard`, `hammerUp`, `hammerDown`, `magnifier`, `antennaA`, `antennaB` |
| `look` | `-1` (back), `0`, `1` (forward) |
| `bob` | `0` or `1`: lifts the body a pixel |
| `squash` | `true`: the landing squash |
| `hat` | `keep` (default), `none`, or a built-in hat: `party`, `topHat`, `beanie`, `cowboy`, `crown`, `propeller`, `flower`, `santa`, `witch`, `leprechaun`, `heartBow`, `flowerCrown` |
| `accessories` | A list of accessory names to add |
| `art` | Replaces the whole buddy sprite with pack art (for example, curled into a ball) |
| `angle` | Rotation in degrees. Positive tips forward, negative tips backward (a backflip). |
| `dx`, `dy` | Nudges the buddy in art pixels without moving where it "is". `dx` is toward the way it faces. |
| `hidden` | `true` hides it |

**Named poses:** `stand`, `sit`, `sleep`, `cheer`, `jump`, `wave`, `surprised`, `dizzy`, `hold`.

## Clips

A clip is a list of frames. Each frame is a pose plus `time` (seconds) and an optional `effect`.

```json
"clips": {
  "backflip": {
    "tween": true,
    "frames": [
      {"squash": true, "time": 0.12},
      {"dy": 7, "angle": -90, "arms": "up", "legs": "tucked", "time": 0.1},
      {"dy": 11, "angle": -180, "arms": "up", "legs": "tucked", "time": 0.1},
      {"dy": 7, "angle": -270, "arms": "up", "legs": "tucked", "time": 0.1},
      {"angle": -360, "time": 0.06},
      {"pose": "cheer", "time": 0.4, "effect": "sparkle"}
    ]
  }
}
```

- **Smooth motion.** `"tween": true` blends `angle`, `dx`, and `dy` smoothly between frames.
- **Looping.** `"loop": true` repeats the clip. Played without `times`, a looping clip keeps going while the script moves on. Stop it with `{"stop": true}` or another `play`.
- **Timing.** `"frameTime": 0.15` (or `"fps": 8`) sets the time for frames that don't give their own.
- **Shorthand.** A frame can be just a pose name: `"frames": ["wave", "stand"]`.
- **Built-in clips:** `backflip`, `cartwheel`, `bow`, `wave`, `robot` (loops), `cast`, `reel` (loops), `stretch`, `roll` (loops, ball art), `handshake`, `munch`.
- **Reduce Motion.** With Reduce Motion turned on, rotation is skipped.

## Activities

```json
"activities": {
  "picnic": {
    "title": "Picnic",
    "menu": true,
    "endWith": "wave",
    "cast": [
      {"role": "star", "who": "main"},
      {"role": "friend", "who": "other", "ifMissing": "summon", "hat": "beanie"}
    ],
    "props": {
      "blanket": {"art": "picnic-blanket", "z": "back"},
      "basket": {"art": "basket", "z": "front"}
    },
    "steps": [ ... ]
  }
}
```

- `title` is the menu name. `"menu": false` hides the activity from the menu, which is useful for activities that only triggers run.
- `endWith` controls how it finishes: `wave` (default) ends with a little wave; `none` goes straight back to normal.
- `cast` defaults to one role, `star`, played by the main buddy.
  - **`who`** picks who plays the role:
    - `main`: the main buddy.
    - `other`: any other buddy. It prefers ones whose Claude session is idle, then the closest.
    - `any`: whoever's free.
  - **`ifMissing`** says what happens when nobody's free for a role:
    - **`summon`** (default): a guest buddy drops in, plays the part, and walks off afterwards. `hat` picks its hat.
    - **`unavailable`**: the activity can't start. It's grayed out in the menu, and the leader key says "Needs 2 buddies".
    - **`skip`**: the role is simply absent, and steps for it are skipped.
- `props` names the props this activity uses. Each is `{"art": "...", "z": "back" | "front" | "over" | number}`:
  - `back` is behind the buddies (a bed).
  - `front` is in front of them (a closet the buddy walks *into*).
  - `over` is in front of the buddies but behind `front` props.

### How it runs

- **One at a time.** Only one activity runs at a time. Starting the *same* activity again while it runs doesn't restart it; it sends the `again` signal, so a shortcut can both start a nap-style routine and wake it.
- **Claude events wait.** Buddies in an activity ignore Claude Code events until it ends.
- **The nap and Today board win.** ⌃⌥N (nap) and ⌃⌥T (Today board) stop any activity first.
- **Stopping it.** Press ⌃⌥B then **Esc**, or choose **Extras → Stop …**.
- **Leaving window ledges.** Buddies sitting on window ledges hop down to the floor before the activity begins.

## Steps

Steps run in order. Most take `who` (a role name). Without it they apply to the current role: the first role, or the role of the enclosing `together` lane. Add `"async": true` to any step to run it in the background while the script moves on.

### Moving

| Step | What it does |
|---|---|
| `{"walk": "center", "speed": 30}` | Walks to an x position. `speed` is art pixels per second (default 30). `"backwards": true` moonwalks. `"clip": "robot"` plays a clip while walking. |
| `{"run": "right-40"}` | Same as `walk`, with a default speed of 60. |
| `{"hop": {"x": "bed.left+15", "y": "bed.bottom+9"}, "height": 14, "time": 0.5}` | An arcing hop. `"hop": true` jumps in place. |
| `{"place": {"x": "left+20", "y": "floor"}}` | Teleports. |
| `{"face": "left"}` | Turns. Also accepts `right`, `turn`, `cursor`, or a role or prop name. |
| `{"hide": true}` / `{"show": true}` | Hides the buddy (inside a tent or closet) or shows it again. |
| `{"ride": "bed", "offset": {"x": 15, "y": 9}}` | Sticks the buddy to a prop, measured from the prop's bottom-left corner. It moves when the prop moves. `{"ride": null}` lets go. |
| `{"leave": true}` | This buddy is done early. A guest walks off; the main buddy goes back to normal. |

### Looking

| Step | What it does |
|---|---|
| `{"pose": "sit"}` or `{"pose": {"eyes": "happy", "arms": "up"}}` | Sets the resting pose. It stays until the next `pose`. `"pose": "stand"` resets it. |
| `{"play": "backflip", "times": 2}` | Plays a clip and waits for it to finish. |
| `{"stop": true}` | Stops a looping clip. |
| `{"wear": "fishing-rod"}` / `{"unwear": "fishing-rod"}` | Adds or removes an accessory for the rest of the activity. |
| `{"say": "Hello!", "time": 2}` | A speech bubble. It waits `time` seconds (default depends on the text length); add `"async": true` to keep going meanwhile. Up to 3 short lines. |
| `{"effect": "hearts", "at": "star", "count": 3}` | Effects: `hearts`, `confetti`, `stars`, `sparkle`, `zzz`, `notes`, `snow`, or `float` (with `"art"`, `"dx"`, `"dy"`, `"time"`). `at` is a role or prop. |

### Props

Everything about a prop goes in one step with `"prop": name`, plus any of these keys:

| Key | What it does |
|---|---|
| `"show": true` or `"show": {"x": "left+20", "y": "floor-16"}` | Shows it. Positions are its **bottom-center**. |
| `"hide": true` | Hides it and stops it following anyone. |
| `"frame": "open"` | Switches frames. |
| `"move": {"x": "...", "y": "..."}` | Slides it there, then the script continues. Add `"time": 0.7` or `"speed": 40`, and `"ease"`: `inOut` (default), `in`, `out`, `linear`. |
| `"follow": "star", "side": "behind"` | Follows a buddy: `behind` for pulling a wagon, `ahead` for pushing. `"gap": 2` sets the space between. `"offset": {"x": 5, "y": 3}` follows at a fixed offset instead (x mirrors with facing). `"follow": null` stops. |
| `"shake": 0.8` | Rattles it for that many seconds. |
| `"flip": true` | Mirrors it. |
| `"z": "front"` | Changes its layer. |

A prop rising out of the floor, like the nap's closet:

```json
{"prop": "tent", "show": {"x": "left+22", "y": "floor-16"}},
{"prop": "tent", "move": {"y": "floor"}, "time": 0.8, "ease": "out"}
```

Going into it and coming out with a wagon in tow:

```json
{"prop": "tent", "frame": "open"},
{"hide": true}, {"prop": "tent", "shake": 0.9}, {"wait": 1.1},
{"prop": "wagon", "show": {"x": "tent", "y": "floor"}},
{"prop": "wagon", "follow": "star", "side": "behind"},
{"show": true}, {"face": "right"},
{"walk": "center", "speed": 26},
{"prop": "wagon", "follow": null}
```

### Flow

| Step | What it does |
|---|---|
| `{"wait": 1.5}` | Pauses. |
| `{"together": [ {"who": "star", "steps": [...]}, {"who": "friend", "steps": [...]} ]}` | Runs lanes side by side and waits for all of them. A lane can also be a plain list of steps. |
| `{"loop": [...], "times": 3}` | Repeats. |
| `{"loop": [...], "until": ["click", "again"], "for": 300}` | Repeats until a condition, or a time limit in seconds. It stops *immediately* when the condition happens, even mid-step. |
| `{"waitFor": "click", "timeout": 20, "else": [...]}` | Waits for a condition. `else` runs on timeout. |
| `{"random": [[...], [...]]}` | Picks one of the lists at random. |
| `{"if": "night", "then": [...], "else": [...]}` | Conditions: `music`, `alone`, `night`, `morning`, `afternoon`, `evening`, `weekend`, `busy` (Claude is working), `reduce-motion`, `chance:0.3`. Put `not:` in front to flip one (`not:music`). |
| `{"call": "backflip"}` | Runs another activity's steps here, using this activity's roles. The other activity's props come along. |

**Conditions** for `until` and `waitFor` can be one value or a list; any of them will do:

| Condition | Happens when |
|---|---|
| `click` | Any buddy in the activity is ⌥-clicked. |
| `click:friend` | That role's buddy is ⌥-clicked. |
| `again` | The activity is started again: its shortcut, menu item, or trigger. |
| `key:space` | A key is pressed. Any key name works. The key is grabbed only while waiting, so it doesn't reach other apps during that time. |
| `never` | Only a time limit or stopping the activity ends it. |

### Puppet mode

```json
{"puppet": {
  "speed": 45, "jump": 20, "timeout": 180, "idleTimeout": 45,
  "hint": "Arrows move, Esc stops",
  "keys": {"f": [{"play": "backflip"}], "h": [{"effect": "hearts"}]}
}}
```

- **Controls.** ← → walk, ↑ or Space jumps, ↓ crouches, and Esc ends puppet mode. The script then carries on.
- **Your own keys.** `keys` adds more controls, each a list of steps. Space can be given another job; the arrows and Esc can't.
- **Other apps lose these keys while it lasts.** The keys are grabbed system-wide during puppet mode. It ends by itself after `timeout` seconds, or after `idleTimeout` seconds with no keys pressed.

## Positions

A position is a number or a string like `base+offset`, for example `"right-20"`, `"bed.left+15"`, `"floor-16"`, or `"40%"`. Offsets are in art pixels.

| x | y |
|---|---|
| a number: from the left edge | a number: up from the floor |
| `left`, `right`, `center` | `floor`, `top` |
| `40%` of the screen width | `40%` of the screen height |
| `here` (this buddy), `start` (where it began), `cursor`, `main` | `here`, `cursor` |
| `offleft`, `offright`: just past the edges | |
| a role name, e.g. `friend` or `friend.x` | a role name (its feet), or `friend.head` |
| a prop: `bed` / `bed.x` (center), `bed.left`, `bed.right` | a prop: `bed` / `bed.bottom`, `bed.top`, `bed.center` |

## Bindings

```json
"bindings": [
  {"keys": "ctrl+opt+f", "run": "fishing"},
  {"sequence": "up up down down", "run": "backflip"},
  {"sequence": "g m", "say": "Good morning!"},
  {"sequence": "z", "steps": [{"play": "bow"}, {"effect": "hearts"}]}
]
```

- **Global shortcuts (`keys`).**
  - They work in any app with no special permissions.
  - Use at least one modifier (`ctrl`, `opt`, `cmd`, `shift`). F-keys can go without one.
  - If another app already owns a shortcut, the Shortcuts menu marks it ⚠︎.
- **The leader key (`sequence`).**
  - The leader key is **⌃⌥B** by default; change it in **Extras → Leader Key**.
  - Press it, then type the keys within 2.5 seconds. The buddy shows what you've typed.
  - Only the keys your sequences use are grabbed, and only for those few seconds.
  - Esc always means "stop the current activity."
- **Sequences that overlap.** If one sequence starts another (`f` and `f f`), typing `f` waits a moment for the second key.
- **What a binding runs.** `run` (an activity), `steps` (inline, acted out by the main buddy), or `say`.
- **Key names:**
  - letters and digits
  - `space`, `return`, `tab`, `escape`, `delete`
  - `up`, `down`, `left`, `right`
  - `f1`–`f12`
  - punctuation: `minus`, `equals`, `comma`, `period`, `slash`, `semicolon`, `quote`, `leftbracket`, `rightbracket`, `backslash`, `grave`

## Triggers

```json
"triggers": [
  {"at": "14:30", "run": "stretch"},
  {"at": "9:00am", "days": "weekdays", "say": "Good morning!"},
  {"every": "45m", "between": "09:00-18:00", "run": "water"},
  {"when": "app-open", "app": "Xcode", "run": "hammer-time", "cooldown": "30m"},
  {"when": "app-quit", "app": "com.spotify.client", "say": "Aw, the music stopped."},
  {"when": "claude", "event": "Stop", "chance": 0.2, "run": "backflip"},
  {"when": "claude", "event": "PostToolUse", "tool": "Bash", "cooldown": "2m", "run": "robot-dance"},
  {"when": "wake", "run": "stretch"},
  {"when": "startup", "say": "Morning!"}
]
```

| Kind | Fires |
|---|---|
| `at` | Once a day at that time (`14:30`, `2:30pm`). If the Mac was asleep, it still fires if it wakes within 10 minutes. |
| `every` | Every `45m`, `2h`, `90s` and so on (at least a minute), counted from when Claude Buddy started. |
| `when: app-launch` | The app starts. |
| `when: app-activate` | You switch to the app. |
| `when: app-open` | Either of the above (default cooldown 10 minutes). |
| `when: app-quit` | The app quits. |
| `when: wake` | The Mac wakes from sleep. |
| `when: startup` | Claude Buddy launches. |
| `when: claude` | A Claude Code hook event: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`. Add `"tool"` to match one tool. |

- **Matching apps.** `app` matches the app's name ("Xcode", case-insensitive) or its bundle ID ("com.apple.dt.Xcode").
- **Limits.**
  - `days`: `weekdays`, `weekends`, or a list like `["mon", "wed"]`.
  - `between`: a daily window like `09:00-17:00`. Windows past midnight work too, like `22:00-02:00`.
  - `cooldown`: the minimum time between firings.
  - `chance`: `0`–`1`.
- **Busy or hidden.** If the buddy is busy (another activity, a nap) or hidden, a trigger waits up to 2 minutes for it to be free.

## Tips

- **Test with a curl.** `{"steps": [...]}` sent to `/claude-buddy/do` is the fastest way to try an idea before putting it in a pack.
- **Film it.** `--film` shows exactly what an activity looks like over time, which makes it easy to line up props.
- **Leave everyone as you found them.** At the end of an activity, props are hidden, extra accessories come off, and guests leave on their own. Still, walk the buddy back somewhere sensible if the activity took it off-screen.
- **Replacing built-ins.** A pack item with the same name as a built-in one replaces it, as long as your pack is enabled.
