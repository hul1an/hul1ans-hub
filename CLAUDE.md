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

**5. Changes are for the game being worked on only**, unless the user says otherwise.
A change asked for while working on one game must not alter what another game's window shows or does.
Changes that aren't about any game, such as the menu's style, are exempt.

## Executor rules

- Target is any executor at 100% sUNC. Only call functions sUNC covers. No executor-specific globals
  (`syn`, `fluxus`, `KRNL_LOADED`, ...). If it isn't certain a function is in sUNC, ask before using
  it. `identifyexecutor()` is for logging only, never for branching.
- Potassium's API docs are at `https://docs.potassium.pro`, with a page index at `/llms.txt`. They list
  functions beyond sUNC, among them `getproperties`, `decompile` and `saveinstance`; being listed there
  doesn't make one usable in the hub.
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
| `loader.lua` | The only file users run. Holds the repo constant, builds the `hub` table (`fetch`, `read`, `load`, `require`, `cleanup`, `unload`, `ui`), looks the game up in the registry and runs its file. In a game with no entry it warns and stops before anything else is fetched: no window, no features |
| `core/cleanup.lua` | The cleanup list: `add(item)` for connections, instances, functions and threads, `run()` undoes them all |
| `core/ui.lua` | The menu (`hub.ui`): a port of the "starline" CS2 menu's look from the static dump in `D:\intruigingFolder\zzzclaude\starline-dump-gui` (`docs/P22_gui_visual_spec.md` there is the spec). Built from GUI instances under `gethui()`, not Drawing. `ui.createWindow(title)` returns the window, `ui.visible()` says whether it is showing, `ui.notify(text, "error" | "success" | nil)` shows a toast for 5 s. RightShift toggles the window. `window:CreateTab(name, icon)` takes an icon name from the `ICONS` table; `tab:CreateSection(name, "LeftSide" | "RightSide")` goes to the shorter column without a side; `tab:CreateSubTab(name)` gives a page with its own `CreateSection`, and the bottom strip only shows once a tab has more than one. A section has `CreateLabel`, `CreateButton` (`:Remove()`), `CreateToggle` (`:CreateKeybind(bind)`, where a bind is a KeyCode name or `MouseButton1` to `3`; Roblox reports no side buttons; and `:CreateColorpicker(callback)`, a swatch on the same row just left of the box that opens the picker, returning an object with `:UpdateColor` and saved in configs as `<name> color`; it is made before a keybind so the chip sits left of it), `CreateSlider(name, min, max, default, precise, callback, format)`, `CreateDropdown` / `CreateMultiDropdown` (`:AddOption`, `:ClearOptions`), `CreateColorpicker` (`:UpdateColor`), `CreateTextBox(name, placeholder, numbersOnly, callback)` and `CreateGroup(name, default, callback)`, which returns a foldable container with the same methods and the row's own control as `.header` (the toggle when there is a callback, so a swatch or keybind goes on `group.header`); its chevron sits just after the name, as in starline. Every control has `:AddToolTip(text)` and `:Disable()`, which greys the row out and stops its clicks. The header's search steps through controls by name, and its save button opens the config popup. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/bracket.lua` | No longer loaded. Kept only until `core/ui.lua` has been seen working in Potassium, then delete it. Loads AlexR32's BracketV3 (archived, no license, so fetched at a pinned commit instead of copied) and returns `createWindow(title)`. Patches the library at load so its `RunService` / `UserInputService` connections are undone by `unload()`. Also adds an optional side to `tab:CreateSection(name, "LeftSide" | "RightSide")`; without it Bracket picks the shorter column. Two more patches: dropdowns get `:AddOption(name)` and buttons get `:Remove()`, neither of which Bracket has. RightShift toggles the window and `bracket.visible()` says whether it is showing. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/config.lua` | `config.load(name)` / `config.save(name, table)`: JSON files in the `hul1ans-hub` folder of the executor workspace. `load` returns nil when the file doesn't exist. `config.list(prefix)` gives the saved names that start with a prefix and `config.delete(name)` removes one |
| `games/bloxstrike/esp.lua` | BloxStrike's ESP engine on the Drawing API. `esp.settings` holds the shared options (enabled, and box, skeleton, chams, health bar and name each with a colour, `BoxColor` and so on; teammates are always left out), `esp.sources` the target lists, `esp.start()` begins the RenderStepped loop. Each source has its own `enabled`, `color`, `maxDistance` (10000 studs, no slider), `tracers`, `tracerColor` and `aim` (whether the aim assist may target it). A source added with a colour has everything but its tracer and health bar drawn in it; the players source has none, so its drawings take the element colours. Players are the built-in source; `main.lua` adds the Heard source with `esp.addSource(name, color, models, label)` before it calls `tabs.lua`. `models(skipTeammates)` gets the caller's team check; only the players source uses it, comparing `player.Team`. A source may also have `health(model)` returning health and max health (without it `esp.health` reads the model's Humanoid), `opacityOf(model)` returning 0 to 1 to fade its drawings (a Drawing's `Transparency` is its opacity, 1 by default), and `toggle` and `aimToggle`, the text of its toggles in the ESP tab and the Combat tab's Options card in place of "Show <name>" and "Target <name>", and `options(section)`, called with its ESP section right after its show toggle so `main.lua` can put its own controls there. `main.lua` overrides `esp.sources[1].models`, `.label` and `.health`, because the game's characters, teams and health aren't the Roblox defaults. The box is placed and sized from `HumanoidRootPart` (falling back to the model's bounding box when there is none), because a bounding box is thrown off by parts a game keeps elsewhere. Chams are `Highlight` instances in a folder under `gethui()`; skeleton lines are only created while Skeleton is on |
| `games/bloxstrike/aim.lua` | BloxStrike's aim assist and triggerbot, a port of the starline dump's native legit unit (`starline-src/features/combat/legit/` there, `docs/P18_combat_native.md` is its write-up). One step bound with `BindToRenderStep` just after the camera update. Targets come from `esp.sources` whose `aim` flag is set: players always, other sources opt-in. Each frame it takes the target with the best key (crosshair angle, health or distance) that has a visible point inside Max FOV, which is an angle in degrees, not pixels. The points are the centres of the chosen hitgroups' parts (`HITGROUPS` maps starline's seven groups to R15 and R6 part names; Stomach is `HumanoidRootPart`), plus points towards the parts' edges with Multipoint; a model with none of those parts is aimed at by its root. While Enabled is on `pull` turns the camera to the point, with no key to hold: a snap by default, with Smoothing starline's per-frame share, humanization and sticky. While `aim.settings.SilentAim` is on the camera is left alone and `main.lua`'s shot hook redirects shots to `aim.target`. The triggerbot left clicks through `VirtualInputManager` while the view ray passes through a target's part (or, with Silent Aim on, while the aim has a target at all), after its delay, visible delay and burst. `main.lua` sets `aim.spread`, a function returning how many degrees the next shot may leave the view ray by (nil with no gun out), for the trigger's Hitchance, which holds fire until that percentage of 96 sample shots over the spread would enter the target's trigger hitgroups, and Seeded with its Legitimacy slider, the share of the spread the trigger's own shots keep. The shot hook applies it by multiplying the spread by `aim.spreadScale()`, which is 1 for any shot more than 0.2 s after a trigger click. `main.lua` sets `aim.damage(part, distance)` the same way, returning what the next shot would do, for the trigger's Min Damage, which holds fire while the part under the crosshair (with Silent Aim, the aim's target part) would take less than the setting and less than the target's health. The aim always skips teammates (it asks every source for `models(true)`) and always checks visibility (a raycast from the camera that looks through fully invisible parts, since maps have invisible barrier walls); `aim.settings.MaxDistance` is fixed at 10000 studs. `aim.target` is the current target part. `main.lua` sets `aim.blocked`, a function that returns true while the aim and the triggerbot must stay off (dead or spectating) |
| `games/walking_dead_online/markers.lua` | Text-only world markers on the Drawing API, for things that aren't characters (corpses, loot). `markers.add(color, instances, label)` returns a group with `enabled`, `color`, `maxDistance` and `interval` (seconds between scans, default 1). `instances()` and `label(instance)` only run on a scan; `label` returns a heading and the text under it, or nil to skip. Between scans it re-checks distance 4 times a second from cached positions and only moves the labels per frame. `markers.start()` begins the loop. `main.lua` starts it and builds the controls itself |
| `games/bloxstrike/tabs.lua` | Was the shared `universal.lua`. Starts BloxStrike's ESP and aim assist and returns `function(window, features)`, which builds the whole window as starline's tree: aimbot › aimbot, assist · players › enemies, teammates, local, list · visuals › world, entities · changer › inventory · misc › general, movement · scripts › list, with the cards and widgets of the dump's `pages.json`. `features` is what `main.lua` has behind the pages: its `antiAim`, `visuals` and `movement` tables, `setNight` and `setThirdPerson`. The `off` helpers draw a starline control the hub has no code for: named `(placeholder)`, greyed out with `:Disable()`, callback `nothing`. `main.lua` calls it last, once everything in `features` exists |
| `games/walking_dead_online/esp.lua`, `aim.lua`, `tabs.lua` | The Walking Dead Online's own ESP, aim and tabs: the shared `core/esp.lua`, `core/aim.lua` and `universal.lua` exactly as they stood at commit `8734ac2` (2026-10-11 16:40, before that day's BloxStrike work), put back at the user's request with only the require paths changed. So that game still has what BloxStrike's copies lost or changed since: the aim's Team Check, Visibility Check, Max Distance and Target Color, each ESP source's Color row and Max Distance slider, the ESP's Team Check and Distance toggles and the distance text, one colour per source, and placeholders for the trigger's Seeded, Min Damage and Min Accuracy. The rows above describe BloxStrike's copies, not these |
| `assets/` | Files `core/ui.lua` fetches once and then reads from `hul1ans-hub/assets` in the executor workspace through `getcustomasset`, so a changed asset needs a new file name. `GeistMono-Medium.ttf` is the menu font (SIL OFL 1.1, licence in `OFL.txt`). `icons.png` is a sheet of the dump's 21 `sl-*` SVG icons drawn at twice their shown size, made with a throwaway script because Roblox can't render SVG |
| `tools/bridge.lua` | Dev tool, not part of the hub and Potassium only: lets Claude Code read the running game. It is started with `dofile("claude-bridge/bridge.lua")`, by the user or through Potassium's MCP server; it polls `claude-bridge/request.json` in the executor workspace, writes the answer to `response.txt` as plain text, then deletes the request. Ops are read-only: `ping`, `children` (`depth`), `inspect` (properties, attributes, tags), `find` (`name`, `class`, `show` for a property to print), `watch` (what is added under a path over `seconds`, optionally one `class`, with a Sound's id, its position and the nearest part named `nearName` under `near`), `decompile`. A `path` is a JSON list from `game` down, a child's name or its `GetChildren` index where the name isn't unique. Running it again, or deleting `claude-bridge/session`, stops the older loop. The workspace copy is made by hand, so copy it again after an edit |
| `tools/bridge.sh` | The sender, run from Git Bash: `sh tools/bridge.sh '{"op":"children","path":["Workspace"]}' [timeout]`. Prints the response, or fails after the timeout (30 s) when the bridge isn't running |
| `games/registry.lua` | Maps `game.GameId` (the universe, covers every place) to a game's `main.lua` |
| `games/<name>/` | One folder per supported game holding everything that game runs: `main.lua`, the file the registry names, run with `hub` as `...`, and whatever else it needs (`esp.lua`, `aim.lua`, `tabs.lua`, ...). Nothing in one game's folder is required from another's |
| `games/CLAUDE.md` | Per-game findings: ids, remote names, attribute names, Dex paths, quirks |
| `matcha/` | The hub as it was before the games were separated, for Matcha, an external LuaVM executor that hooks nothing and can't create instances; what that takes away and the adapter's mapping are in `matcha/CLAUDE.md` |

- Every fetched file starts with `local hub = ...` if it needs the hub. `hub.require(path)` caches the
  returned value, `hub.load(path)` runs a file fresh.
- Game scripts are entirely separate (decided by the user on 2026-10-11): there are no universal features,
  and the loader runs nothing in a game that has no entry in the registry. `core/` holds only what isn't a
  feature of any game: the menu, cleanup and config. ESP, aim and the tabs built on them belong to a game
  and live in its folder, each game with its own copy, so a change to one game's copy is not carried to
  another's. `matcha/` was not restructured and still has its own shared files and Universal window.
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
- Seeded and Hitchance (asked for by the user on 2026-10-11) take the place of the trigger's Seeded and Min
  Accuracy placeholders in BloxStrike's Combat tab; The Walking Dead Online's keeps the placeholders. Seeded is not
  starline's: the user asked for the trigger to fire when the spread seed lands on a hitbox, and where the seed
  can't be read (BloxStrike) for a Legitimacy slider instead, 0% removing the spread, 100% leaving it alone so
  that only Hitchance decides. Restricted and Strength are not drawn beside it. The trigger's Min Damage
  (asked for the same day) is real in BloxStrike; the Accuracy card's Min Damage is still a placeholder. A shot that would kill passes whatever the setting (asked for by the user). Hitchance is measured on the
  gun's real spread, not on what Legitimacy leaves (asked for by the user the same day: Seeded must not fire
  where a regular shot wouldn't pass), and is skipped with Silent Aim on.
- BloxStrike's window is starline's whole menu (asked for by the user on 2026-10-11: recreate it as closely as possible,
  grey out and label what the hub has no code for, keep the empty pages). Every name and option is lowercase as
  starline's are, so the option values in BloxStrike's `aim.lua` and anti-aim are lowercase too (`"head"`,
  `"crosshair"`, `"at targets"`). Where the hub's own features went: anti-aim on aimbot › aimbot (the dump has no cards
  for that page), the `options` card on assist, a card per ESP source on players › enemies, `night mode` in world ›
  general, `hit effect` in effects, `eject` in misc › general › main. Starline rows with hub code behind them: the esp
  card's enabled, bounding box, name, skeleton and health bar, the chams card's glow (the hub's Highlight chams),
  bullet tracers with size and time, third person with distance (in studs, not starline's 50 to 160), auto jump (Bhop).
- The players sub-tabs enemies / teammates / local / list and the enemies page's rows are from the user's screenshot
  of the real menu; the dump has one esp and one chams page with a name set at run time. Guessed: teammates has the
  enemies rows and local every chams row in the dump. Not drawn: the rows the dump hangs under name, weapon icon,
  health bar and ammo bar (font, invert, display value, hp scaled color, shadow), which the screenshot shows with no
  fold; ragdoll's second material and what the dump hangs under attachments overlay; the `chams finish` page, which no
  tab leads to; two checkboxes whose labels didn't decode (world › general, view); the swatch on scope overlay; and
  the viewmodel changer's side-by-side pairs, drawn as six rows.
- Kept in the Combat tab though starline has no such thing: the Enabled keybind, BloxStrike's Silent Aim
  toggle, and the Options card, which in BloxStrike is only the per-source target toggles.
- Removed from BloxStrike's copies by the user on 2026-10-11: the Max Distance sliders of the aim
  and of each ESP source, both limits now fixed at 10000 studs; Target Color, with `esp.highlight`; and the
  aim's Team Check and Visibility Check toggles, both now always on (the user: team check needs no toggle,
  and Auto Wall off is the visibility check). A dynamic FOV shrinks over its own 500 studs (`FOV_RANGE`), the
  range it had while the aim's limit was 500. Later the same day: the ESP's Team Check toggle (teammates are always left out), its
  Distance toggle and then the distance text itself, and BloxStrike's Team Colors, with `colorOf` on a source. In their place each ESP element
  has its own colour, and colour pickers attach to a toggle's row; Draw FOV and BloxStrike's Bullet Tracers
  carry theirs that way too. The health bar's colour is the one at full health and it still runs to red. None of this
  applies to The Walking Dead Online's copies or to `matcha/`.
- Removed by the user on 2026-10-10: hold right mouse to aim (the aim is on whenever Enabled is) and Auto
  Fire (the triggerbot took its place). Auto Fire clicked whenever there was a target in the FOV, which is
  what paired with silent aim, so with Silent Aim on the triggerbot does the same, with its delays; without
  it the triggerbot only clicks with the crosshair on a part.
- Silent Aim on means no camera pull. That was not asked for in so many words: it keeps silent aim as it
  was before the aim became always on, when the camera only moved with right mouse held.
- Not in the dump, chosen for the port: every default (the dump has ranges only; they are set so the aim
  snaps as it did before: smoothing off, mouse override 100%), FOV Mode's option names Static / Dynamic
  (only modes 0 and 1 are known), the hitgroup to part map, the trigger's 6 stud reach, and the jump
  disabler's ground ray (BloxStrike characters have no Humanoid to ask). A dynamic FOV is scaled against
  Roblox's default field of view of 70 where starline uses 90.
- `pull` in each game's `aim.lua` measures the user's own mouse movement from the view it wrote last frame or from
  the view the game showed before that, whichever the new view is nearer, because a game with its own
  camera script hands back its own angles and the default camera hands back the written ones.

## Hosting

Public GitHub repo `hul1an/hul1ans-hub` (branch `main`), so everything pushed is world-readable: no
tokens, keys or private notes in it. The repo name is the `REPO` constant at the top of `loader.lua`.
Raw branch URLs are cached for 5 minutes and ignore query strings, so a `?t=` cache-buster does nothing.
The loader asks the GitHub API for the latest commit of `main` and fetches every hub file by that commit
hash, falling back to `main` if the API call fails (unauthenticated limit is 60 per hour per IP). The
user's one-liner for `loader.lua` itself can't do that: after a push use the commit hash in its URL, or
wait out the cache.

Commit and push finished changes straight to `main` without asking (told by the user on 2026-10-11): the
loadstring is how they run anything, so a change that isn't pushed can't be tested.

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

The starline combat port (then `core/aim.lua` and the Combat tab in `universal.lua`, now each game's `aim.lua` and
`tabs.lua`) was written the same day and
has not been run either. It replaced the aim core that was confirmed in BloxStrike, so everything that
goes through it is open again: target selection and FOV in degrees, the hitgroups, multipoint, smoothing /
humanization / sticky in a game with its own camera script, switch delay, mouse override, the jump
disabler, the triggerbot, and that silent aim still gets its target from `aim.target`. Mouse buttons as
keybinds in `core/ui.lua` are written and not run as well.

The trigger's Seeded (Legitimacy), Hitchance and Min Damage were written on 2026-10-11 with BloxStrike's
spread and damage figures behind them and have not been run.

`tools/bridge.lua` was run in BloxStrike on 2026-10-11 and all five ops answered. Potassium's workspace is
`%LOCALAPPDATA%\Potassium\workspace`.

Potassium's own MCP server (Settings, Agent Access, `http://127.0.0.1:8225/mcp`) was connected the same
day through a project `.mcp.json`. That file holds the bearer token, so it is in `.gitignore` and must
stay out of the repo. Its tools are `list_clients`, `execute_script` and `read_console`. Claude Code has
used `execute_script` only to start the bridge; running the hub through it hasn't been agreed with the
user. With Potassium set to redirect output and errors to its console, `read_console` returns `print`, `warn`
and `error()` with its stack. The setting only takes full effect after the game is rejoined: before
that only errors came through.

BloxStrike's starline menu tree, `:Disable()`, the group chevron after the name and `group.header` were written on
2026-10-11 and have not been run. Open: whether a row's cover stops its clicks, whether `TextBounds` places the
chevron (it is divided by the window's `UIScale`), and how the long `(placeholder)` names fit. BloxStrike configs
saved before it no longer load, since every control's path changed.

The Matcha port in `matcha/` was written on 2026-10-11 against its documented API and has not been run.

The split into per-game folders and the loader stopping in unlisted games were written on 2026-10-11 and
have not been run. The Walking Dead Online's `esp.lua`, `aim.lua` and `tabs.lua` have not been run in that
game either: they date from after the starline combat port.
