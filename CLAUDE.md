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
  threads, hooks. `unload()` undoes all of it. A feature that can't be undone doesn't go in.
- Network fetches (the loader, game modules) use `request` and check `StatusCode`. The user's
  one-liner is the only place `game:HttpGet` is acceptable.
- The two expected pcalls are the fetch and the load of a game module, so a dead URL or a broken
  game file can't take the hub down. Report the failure with `warn` (and in the UI once the window exists), don't swallow it.
- Config is saved with `writefile` into a hub folder in the executor workspace, as JSON. Check
  `isfile` before `readfile`.
- When a game-specific instance or remote isn't found, notify with the missing path and skip the
  feature. Don't silently no-op, and don't guess a name: games rename things in updates.

## Layout

| Path | What |
|---|---|
| `loader.lua` | The only file users run. Holds the base-URL constant, builds the `hub` table (`load`, `require`, `cleanup`, `unload`, `ui`), looks the game up in the registry and runs its file |
| `core/cleanup.lua` | The cleanup list: `add(item)` for connections, instances, functions and threads, `run()` undoes them all |
| `core/ui.lua` | Custom window: `createWindow(title)` returns `section`, `button`, `notify`. Draggable, RightShift toggles it, X and the Eject button both call `hub.unload()` so the game doesn't need restarting between tests |
| `games/registry.lua` | Maps `game.GameId` (the universe, covers every place) to a game file |
| `games/<name>.lua` | One file per supported game, run with `hub` as `...`. Never requires another game file |
| `games/CLAUDE.md` | Per-game findings: ids, remote names, attribute names, Dex paths, quirks |

- Every fetched file starts with `local hub = ...` if it needs the hub. `hub.require(path)` caches the
  returned value, `hub.load(path)` runs a file fresh.
- Not written yet: `universal.lua` (features for any game, also for unsupported games) and the
  config save/load in `core/`. Unsupported games currently only get a `warn`.
- The UI is custom (`core/ui.lua`), no third-party library. Adding one needs asking first.
- Shared code lives in `core/`. Don't copy it between game files.

## Hosting

Public GitHub repo `hul1an/hul1ans-hub` (branch `main`), so everything pushed is world-readable: no
tokens, keys or private notes in it. The base URL is the single constant at the top of `loader.lua`.

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
placeholder window. Raw GitHub URLs are cached for a few minutes, so a test right after a push can still load the old files.
