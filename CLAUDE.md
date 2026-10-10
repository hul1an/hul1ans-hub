# Script Hub

Multigame Lua script hub for Roblox internal executors that pass 100% of sUNC (Potassium is the one
the user tests on). Users run a one-line `loadstring` of a raw URL; the loader works out which game
it is in, fetches that game's module, and shows one shared UI. The name is undecided.

The scripts are Luau, not Lua 5.x: Roblox's dialect with `task.*`, `typeof`, `continue`, compound
assignment and the Roblox API.

## Ground rules

**1. No AI slop.**
Match the code that's already here.
- Code reads like a person wrote it: short, plain, no assistant-speak, no filler.
- Comments are one line, the *why* or what a magic number is. No essays, no changelog narrative,
  nothing restating the line below it.
- No defensive noise: no nil checks on things that can't be nil, no pcall-everything, no "just in
  case" fallbacks. The pcalls that are expected are listed under Executor rules.
- No helper wrappers, config flags, or abstraction layers nobody asked for.
- Don't rewrite working code you happened to read. Change what was asked, leave the rest.
- No emoji, no banner comments, no `-- ===== SECTION =====` dividers.
- No tests, probes or verification harnesses unless asked.

**2. Persistent context goes in CLAUDE.md, never in Claude Code memory.**
Memory is per-machine and doesn't sync. Project facts, decisions and gotchas land in this file (or a
scoped `CLAUDE.md` in the subdirectory they belong to), one or two sentences each.

**3. Written is not working.**
Nothing here can run a script against Roblox, so nothing counts as confirmed until the user has run it
in an executor in the target game and reported what they saw. Say "written, not run" and wait.

**4. Ask questions through the question tool**, not in plaintext.

## Executor rules

- Target is any executor at 100% sUNC. Only call functions sUNC covers. No executor-specific globals
  (`syn`, `fluxus`, `KRNL_LOADED`, ...). If it isn't certain a function is in sUNC, ask before using
  it. `identifyexecutor()` is for logging only, never for branching.
- Passing sUNC means the functions exist and pass its checks, not that they behave the same in every
  game. Hooks, `getgc`, `getconnections` and the like still have to be seen working in the game.
- Use `task.spawn / delay / wait`, never `spawn / delay / wait`.
- Get services once at the top of the file: `local Players = cloneref(game:GetService("Players"))`.
- `getgenv()` holds exactly one hub table, and nothing else is put in it. It is the single-instance
  guard: running the loader again calls `unload()` on the previous run first.
- Everything the hub creates is registered for cleanup: connections, Drawing objects, instances,
  threads, hooks. A `hookfunction` hook is undone by hooking the returned original back. `unload()` undoes all of it. A feature that can't be undone doesn't go in.
- Network fetches (the loader, game modules) use `request` and check `StatusCode`. The user's
  one-liner is the only place `game:HttpGet` is acceptable.
- The expected pcalls are the commit lookup in the loader, the load of a game module, and our code inside a
  hooked game function, so a rate-limited API, a broken game file or a hook bug can't take the hub or the
  game's own behaviour down. Report the failure with `warn` (and in the UI once the window exists), don't swallow it.
- Config is saved with `writefile` into a hub folder in the executor workspace, as JSON. Check
  `isfile` before `readfile`.
- When a game-specific instance or remote isn't found, notify with the missing path and skip the
  feature. Don't silently no-op, and don't guess a name: games rename things in updates.

## Layout

| Path | What |
|---|---|
| `loader.lua` | The only file users run. Holds the repo constant, builds the `hub` table (`fetch`, `read`, `load`, `require`, `cleanup`, `unload`, `ui`), looks the game up in the registry and runs its file |
| `core/cleanup.lua` | The cleanup list: `add(item)` for connections, instances, functions and threads, `run()` undoes them all |
| `core/ui.lua` | The menu (`hub.ui`): a port of the "starline" CS2 menu's look from the static dump in `D:\intruigingFolder\zzzclaude\starline-dump-gui` (`docs/P22_gui_visual_spec.md` there is the spec). Built from GUI instances under `gethui()`, not Drawing. `ui.createWindow(title)` returns the window, `ui.visible()` says whether it is showing, `ui.notify(text, "error" | "success" | nil)` shows a toast for 5 s. RightShift toggles the window. `window:CreateTab(name, icon)` takes an icon name from the `ICONS` table; `tab:CreateSection(name, "LeftSide" | "RightSide")` goes to the shorter column without a side; `tab:CreateSubTab(name)` gives a page with its own `CreateSection`, and the bottom strip only shows once a tab has more than one. A section has `CreateLabel`, `CreateButton` (`:Remove()`), `CreateToggle` (`:CreateKeybind(bind)`), `CreateSlider(name, min, max, default, precise, callback, format)`, `CreateDropdown` / `CreateMultiDropdown` (`:AddOption`, `:ClearOptions`), `CreateColorpicker` (`:UpdateColor`), `CreateTextBox(name, placeholder, numbersOnly, callback)` and `CreateGroup(name, default, callback)`, which returns a foldable container with the same methods. Every control has `:AddToolTip(text)`. The header's search steps through controls by name, and its save button opens the config popup. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/bracket.lua` | No longer loaded. Kept only until `core/ui.lua` has been seen working in Potassium, then delete it. Loads AlexR32's BracketV3 (archived, no license, so fetched at a pinned commit instead of copied) and returns `createWindow(title)`. Patches the library at load so its `RunService` / `UserInputService` connections are undone by `unload()`. Also adds an optional side to `tab:CreateSection(name, "LeftSide" | "RightSide")`; without it Bracket picks the shorter column. Two more patches: dropdowns get `:AddOption(name)` and buttons get `:Remove()`, neither of which Bracket has. RightShift toggles the window and `bracket.visible()` says whether it is showing. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/config.lua` | `config.load(name)` / `config.save(name, table)`: JSON files in the `hul1ans-hub` folder of the executor workspace. `load` returns nil when the file doesn't exist. `config.list(prefix)` gives the saved names that start with a prefix and `config.delete(name)` removes one |
| `core/esp.lua` | ESP engine on the Drawing API. `esp.settings` holds the shared options (enabled, team check, box, skeleton, chams, health bar, name, distance), `esp.sources` the target lists, `esp.start()` begins the RenderStepped loop. Each source has its own `enabled`, `color`, `maxDistance` (0-3000), `tracers` and `aim` (whether the aim assist may target it). Players are the built-in source; a game file adds its NPCs with `esp.addSource(name, color, models, label)` before it calls `universal.lua`. `models(skipTeammates)` gets the caller's team check; only the players source uses it, comparing `player.Team`. A source may also have `health(model)` returning health and max health (without it `esp.health` reads the model's Humanoid) and `colorOf(model)` returning a colour to use in place of the source's, or nil. A game whose characters, teams or health aren't the Roblox defaults overrides `esp.sources[1].models` and `.health` in its game file (see BloxStrike). The box is placed and sized from `HumanoidRootPart` (falling back to the model's bounding box when there is none), because a bounding box is thrown off by parts a game keeps elsewhere. The colour covers box, skeleton, chams, tracer and text; the health bar stays red to green. Chams are `Highlight` instances in a folder under `gethui()`; skeleton lines are only created while Skeleton is on |
| `core/aim.lua` | Aim assist and triggerbot, a port of the starline dump's native legit unit (`starline-src/features/combat/legit/` there, `docs/P18_combat_native.md` is its write-up). One step bound with `BindToRenderStep` just after the camera update. Targets come from `esp.sources` whose `aim` flag is set: players always, other sources opt-in. Each frame it takes the target with the best key (crosshair angle, health or distance) that has a visible point inside Max FOV, which is an angle in degrees, not pixels. The points are the centres of the chosen hitgroups' parts (`HITGROUPS` maps starline's seven groups to R15 and R6 part names; Stomach is `HumanoidRootPart`), plus points towards the parts' edges with Multipoint; a model with none of those parts is aimed at by its root. While right mouse is held `pull` turns the camera to the point: a snap by default, with Smoothing starline's per-frame share, humanization and sticky. The triggerbot left clicks through `VirtualInputManager` while the view ray passes through a target's part, after its delay, visible delay and burst. `aim.settings` also holds the hub's own options: team check, visibility check (raycast from the camera that looks through fully invisible parts, since maps have invisible barrier walls), max distance, target colour (sets `esp.highlight` so the ESP draws that model red), auto fire (clicks while there is a target and the menu is hidden). `aim.target` is the current target part for game files to read |
| `core/markers.lua` | Text-only world markers on the Drawing API, for things that aren't characters (corpses, loot). `markers.add(color, instances, label)` returns a group with `enabled`, `color`, `maxDistance` and `interval` (seconds between scans, default 1). `instances()` and `label(instance)` only run on a scan; `label` returns a heading and the text under it, or nil to skip. Between scans it re-checks distance 4 times a second from cached positions and only moves the labels per frame. `markers.start()` begins the loop. Game files start it and build the controls themselves |
| `universal.lua` | Features that work in any game. Starts the ESP and aim assist and returns `function(window)` that adds the Combat tab (starline's aimbot cards General, Targeting, Behavior, Accuracy, Triggerbot and RCS, plus the hub's own Options card) and the ESP tab (master toggle, one section per source, shared options) to a window, and returns `{ combat, esp }` so a game file can add sections to those tabs |
| `assets/` | Files `core/ui.lua` fetches once and then reads from `hul1ans-hub/assets` in the executor workspace through `getcustomasset`, so a changed asset needs a new file name. `GeistMono-Medium.ttf` is the menu font (SIL OFL 1.1, licence in `OFL.txt`). `icons.png` is a sheet of the dump's 21 `sl-*` SVG icons drawn at twice their shown size, made with a throwaway script because Roblox can't render SVG |
| `games/registry.lua` | Maps `game.GameId` (the universe, covers every place) to a game file |
| `games/<name>.lua` | One file per supported game, run with `hub` as `...`. Never requires another game file |
| `games/CLAUDE.md` | Per-game findings: ids, remote names, attribute names, Dex paths, quirks |

- Every fetched file starts with `local hub = ...` if it needs the hub. `hub.require(path)` caches the
  returned value, `hub.load(path)` runs a file fresh.
- Game files call `hub.require("universal.lua")(window)` to add the universal tabs before their own
  Misc / Eject tab. An unsupported game gets a "Universal" window with just those tabs and Eject.
- Settings reset on every load unless a config is loaded from the menu's save button. A config is every
  control's value keyed by its tab / section / name path, saved as `<window title>_config_<name>.json`.
  The Walking Dead Online loot filter is still saved on its own.
- The UI library is `core/ui.lua` (`hub.ui`), asked for by the user on 2026-10-10 to replace Bracket and
  given the method names the game files already called. A different library needs asking first.
- `core/ui.lua` does not call a control's callback while it is built, only on a change, a config load or
  `:UpdateColor`. Bracket did, which is why Walking Dead Online still has a `ready` flag; it can go when
  `core/bracket.lua` does. A new colorpicker is white until `:UpdateColor(color)` is called on it.
- Decided by the user for the port: no backdrop blur and no drop shadow (Roblox has neither), brand text
  "bloxline", and built from scratch in the dump's palette because the dump had no exact draw for them:
  button, label, keybind chip, colour picker layout, dropdown field, text input, tooltip, group header,
  search behaviour, config popup and toasts. Hover, popup fade, open / close and wheel speeds weren't
  recovered either; they are the guessed constants at the top of the file.
- Left out of the port: the CS2-only screens (inventory, side panel, preset chips), Divider, ListBox,
  typing a slider's value, and the picker's alpha bar and RGB sliders (hub colours are `Color3`).
- The Combat tab is starline's aimbot › assist page (`starline-src/assets/gui/pages.json` in the dump has its
  widgets, ranges and formats), asked for by the user on 2026-10-10. A control or option labelled
  `(placeholder)` is a starline feature that needs game code the hub doesn't have: it is drawn and saved in
  configs, and its callback is `nothing`. They are the flash and smoke disablers, the highest damage and
  dynamic hitbox selections, backtrack, auto wall, min damage, baim if lethal, auto scope, the trigger's
  seeded / restricted / min accuracy / auto stop, and all of RCS. Making one real takes a per-game hook
  (damage, recoil, spread, scope or movement) from that game's file.
- Kept in the Combat tab though starline has no such thing: hold right mouse to aim (starline aims whenever
  it is enabled), the Enabled keybind, and the Options card (Team Check, Visibility Check, Max Distance in
  place of starline's weapon range, Target Color, Auto Fire, the per-source target toggles).
- Not in the dump, chosen for the port: every default (the dump has ranges only; they are set so the aim
  snaps as it did before: smoothing off, mouse override 100%), FOV Mode's option names Static / Dynamic
  (only modes 0 and 1 are known), the hitgroup to part map, the trigger's 6 stud reach, and the jump
  disabler's ground ray (BloxStrike characters have no Humanoid to ask). A dynamic FOV is scaled against
  Roblox's default field of view of 70 where starline uses 90.
- `pull` in `core/aim.lua` measures the user's own mouse movement from the view it wrote last frame or from
  the view the game showed before that, whichever the new view is nearer, because a game with its own
  camera script hands back its own angles and the default camera hands back the written ones.
- Shared code lives in `core/`. Don't copy it between game files.

## Hosting

Public GitHub repo `hul1an/hul1ans-hub` (branch `main`), so everything pushed is world-readable: no
tokens, keys or private notes in it. The repo name is the `REPO` constant at the top of `loader.lua`.
Raw branch URLs are cached for 5 minutes and ignore query strings, so a `?t=` cache-buster does nothing.
The loader asks the GitHub API for the latest commit of `main` and fetches every hub file by that commit
hash, falling back to `main` if the API call fails (unauthenticated limit is 60 per hour per IP). The
user's one-liner for `loader.lua` itself can't do that: after a push use the commit hash in its URL, or
wait out the cache.

## Conventions

Defaults until the first files set the pattern:
- Tabs for indentation, double-quoted strings, the StyLua defaults. No formatter is configured.
- `local` everything. No globals.
- camelCase for locals and functions, PascalCase for classes and module tables, UPPER_SNAKE for
  constants.
- File names are lowercase snake_case.

## Game research

The user supplies what Dex++ shows: instance paths, ClassNames, properties and attributes, remote
names, decompiled script source, screenshots. Each request needs the game and its place id, the
executor, and what the script should do. Record anything learned about a game in `games/CLAUDE.md`,
not in the game file's comments.

## Status

Started from scratch on 2026-10-09 after the old C++ Fragment external and the other product's `bot/`
were deleted on the user's instruction (unrecoverable). First game is The Walking Dead Online with a
Bracket placeholder window (confirmed working in Potassium).

`core/ui.lua` and the switch away from Bracket were written on 2026-10-10 and have not been run. Open
until the user reports back: whether Potassium loads the font and the icon sheet through
`getcustomasset`, and whether the window draws and behaves as intended.

The starline combat port (`core/aim.lua`, the Combat tab in `universal.lua`) was written the same day and
has not been run either. It replaced the aim core that was confirmed in BloxStrike, so everything that
goes through it is open again: target selection and FOV in degrees, the hitgroups, multipoint, smoothing /
humanization / sticky in a game with its own camera script, switch delay, mouse override, the jump
disabler, the triggerbot, and that silent aim and Auto Fire still get their target from `aim.target`.
