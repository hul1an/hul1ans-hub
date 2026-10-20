# Matcha port

The same hub for [Matcha](https://matcha-latte.win), an external LuaVM that emulates the Roblox API
instead of hooking the engine. Its docs are at `https://huoadf.github.io/matcha-docs/llms-full.txt`.
Run with
`loadstring(httpget("https://raw.githubusercontent.com/hul1an/hul1ans-hub/main/matcha/loader.lua"))()`.
Nothing here has run in Matcha yet.

## What Matcha takes away

- No `Instance.new`. Nothing can be built from GUI instances, so there is no bloxline menu and no
  Highlight chams. `core/ui.lua` is an adapter over Matcha's own `UI.AddTab` binding, whose tab
  callbacks are re-emitted every frame, and the ESP has no Chams toggle.
- No hooks. `hookfunction`, `hookmetamethod`, `newcclosure` and `getnamecallmethod` don't exist, so
  BloxStrike silent aim, bullet tracers, the hit effect and auto bunnyhop, and The Walking Dead
  Online's auto loot and remote logger, are not ported. Matcha ships its own BloxStrike silent aim
  and team check; those cover the shooting.
- `task.delay` and `task.defer` never run their callbacks and `task.spawn` drops extra arguments, so
  nothing here uses them. The triggerbot presses and releases its click from the render loop.
- A chunk's `loadstring` return is dropped and `setfenv` can't change a chunk's environment (seen on
  2026-10-20: `'setfenv' cannot change environment of given object`), so `hub.load` wraps each module in a
  function that the chunk leaves in `_G.HubModule`, taken out again at once.
- No `WorldToViewportPoint`: the global `WorldToScreen` returns a Vector2 and an on-screen boolean.
- `RaycastParams` isn't documented. The aim's visibility check branches on whether the class exists;
  without it a hit on the target model itself counts as visible, the jump disabler's ground ray
  can't ignore the local character so it never fires, and BloxStrike's third person tab is left out
  because its wall check would only ever hit the local character.
- No `cloneref`, `gethui`, `getcustomasset`, `getgenv`, `request` or `Random`. Services come from
  `game:GetService` directly, randomness from `math.random`, the single-instance guard lives in
  `_G.Hub`, and HTTP goes through `httpget`, which answers a failure with an empty body.
- `Player.DisplayName`, `GetPlayerFromCharacter` and `GetPlayerByUserId` aren't documented; labels
  and owners come from scanning `GetPlayers` for `Name` and `UserId`.
- `Color3:Lerp` and `GetPivot` aren't documented. `core/esp.lua` mixes the health bar colour by
  hand; `core/markers.lua` reads a part's `Position`, else the root or primary part's.
- `CFrame.lookAt` isn't documented either. `core/aim.lua` and `games/bloxstrike.lua` build the same
  orientation with `fromOrientation`: pitch `asin(y)`, yaw `atan2(-x, -z)`, no roll.
- `writefile` only takes `.txt .lua .luau .json .cfg .dat .ini`, which the configs already are.

## Universal script (`games/universal/`)

Asked for by the user on 2026-10-20: the root `games/universal/` made as compatible with Matcha as it can be. This is
its own copy, run by the loader in a game with no entry in the registry; the shared `core/esp.lua`, `core/aim.lua`
and `universal.lua` are for the BloxStrike and Walking Dead Online ports and were not touched. Written against the
docs of 2026-10-16, not run. What differs from the root copy:
- Only documented API: no `cloneref`, `gethui`, `Instance.new`, `BindToRenderStep`, `VirtualInputManager`, `Random`,
  `CFrame.lookAt`, `GetPlayerFromCharacter`, `DisplayName`, `RaycastParams`, `WorldToViewportPoint`, `os.date` or `continue`.
  Time is `tick()`, the click `mouse1press` released from the frame loop, positions `WorldToScreen`.
- Angles in the aim are two numbers (pitch, yaw) and not a Vector2, which the docs give no arithmetic for.
- Tables keyed by an instance are keyed by its `Address`: the docs say `==` works on instances, not that the same
  instance is always the same object.
- Line of sight is `workspace:Raycast` with no params; a ray that hits the user's own character, the camera or a part
  with `Transparency` 1 is moved on past it, up to eight times. The jump disabler's ground ray does the same.
- Left out because Matcha can't: chams and avatars (no Highlight or image), precipitation, fog, bloom, motion blur,
  the world tint, sun, light and the removals (no instances, and the Lighting properties they need aren't documented),
  third person (Player camera properties undocumented), auto jump (`Humanoid.Jump` undocumented, and a key press
  can't be told from the user's), the keybind list (Matcha has its own hotkey overlay, `:AddToHotkey`), the landing
  events, the watermark's time and the offscreen arrows' fill and outline (three lines, with a shadow).
- Kept: the esp (box, name, weapon name, skeleton, health bar, arrows, only visible) on the enemies, teammates and
  local pages, the aim and triggerbot, the list page, night mode (`ClockTime`, `Ambient`, `ExposureCompensation`),
  ambience (`Ambient`), override fov, aspect ratio, the watermark and the velocity graph.
- Seen on 2026-10-20 through Matcha's MCP: a Text takes `Size` and errors on `FontSize` (`Unknown property`), the
  docs' property list is wrong there; `Color3.new()` needs its arguments; `table.find`, `table.clear`, `math.atan2`,
  `os.date` and `CFrame.lookAt` all exist, so the docs' list of what is missing is too long.
- Open: whether a camera write lands before or after the game's own each
  frame (override fov and aspect ratio are written from what the game would have, not from the last frame), and
  whether the trigger's click at the cursor's place is where the view is.

## Adapter mapping (`core/ui.lua`)

- `CreateTab` is `UI.AddTab`, one per name; the icon argument is dropped. Eject removes the tab.
- `CreateMultiDropdown` is one toggle per option, feeding the callback the selected array.
- `CreateGroup` is the group's toggle, then its controls flattened into the same section with the
  group name prefixed on their labels.
- `CreateColorpicker` is `ColorPicker`, which Matcha puts on the row of the toggle before it. Every
  layout here already creates a toggle directly before each picker; keep that true in new code.
- `CreateDropdown` is `Combo`, matched on the option text. `AddOption` and `ClearOptions` mutate the
  list the next frame shows.
- A toggle's creator also gives `CreateKeybind(key, mode)` with mode `hold` or `toggle`, `CreateColorpicker(callback,
  alpha)` (a swatch on the toggle's row, the callback getting the colour and its opacity) and `Set`, which is
  `UI.SetValue`; a group has `.header`, its own toggle, and a slider has `Set`. `tab:CreateSubTab(name)` puts its
  sections in the tab with its name in front of theirs, and its `CreatePlayerList(groups, chosen)` is a dropdown of
  everyone over a card of rows. A format function on a slider is ignored: Matcha takes a pattern. These are for
  `games/universal/`; the older ports don't use them.
- No tooltips, search, config popup, RightShift toggle (Matcha's menu is its own), and
  `ui.visible()` is always false because Matcha doesn't say whether its menu is open, so the
  triggerbot can click into it.

## Open questions for the first run

- Whether `BasePart.CFrame` reads and the part, joint and camera CFrame writes work; the aim,
  anti-aim and third person hang off them.
- Whether a Combo refreshes its items when the list changes between frames, and whether defaults
  re-passed every frame stick; the loot filter and every control depend on both.
- Whether `RenderStepped:Connect` returns something with `Disconnect`, and `aim` order against the
  game's camera, which `BindToRenderStep` used to settle.

Settings reset every run: the adapter has no save button. The Walking Dead Online loot filter still
saves itself on every change.
