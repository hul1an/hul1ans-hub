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
| `loader.lua` | The only file users run. Holds the repo constant, builds the `hub` table (`fetch`, `load`, `require`, `cleanup`, `unload`, `bracket`), looks the game up in the registry and runs its file |
| `core/cleanup.lua` | The cleanup list: `add(item)` for connections, instances, functions and threads, `run()` undoes them all |
| `core/bracket.lua` | Loads AlexR32's BracketV3 (archived, no license, so fetched at a pinned commit instead of copied) and returns `createWindow(title)`. Patches the library at load so its `RunService` / `UserInputService` connections are undone by `unload()`. Also adds an optional side to `tab:CreateSection(name, "LeftSide" | "RightSide")`; without it Bracket picks the shorter column. Two more patches: dropdowns get `:AddOption(name)` and buttons get `:Remove()`, neither of which Bracket has. RightShift toggles the window and `bracket.visible()` says whether it is showing. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/config.lua` | `config.load(name)` / `config.save(name, table)`: JSON files in the `hul1ans-hub` folder of the executor workspace. `load` returns nil when the file doesn't exist |
| `core/esp.lua` | ESP engine on the Drawing API. `esp.settings` holds the shared options (enabled, team check, box, skeleton, chams, health bar, name, distance), `esp.sources` the target lists, `esp.start()` begins the RenderStepped loop. Each source has its own `enabled`, `color`, `maxDistance` (0-3000), `tracers` and `aim` (whether the aim assist may target it). Players are the built-in source; a game file adds its NPCs with `esp.addSource(name, color, models, label)` before it calls `universal.lua`. `models(skipTeammates)` gets the caller's team check; only the players source uses it, comparing `player.Team`. A source may also have `health(model)` returning health and max health (without it `esp.health` reads the model's Humanoid) and `colorOf(model)` returning a colour to use in place of the source's, or nil. A game whose characters, teams or health aren't the Roblox defaults overrides `esp.sources[1].models` and `.health` in its game file (see BloxStrike). The box is placed and sized from `HumanoidRootPart` (falling back to the model's bounding box when there is none), because a bounding box is thrown off by parts a game keeps elsewhere. The colour covers box, skeleton, chams, tracer and text; the health bar stays red to green. Chams are `Highlight` instances in a folder under `gethui()`; skeleton lines are only created while Skeleton is on |
| `core/aim.lua` | Aim assist. While right mouse is held it turns the camera to the best target (no smoothing), bound with `BindToRenderStep` just after the camera update. Targets come from `esp.sources` whose `aim` flag is set: players always, other sources opt-in. `aim.settings`: team check, visibility check (raycast from the camera), max distance, mode (Distance / Crosshair / Health), target part, FOV radius in pixels around the screen centre, draw FOV circle, target colour (sets `esp.highlight` so the ESP draws that model red), auto fire (left clicks through `VirtualInputManager` while there is a target and the menu is hidden). `aim.target` is the current target part for game files to read |
| `core/markers.lua` | Text-only world markers on the Drawing API, for things that aren't characters (corpses, loot). `markers.add(color, instances, label)` returns a group with `enabled`, `color`, `maxDistance` and `interval` (seconds between scans, default 1). `instances()` and `label(instance)` only run on a scan; `label` returns a heading and the text under it, or nil to skip. Between scans it re-checks distance 4 times a second from cached positions and only moves the labels per frame. `markers.start()` begins the loop. Game files start it and build the controls themselves |
| `universal.lua` | Features that work in any game. Starts the ESP and aim assist and returns `function(window)` that adds the Combat tab (aim assist) and the ESP tab (master toggle, one section per source, shared options) to a Bracket window, and returns `{ combat, esp }` so a game file can add sections to those tabs |
| `games/registry.lua` | Maps `game.GameId` (the universe, covers every place) to a game file |
| `games/<name>.lua` | One file per supported game, run with `hub` as `...`. Never requires another game file |
| `games/CLAUDE.md` | Per-game findings: ids, remote names, attribute names, Dex paths, quirks |

- Every fetched file starts with `local hub = ...` if it needs the hub. `hub.require(path)` caches the
  returned value, `hub.load(path)` runs a file fresh.
- Game files call `hub.require("universal.lua")(window)` to add the universal tabs before their own
  Misc / Eject tab. An unsupported game gets a "Universal" window with just those tabs and Eject.
- Only the Walking Dead Online loot filter is saved so far; the other settings reset on every load.
- The UI library is Bracket (`hub.bracket`), chosen by the user after testing. A different library or a
  custom UI needs asking first.
- Bracket builds its UI from the Roblox asset `rbxassetid://7141683860` through `game:GetObjects`
  (public domain, last updated by its owner in 2022). If that asset ever goes away the window won't build.
  Its callbacks fire once while controls are built, so game files guard their placeholders with a `ready` flag.
  A new colorpicker shows black until `:UpdateColor(color)` is called on it.
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
