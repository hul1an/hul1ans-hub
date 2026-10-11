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
- A chunk's `loadstring` return is dropped and its `setfenv` refuses a loadstring'd function (seen
  on the first run), so `hub.load` wraps each module in a call that runs it with `hub` and reads the
  module back out of the chunk's own environment under a named key.
- No `WorldToViewportPoint`: the global `WorldToScreen` returns a Vector2 and an on-screen boolean.
- `RaycastParams` isn't documented. The aim's visibility check branches on whether the class exists;
  without it a hit on the target model itself counts as visible, the jump disabler's ground ray
  can't ignore the local character so it never fires, and BloxStrike's third person tab is left out
  because its wall check would only ever hit the local character.
- No `cloneref`, `gethui`, `getcustomasset`, `getgenv`, `request` or `Random`. Services come from
  `game:GetService` directly, randomness from `math.random`, the single-instance guard lives in
  `_G.Hub`, and HTTP goes through `httpget`, which answers a failure with the error page's body
  (`404: Not Found`), so `hub.fetch` rejects bodies that start `<code>: `.
- `Player.DisplayName`, `GetPlayerFromCharacter` and `GetPlayerByUserId` aren't documented; labels
  and owners come from scanning `GetPlayers` for `Name` and `UserId`.
- `Color3:Lerp` and `GetPivot` aren't documented. `core/esp.lua` mixes the health bar colour by
  hand; `core/markers.lua` reads a part's `Position`, else the root or primary part's.
- `CFrame.lookAt` isn't documented either. `core/aim.lua` and `games/bloxstrike.lua` build the same
  orientation with `fromOrientation`: pitch `asin(y)`, yaw `atan2(-x, -z)`, no roll.
- `writefile` only takes `.txt .lua .luau .json .cfg .dat .ini`, which the configs already are.

## Adapter mapping (`core/ui.lua`)

- `CreateTab` is `UI.AddTab`, one per name; the icon argument is dropped. Eject removes the tab.
- `CreateMultiDropdown` is one toggle per option, feeding the callback the selected array.
- `CreateGroup` is the group's toggle, then its controls flattened into the same section with the
  group name prefixed on their labels.
- `CreateColorpicker` is `ColorPicker`, which Matcha puts on the row of the toggle before it. Every
  layout here already creates a toggle directly before each picker; keep that true in new code.
- `CreateDropdown` is `Combo`, matched on the option text. `AddOption` and `ClearOptions` mutate the
  list the next frame shows.
- No tooltips, search, config popup, sub-tabs or a RightShift toggle (Matcha's menu is its own), and
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
