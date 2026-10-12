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
- A hooked game function runs our code on the game's thread, with the game's permissions: it can't create or touch
  anything under `gethui()` (`The current thread cannot access 'Instance' (lacking capability Plugin)`, seen in
  BloxStrike's shot hook on 2026-10-11). A hook hands such work to a connection the hub made itself.
- Config is saved with `writefile` into a hub folder in the executor workspace, as JSON. Check
  `isfile` before `readfile`.
- When a game-specific instance or remote isn't found, notify with the missing path and skip the
  feature. Don't silently no-op, and don't guess a name: games rename things in updates.

## Layout

| Path | What |
|---|---|
| `loader.lua` | The only file users run. Holds the repo constant, builds the `hub` table (`fetch`, `read`, `load`, `require`, `cleanup`, `unload`, `ui`), looks the game up in the registry and runs its file. In a game with no entry it warns and stops before anything else is fetched: no window, no features |
| `core/cleanup.lua` | The cleanup list: `add(item)` for connections, instances, functions and threads, `run()` undoes them all |
| `core/ui.lua` | The menu (`hub.ui`), and `ui.asset(name)`, which gives a file under `assets/` as an asset id for a game's own use: a port of the "starline" CS2 menu's look from the static dump in `D:\intruigingFolder\zzzclaude\starline-dump-gui` (`docs/P22_gui_visual_spec.md` there is the spec). Built from GUI instances under `gethui()`, not Drawing. `ui.createWindow(title)` returns the window, `ui.visible()` says whether it is showing, `ui.notify(text, "error" | "success" | nil)` shows a toast for 5 s. `ui.log(text)` adds a line at the lower left, where the game's chat is: the brand in the accent, ` » ` and the text, gone after 6 s. RightShift toggles the window. `window:CreateTab(name, icon)` takes an icon name from the `ICONS` table; `tab:CreateSection(name, "LeftSide" | "RightSide")` goes to the shorter column without a side; `tab:CreateSubTab(name)` gives a page with its own `CreateSection`, and the bottom strip only shows once a tab has more than one. A section has `CreateLabel`, `CreateButton` (`:Remove()`), `CreateToggle` (`:CreateKeybind(bind)`, where a bind is a KeyCode name or `MouseButton1` to `3`; Roblox reports no side buttons; and `:CreateColorpicker(callback, alpha)`, a swatch on the same row just left of the box that opens the picker, returning an object with `:UpdateColor(color, opacity)` and saved in configs as `<name> color`; with `alpha` the picker shows an opacity bar under the square, the callback gets the opacity (0 to 1) after the colour, and the config value is eight hex digits; it is made before a keybind so the chip sits left of it), `CreateSlider(name, min, max, default, precise, callback, format)`, `CreateDropdown` / `CreateMultiDropdown` (`:AddOption`, `:ClearOptions`), `CreateColorpicker` (`:UpdateColor`), `CreateTextBox(name, placeholder, numbersOnly, callback)` and `CreateGroup(name, default, callback)`, which returns a foldable container with the same methods and the row's own control as `.header` (the toggle when there is a callback, so a swatch or keybind goes on `group.header`); its chevron sits just after the name, as in starline. Every control has `:AddToolTip(text)` and `:Disable()`, which greys the row out and stops its clicks. The header's search steps through controls by name, and its save button opens the config popup. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/bracket.lua` | No longer loaded. Kept only until `core/ui.lua` has been seen working in Potassium, then delete it. Loads AlexR32's BracketV3 (archived, no license, so fetched at a pinned commit instead of copied) and returns `createWindow(title)`. Patches the library at load so its `RunService` / `UserInputService` connections are undone by `unload()`. Also adds an optional side to `tab:CreateSection(name, "LeftSide" | "RightSide")`; without it Bracket picks the shorter column. Two more patches: dropdowns get `:AddOption(name)` and buttons get `:Remove()`, neither of which Bracket has. RightShift toggles the window and `bracket.visible()` says whether it is showing. Every game window should end with an Eject button that calls `hub.unload()` so the game doesn't need restarting between tests |
| `core/config.lua` | `config.load(name)` / `config.save(name, table)`: JSON files in the `hul1ans-hub` folder of the executor workspace. `load` returns nil when the file doesn't exist. `config.list(prefix)` gives the saved names that start with a prefix and `config.delete(name)` removes one |
| `games/bloxstrike/esp.lua` | BloxStrike's ESP engine on the Drawing API. `esp.settings` holds the enemies' options (enabled, and box, skeleton, health bar and name each with a colour, `BoxColor` and so on), `esp.sources` the sources of the enemies' page, which the aim picks its targets from, `esp.start()` begins the RenderStepped loop. Each source has its own `enabled`, `color`, `maxDistance` (10000 studs, no slider) and `aim` (whether the aim assist may target it). A source added with a colour has everything but its health bar drawn in it; the players source has none, so its drawings take the element colours. Players are the built-in source; `main.lua` adds the Heard source with `esp.addSource(name, color, models, label)` before it calls `tabs.lua`. `models(skipTeammates)` gets the caller's team check; only the players source uses it, comparing `player.Team`. A source may also have `health(model)` returning health and max health (without it `esp.health` reads the model's Humanoid), `opacityOf(model)` returning 0 to 1 to fade its drawings (a Drawing's `Transparency` is its opacity, 1 by default), and `toggle` and `aimToggle`, the text of its toggles in the ESP tab and the Combat tab's Options card in place of "Show <name>" and "Target <name>", and `options(section)`, called with its ESP section right after its show toggle so `main.lua` can put its own controls there. `main.lua` overrides `esp.sources[1].models`, `.label` and `.health`, because the game's characters, teams and health aren't the Roblox defaults. The box is placed and sized from `HumanoidRootPart` (falling back to the model's bounding box when there is none), because a bounding box is thrown off by parts a game keeps elsewhere. The chams card is all here too (see the chams bullets below): its Highlights are in a folder under `gethui()` and its copies in a folder under the camera; skeleton lines are only created while Skeleton is on. A source may also have `weapon(model)` (name, icon, rounds left, rounds a magazine takes), `avatar(model)` (an image) and `flags(model, kinds)` (the texts of the chosen flags that apply), which `main.lua` sets on the players source for the weapon name, weapon icon, ammo bar, avatar and flags; the avatar and the icon are ImageLabels in a ScreenGui under `gethui()`, because a Drawing image can't show a Roblox asset. `esp.visible(camera, point, model)` is the line of sight check, which the aim uses too. `main.lua` writes `esp.audible[model]` and calls `esp.sound(position, source)` from its sound listeners, for only audible and the sound marks. `esp.teammates` and `esp.own` are two more sources, kept out of `esp.sources`: each has a `settings` table of its own with the enemies' keys (every source has `settings`, the others' being `esp.settings`), takes whatever `main.lua` sets on the players source through a metatable, and has its `models` set by `main.lua`. `main.lua` also sets `esp.ragdolls()`, the ragdolls in use each with its source, and `esp.gear()`, the parts the local page's viewmodel, weapon and attachments rows change, by the model they are in |
| `games/bloxstrike/aim.lua` | BloxStrike's aim assist and triggerbot, a port of the starline dump's native legit unit (`starline-src/features/combat/legit/` there, `docs/P18_combat_native.md` is its write-up). One step bound with `BindToRenderStep` at the camera's own priority (see `games/CLAUDE.md` for why not after it). Targets come from `esp.sources` whose `aim` flag is set: players always, other sources opt-in. Each frame it takes the target with the best key (crosshair angle, health or distance) that has a visible point inside Max FOV, which is an angle in degrees, not pixels. The points are the centres of the chosen hitgroups' parts (`HITGROUPS` maps the hub's seven groups to R15 part names: head, upper torso, lower torso, arms, hands, legs, feet), plus points towards the parts' edges with Multipoint; a model with none of those parts is aimed at by its root. While Enabled is on `pull` turns the camera to the point, with no key to hold: a snap by default, with Smoothing starline's per-frame share, humanization and sticky. While `aim.settings.SilentAim` is on the camera is left alone and `main.lua`'s shot hook redirects shots to `aim.target`. The triggerbot left clicks through `VirtualInputManager` while the view ray passes through a target's part (or, with Silent Aim on, while the aim has a target at all), after its delay, visible delay and burst. `main.lua` sets `aim.spread`, a function returning how many degrees the next shot may leave the view ray by (nil with no gun out), for the trigger's Hitchance, which holds fire until that percentage of 96 sample shots over the spread would enter the target's trigger hitgroups, and Seeded with its Legitimacy slider, the share of its spread every shot keeps. The shot hook applies it by multiplying every shot's spread by `aim.spreadScale()`. `main.lua` sets `aim.damage(part, distance)` the same way, returning what the next shot would do, for the trigger's Min Damage, which holds fire while the part under the crosshair (with Silent Aim, the aim's target part) would take less than the setting and less than the target's health. The aim always skips teammates (it asks every source for `models(true)`) and checks visibility unless Auto Wall is on (a raycast from the camera that looks through fully invisible parts, since maps have invisible barrier walls); `aim.settings.MaxDistance` is fixed at 10000 studs. `aim.target` is the current target part. `main.lua` sets `aim.blocked`, a function that returns true while the aim and the triggerbot must stay off (dead or spectating) |
| `games/walking_dead_online/markers.lua` | Text-only world markers on the Drawing API, for things that aren't characters (corpses, loot). `markers.add(color, instances, label)` returns a group with `enabled`, `color`, `maxDistance` and `interval` (seconds between scans, default 1). `instances()` and `label(instance)` only run on a scan; `label` returns a heading and the text under it, or nil to skip. Between scans it re-checks distance 4 times a second from cached positions and only moves the labels per frame. `markers.start()` begins the loop. `main.lua` starts it and builds the controls itself |
| `games/bloxstrike/tabs.lua` | Was the shared `universal.lua`. Starts BloxStrike's ESP and aim assist and returns `function(window, features)`, which builds the whole window as starline's tree: aimbot › aimbot (general, targeting, behavior, accuracy), assist (triggerbot, rcs) · players › enemies, teammates, local, list · visuals › world, entities · changer › inventory · misc › general, movement · scripts › list, with the cards and widgets of the dump's `pages.json`. `features` is what `main.lua` has behind the pages: its `visuals` and `movement` tables, `setNight` and `setThirdPerson`. The `off` helpers draw a starline control the hub has no code for: named `(placeholder)`, greyed out with `:Disable()`, callback `nothing`. `main.lua` calls it last, once everything in `features` exists |
| `games/walking_dead_online/esp.lua`, `aim.lua`, `tabs.lua` | The Walking Dead Online's own ESP, aim and tabs: the shared `core/esp.lua`, `core/aim.lua` and `universal.lua` exactly as they stood at commit `8734ac2` (2026-10-11 16:40, before that day's BloxStrike work), put back at the user's request with only the require paths changed. So that game still has what BloxStrike's copies lost or changed since: the aim's Team Check, Visibility Check, Max Distance and Target Color, each ESP source's Color row and Max Distance slider, the ESP's Team Check and Distance toggles and the distance text, one colour per source, and placeholders for the trigger's Seeded, Min Damage and Min Accuracy. The rows above describe BloxStrike's copies, not these |
| `assets/` | Files `core/ui.lua` fetches once and then reads from `hul1ans-hub/assets` in the executor workspace through `getcustomasset`, so a changed asset needs a new file name. `GeistMono-Medium.ttf` is the menu font (SIL OFL 1.1, licence in `OFL.txt`). `icons.png` is a sheet of the dump's 21 `sl-*` SVG icons drawn at twice their shown size, made with a throwaway script because Roblox can't render SVG. `weather-streak.png`, `weather-dot.png` and `weather-leaf.png` are BloxStrike's precipitation textures, white shapes a ParticleEmitter tints, made the same way. The streak runs left to right: a `VelocityParallel` particle has its texture's horizontal along the way it moves (the first one, drawn top to bottom, fell as sideways dashes, seen by the user on 2026-10-12) |
| `tools/bridge.lua` | Dev tool, not part of the hub and Potassium only: lets Claude Code read the running game. It is started with `dofile("claude-bridge/bridge.lua")`, by the user or through Potassium's MCP server; it polls `claude-bridge/request.json` in the executor workspace, writes the answer to `response.txt` as plain text, then deletes the request. Ops are read-only: `ping`, `children` (`depth`), `inspect` (properties, attributes, tags), `find` (`name`, `class`, `show` for a property to print), `watch` (what is added under a path over `seconds`, optionally one `class`, with a Sound's id, its position and the nearest part named `nearName` under `near`), `decompile`, `module` (what a ModuleScript returns from `require`, a table's fields one level down). A `path` is a JSON list from `game` down, a child's name or its `GetChildren` index where the name isn't unique. Running it again, or deleting `claude-bridge/session`, stops the older loop. The workspace copy is made by hand, so copy it again after an edit |
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
  typing a slider's value, and the picker's RGB sliders. The picker's alpha bar was left out too until the user asked
  for it on 2026-10-11: it is opt-in per swatch (a toggle's, a group header's, or the stand-alone
  `CreateColorpicker(name, callback, alpha)` row), so a colour whose feature has no opacity shows no bar. It is the hub's own draw, the
  colour fading in from the left; the dump only has the bar's address. In BloxStrike every chams colour has it
  (asked for by the user on 2026-10-11): each row's own (the parts' `Transparency`, or a Highlight's; glass is half
  see-through at full opacity), `glow`, on hit's `glow`, and the backtrack gradient's `oldest` and `newest`, whose
  opacities run across the ticks as the colours do. Wiring it to the ESP's other colours is Claude's to offer, not
  asked for.
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
  (asked for the same day) is real in BloxStrike; the Accuracy card's Min Damage is auto wall's, below. A shot that would kill passes whatever the setting (asked for by the user). Hitchance is measured on the
  gun's real spread, not on what Legitimacy leaves (asked for by the user the same day: Seeded must not fire
  where a regular shot wouldn't pass), and is skipped with Silent Aim on.
- BloxStrike's window is starline's whole menu (asked for by the user on 2026-10-11: recreate it as closely as possible,
  grey out and label what the hub has no code for, keep the empty pages). Every name and option is lowercase as
  starline's are, so the option values in BloxStrike's `aim.lua` are lowercase too (`"head"`,
  `"static"`), and target selection's crosshair option is `fov`, starline's name for it. Where the hub's own
  features went: `silent aim` with the sources' aim toggles (`dormant aimbot`) under it in aimbot › aimbot's general card (the
  `options` card went on 2026-10-11, at the user's request), a card per ESP source but the players on players › enemies (the players card, show players and tracers, went
  on 2026-10-11 at the user's request as redundant, and the ESP's tracers with it: the user doesn't want them, so the
  heard card lost its row too, which is Claude's reading), `night mode` in world ›
  general, `hit effect` in effects, `eject` in misc › general › main. Starline rows with hub code behind them: the esp
  card's enabled, bounding box, name, skeleton and health bar, the chams card's glow (the hub's Highlight chams),
  bullet tracers with size and time, third person with distance (in studs, not starline's 50 to 160), auto jump (Bhop).
- Which aimbot cards are on which sub-tab and in which column is from the user's screenshots of both pages: general
  and targeting left, behavior and accuracy right on aimbot; triggerbot left and rcs right on assist. The strip of
  weapon presets under the header (shared, pistols, smgs, ...) is the preset chips, still left out.
- Anti-aim was removed from BloxStrike entirely by the user on 2026-10-11; its code is in commit `66f0eaa`.
- The players sub-tabs enemies / teammates / local / list and the enemies page's rows are from the user's screenshot
  of the real menu; the dump has one esp and one chams page with a name set at run time. Guessed: teammates has the
  enemies rows and local every chams row in the dump. Not drawn: the rows the dump hangs under name, weapon icon,
  health bar and ammo bar (font, invert, display value, hp scaled color, shadow), which the screenshot shows with no
  fold; ragdoll's second material and what the dump hangs under attachments overlay; the `chams finish` page, which no
  tab leads to; two checkboxes whose labels didn't decode (world › general, view); the swatch on scope overlay; and
  the viewmodel changer's side-by-side pairs, drawn as six rows.
- Every row of the esp card on players › enemies is real (asked for by the user on 2026-10-11); teammates and local
  followed on 2026-10-12, below. What the dump doesn't say and Claude chose:
  - `only visible` and `only audible` only filter the players source, not heard ghosts. Visible is a line from the
    camera to the head; audible is a sound from that enemy in the last second (`AUDIBLE_TIME`).
  - `flags` has no options in the dump. The hub's are `money`, `armor` (`HK` or `K`), `kit` (defuse or rescue),
    `scoped` and `bot`, drawn down the box's right side. No bomb flag: where the carrier shows wasn't looked for.
  - `sounds` marks every footstep and shot of an enemy, shown or hidden, for a second. `draw type` has no options in
    the dump: `circle` is the radius in pixels, `ring` the radius in CS2 units at the sound's distance, growing as it
    fades. Both are a Drawing circle facing the camera, not one lying on the ground.
  - `offscreen arrows` are for a model whose middle is off screen, heard ghosts included. They sit on an ellipse along
    the screen's edges, `offset` pixels in from it, and `size` is the arrow's length and width. The shadow is the
    arrow again 2 pixels down and right.
  - The ammo bar is the rounds left over the magazine's, under the box, then the weapon name, then the icon in a 48
    by 16 box. The avatar is 14 pixels, left of the name. Bots get none of these but the `bot` flag.
- The chams card's `visible` row is real on players › enemies (asked for by the user on 2026-10-11, with the
  materials solid, flat, glow, ghost and glass, each taking the row's colour). The user chose to change the enemy's
  own parts over drawing copies. `solid` is the model's Highlight with an opaque fill, depth tested; the others set
  the `Material` and `Color` of the body and armour parts (`SmoothPlastic`, `Neon`, `ForceField`, `Glass` at half
  opacity) after taking the skin off: each part's `SurfaceAppearance` is unparented, its `TextureID` cleared and the
  face decals hidden, all kept in `skins` and put back when the row goes off, the enemy leaves the list or the hub
  unloads. Weapons a character carries and parts that are invisible are left alone. A model shows one Highlight
  with one depth mode, so while `glow` is on a solid fill shows through walls with the outline.
- The `glow` row, the hub's first chams (a Highlight outline through walls on the enemy itself), was removed from the
  enemies page by the user on 2026-10-12 because it conflicts with invisible chams: two Highlights on one silhouette,
  of which Roblox draws the nearer. `esp.settings.Chams` and its colour went with it. Invisible's `glow` material
  and on hit's `glow` are still there. Mentions of the glow row elsewhere in this file are from before that.
- The rest of the enemies chams card is real too (asked for by the user on 2026-10-11); teammates and local followed
  on 2026-10-12, below. Roblox can't draw a part over a wall (only a Highlight, an always-on-top adornment or something in
  screen space can be). The first version drew copies in two full-screen `ViewportFrame`s to get materials through
  walls (commit `3d284a8`); the user had it removed the same day as too heavy, and for now a row that shows through
  walls only offers what a Highlight can draw: `solid`, its fill, and `glow`, its outline. Copies are `part:Clone()`
  with the children destroyed, kept in a folder under the camera. How each row is done is Claude's:
  - `invisible` (solid, glow): a Highlight through walls on copies welded to the body. It is on copies and not the
    model so that a part the camera has a line to can be left out (its copy fully transparent, which a Highlight
    skips), leaving the model and the visible chams to show there. A copy out of sight is opaque in the row's
    colour, with the wall in front of it; it was 0.99 transparent at first, changed after the user reported nothing
    drawing, in case a Highlight leaves such a part out. That is a ray a part, every 0.1 s (`SIGHT_TIME`). A screenshot from
    the user on 2026-10-12 showed six enemies behind walls with the glow row's outline and no invisible fill, and the
    next round two of the lobby had it; the bridge showed every enemy with its copies in place and a Highlight on
    them. Taken to be two Highlights on one silhouette, the copy's and the body's (the glow row's, or the game's own
    on spectated players), of which Roblox draws one a pixel: the copies are now 1.03 times the size (`COVER`) so
    theirs is the nearer, and it draws the glow row's outline itself. Seen working by the user on 2026-10-12 after that
    change, so where two Highlights overlap Roblox does draw only the nearer.
  - `overlay` (flat, glow, ghost, glass): copies 1.05 times the size, each welded to its part so it has no lag.
  - `ragdoll` (all five): the enemies' ragdolls from `esp.ragdolls` (set by `main.lua`), painted as visible chams
    paint, or a Highlight fill for solid.
  - `backtrack` (flat, glow, ghost, glass): copies standing in the world at the places in `esp.past`, the aim's
    backtrack records, which the aim keeps while either its backtrack or this row is on, over the aim's `amount`.
    Walls hide it. Seen working by the user on 2026-10-11, with per tick a massive performance hit: every copy was
    moved every frame, and the set of records drawn changed every frame, since it was counted from the oldest. Now
    a record is taken once a tick and its copy put down once and left, so the cost is a tick's fifteen moves, plus a
    recolour of every copy a tick with the gradient on. Run again by the user, it still halved the frame rate: the
    copies were out for every enemy on the list (everyone, while spectating). At the user's request they are now only
    out for an enemy whose head is on screen and in the camera's sight; the rest keep their records and have their
    copies unparented. Not run since. Through walls it
    would be one Highlight a tick, past the 31 Roblox draws, or one for the whole trail in one colour, which the
    gradient rules out. The oldest record only; with `per tick` (asked for by the user) one for every 1/60 s on
    record but the present; with its `gradient` (also asked for) the colours run from `oldest` to `newest`, two
    colour rows in the per tick fold, in place of the row's own colour. Armour isn't recorded, so a backtrack copy is
    the fifteen body parts.
  - `on hit` (all five): when a shot of the user's has hurt an enemy (the hit logs' check, which now also runs with
    the row on) `esp.flash` stands a copy in the world in the pose from when the shot was fired, 1.05 times the size,
    fading over `duration`; its `glow` is a Highlight outline through walls and solid a Highlight fill. One a victim
    at a time.
- The teammates and local pages of the players tab are real (asked for by the user on 2026-10-12, with: remove anything
  that would add to the 31 Highlight limit). Each page has options of its own, `esp.teammates.settings` and
  `esp.own.settings`. What Claude chose:
  - The removal was taken to be on those two pages; the enemies' page keeps its Highlight rows. Not drawn on the other
    two: `invisible`, the `solid` material, on hit's `glow` and the old `glow` row. Their visible, ragdoll and on hit
    materials are flat, glow, ghost and glass.
  - The local page's esp card and its body chams only draw while the hub's third person is on (`esp.own.models` is
    empty otherwise): in first person there is no body to see.
  - `only audible` and `sounds`: a teammate's sounds are told as an enemy's are. The user's own are the footstep and
    shot sounds the game puts under the user's character; where the user's own shots play wasn't seen.
  - `backtrack`: the aim only records its targets, so `esp.lua` keeps the teammates' and the user's records itself, over
    0.2 s (`BACKTRACK_TIME`, the aim's longest) whatever the aim's `amount` is.
  - `on hit`: a drop in the model's health, whoever caused it, in the pose it has then. The enemies' is still a shot of
    the user's.
  - `ragdoll`: the user's own corpse is now the local page's; it counted as an enemy's while the user spectated.
  - Local `viewmodel` is the first person arms with their sleeves and gloves, `weapon` the gun in the viewmodel and in
    third person the one in the character's hands, `attachments` what the character carries on its body, third person
    only. Each row paints the parts and each `overlay` row puts copies on them. Starline's three names were mapped to
    the game this way by Claude.
  - The game hides a holstered gun and a scoped sniper's viewmodel by setting Transparency to 1 and shows them again at
    their own, so `paint` leaves a part hidden since it was painted alone and repaints one shown again, and an overlay
    copy on gear is hidden with its part (and with the viewmodel in the hub's third person).
  - The known fault of visible chams, the game's ragdolls being cloned in the paint, now goes for teammates too, and
    for the user in third person.
- The general card of visuals › world (asked for by the user on 2026-10-12: start work on it) has skybox,
  precipitation and fog real, and no wetness row. All three are in `main.lua`, read from its `visuals` table
  every frame and undone on unload. What Claude chose:
  - `skybox`: the dump has no list, so the choices are the skies of the game's own maps, by map name. The Sky in
    Lighting gets the chosen one's textures, sun, moon and stars; the rest of the map's lighting is left alone.
  - `precipitation`: a ParticleEmitter a type on an invisible plate 35 studs over the camera, with three textures of the
    hub's own (`assets/weather-*.png`). `particles` is how many are in the air at once, shared between the chosen
    types. Particles don't stop at a roof, so `outdoors only` only stops them while something is straight above the
    camera. Every speed, size and colour is a guess at a look.
  - `fog`: Roblox's own fog, in the game's fog colour. `start` and `end` are CS2 units as in starline; `density` is how
    much is hidden at `end`, the fog going on thickening past it since Roblox's can't stop short. The game's
    Atmosphere switches that fog off, so it is held out of Lighting while the row is on, which also takes its haze away.
  - `wetness` was removed from the card by the user on 2026-10-12 as not possible: most of a map is MeshParts under a
    `SurfaceAppearance`, which a script can't make shinier, so raising `Reflectance` would only wet the plain parts.
- Auto Wall (asked for by the user on 2026-10-11) is real in BloxStrike, for the aim (`AutoWall`) and the trigger
  (`TriggerAutoWall`): a point out of sight still counts when `aim.pierces(origin, point, model)` says the gun out
  would shoot through to it. `main.lua` sets that from the game's own bullet ray (see `games/CLAUDE.md`). A shot
  through something has its Min Damage figure multiplied by the gun's `WallbangMultiplier` once. The accuracy card's
  `min damage` (`MinDamage`, asked for as "autowall min damage" the same day) is the aim's: a point is left alone
  when the shot would do less than the setting and less than the target's health. At first that only held for a point
  reached through something, Claude's reading of the request; on 2026-10-12 the user reported the aim taking
  hitboxes that wouldn't do the damage set, and it now holds in plain sight too. With no gun out there is no figure
  and every point passes. With Silent Aim on
  the trigger follows the aim's target, so the aim's Auto Wall is the one that counts. A trigger Visible Delay above
  0 still needs the target to have been in sight, so it holds fire on a target only reachable through a wall.
- BloxStrike's hitgroups are the R15 body's (asked for by the user on 2026-10-11, to reflect Roblox anatomy), not
  starline's chest / stomach / pelvis: head, upper torso, lower torso, arms, hands, legs, feet. The root part is in
  none, since the game's bullets pass through it, and the R6 names went. Force baim and baim if lethal aim at the two
  torsos.
- Baim if lethal, auto scope and auto stop (asked for by the user on 2026-10-11) are real in BloxStrike. Baim if lethal
  tries the body first when `aim.damage` says a shot to the upper torso would kill, and falls back to the chosen
  hitgroups. Auto scope calls `aim.scope()`, set by `main.lua`: the aim's whenever it has a target, the trigger's when
  a target is under the crosshair, holding fire until the sniper is zoomed. Auto stop is on with any of its options
  chosen (Claude's reading; starline has no plain option): `aim.stopping` is set while a target is under the
  crosshair and the gun could fire (`aim.ready()`, set by `main.lua`: not `IsShooting`, not `IsReloading`, rounds
  left), and `main.lua`'s movement hook counter-strafes. `between shots` drops the could-fire condition (asked for
  by the user after running it: without the option it must not stay stopped between shots), `early` also sets it
  with a target within the trigger's 6 studs of the view ray, and `in air` lets it act off the ground. Seen by the
  user on 2026-10-11: auto stop does stop the character. Reworked at the user's request on 2026-10-12: it only acts
  while the trigger is on an enemy (a target under the crosshair, or with Silent Aim the aim's target), or while the
  aim will have the crosshair on its target by the time the character is still. The second is what `early` now
  turns on, in place of a target within 6 studs of the view ray; that it sits behind `early` rather than always
  being on is Claude's reading. `landing` in `aim.lua` gives the aim's time: none without smoothing, else how long
  the turn takes to shrink to the part's width at smoothing's share a tick, after any switch delay. `aim.stopTime`,
  set by `main.lua`, gives the stop's: a counter-strafe run forward a tick at a time from the last command's speed
  with the game's competitive friction 5.2 and ground accelerate 5.5 (`MovementV2.Simulation.Config`; casual and
  deathmatch use 4 and 5) and the gun's `WalkSpeed`, until under 6.4 studs a second. A FOV condition asked for just
  before was dropped for this. Not run.
- BloxStrike's hit and miss logs (asked for by the user on 2026-10-11, with the wording): the `logs` dropdown in misc ›
  general › others has the hub's `hits` and `misses` in place of starline's five, and `log output` is still a
  placeholder. A line is `Hit <name> for <n> damage in <part> with <n>% hitchance`, or with ` | expected <part>`
  before the chance when another part was hit, or `Missed <name> due to <reason> | expected ...`. The shot hook asks
  `aim.expected(camera, angle)` what the shot was for and takes the first enemy part in the bullet's `Hits` as what
  it got to. A hit is only written once the enemy's `Health` attribute has dropped, which is where the damage comes
  from; after 1 s without that it is a miss by `no registration`. The other reasons come from `aim.missed`: `wall`
  (the bullet's line went through the enemy), `spread` (only the view ray did) and `aim` (neither). Every line is
  also printed as `[hub] ...` so that Claude Code can read it with Potassium's `read_console`, asked for by the user.
- Seeded was reworked at the user's request on 2026-10-11, after a run: with it on every shot's spread is multiplied
  by Legitimacy, 0% none and 100% untouched, the trigger's or not. Before, only shots within 0.2 s of a trigger click
  were narrowed.
- BloxStrike's backtrack (the targeting card's `backtrack` fold and its `amount`, 0 to 200 ms) is a simulation, at
  the user's request on 2026-10-11 after the test showed the server doesn't rewind: see `games/CLAUDE.md`. The chams
  card's backtrack row draws the old places from the same records, which now live in `esp.past`.
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
  camera script hands back its own angles and the default camera hands back the written ones. In BloxStrike the
  step is bound early enough for the game to keep the written view, so there it is always the written one.

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

Baim if lethal, auto scope, auto stop and the R15 hitgroups were written on 2026-10-11 and have not been run.
BloxStrike's aim step was moved from one after the camera's priority to the camera's own on 2026-10-11, after the
user's trigger shots all missed by `aim`; not run since. Open: that the pulled view is now the one shots leave from.

The hit logs and `ui.log` were seen working by the user the same day (a kill reads as the health that was left).
Miss logs failed in that run because the hook wrote to the GUI itself; through a queue they were seen working.

Auto Wall and its min damage were written on 2026-10-11 from the game's decompiled bullet ray and has not been run.

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

The enemies esp card's rows (only visible, only audible, avatar, weapon name, weapon icon, ammo bar, flags, sounds,
offscreen arrows) were written on 2026-10-11. The user's screenshot of 2026-10-12 shows name, health bar and weapon
icon drawing in place; nothing was said of the rest. Open: the avatar's place, whether a Drawing text takes a line
break (flags), and whether an enemy's `CurrentEquipped` keeps up with their rounds (ammo bar).

The picker's opacity bar was written on 2026-10-11; the user has used the chams colours since without a word on it.
Open: how a half-transparent `Neon` or `ForceField` part looks.

Where BloxStrike's chams stood at the end of 2026-10-12:
- Seen working by the user: visible, invisible, overlay, backtrack.
- Not run: on hit (no hit was landed with it on), backtrack's per tick since its copies were limited to enemies on
  screen and in sight (it halved the frame rate before), the gradient's opacities, and on hit's glow opacity.
- Known fault, left at the user's choice: with visible chams painting an enemy's own parts, the game's ragdolls are
  cloned in that paint and with no skin, stay so after eject, and the ragdoll row can't properly override it (see
  `games/CLAUDE.md`). Doing visible chams on copies, as overlay is, would end it.
- Roblox draws at most 31 Highlights and only the nearer of two that overlap. Invisible is one an enemy, solid
  visible one more, an on hit copy one, and the game adds its own to every character while the user spectates, when
  every player also counts as an enemy. Tests of chams while spectating misled twice; test alive in a round.
- Open: whether a weld to a body part ever upsets the game, whether the game puts a skin back mid-round, and whether
  a changed body material alters what the client's own bullet ray goes through.

The aim's min damage in plain sight and the auto stop rework (see the bullets above) were written on 2026-10-12 and
have not been run.

The teammates and local pages of the players tab were written on 2026-10-12 and have not been run. They moved every
enemies row onto per-source settings, so what was seen working on the enemies page (esp card, visible, invisible,
overlay and backtrack chams) needs seeing again. Open besides: whether the local character has `WeaponModel` and
`WeaponAttachments` folders, whether a copy welded to a viewmodel part upsets the viewmodel, what a painted viewmodel
does through a scope, and whether the user's own footsteps reach the local page's sounds. BloxStrike configs keep
their enemies' values; the teammates and local pages' placeholder values in them are dropped.

The world page's skybox, precipitation and fog were written on 2026-10-12. Seen by the user that day: rain falls, so
a ParticleEmitter does take a `getcustomasset` texture, with its streaks lying sideways; the texture was redrawn for
that and not run since. Nothing was said of the rest. Open: how the other four types look, whether Roblox's fog shows
once the Atmosphere is out of Lighting, and whether the Atmosphere comes back right when the row goes off after a map
change.

The Matcha port in `matcha/` was written on 2026-10-11 against its documented API and has not been run.

The split into per-game folders and the loader stopping in unlisted games were written on 2026-10-11 and
have not been run. The Walking Dead Online's `esp.lua`, `aim.lua` and `tabs.lua` have not been run in that
game either: they date from after the starline combat port.
