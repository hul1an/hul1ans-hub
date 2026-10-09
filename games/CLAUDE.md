# Game notes

## The Walking Dead Online

- Place id `128039018996175`, universe (`game.GameId`) `7208219743`, from Roblox's universes API.
- Zombies are the children of `workspace.AI.Walkers` (150+ of them), each with a `HumanoidRootPart`
  (path given by the user from Dex). Registered as the "Zombies" ESP source (also what the aim assist targets when Target Zombies is on), labelled with the model's
  `Name`. Not known yet: whether they have a `Humanoid` (no health bar without one) and what they are named.
- Corpses are the children of `workspace.Corpses`, named after the dead player (e.g. `Nesduck2`). Each has a
  `Loot_Corpse` child whose children are the items, named by item (e.g. `.12 Gauge`). Paths from the user.
  Corpse ESP (Loot tab) marks each corpse at its pivot with its name, distance and item names. Not known:
  the corpse's ClassName (the marker calls `GetPivot`, so it must be a Model or part) and whether an
  item carries an amount.
- Floor loot is the children of `workspace.PhysicalLoot` (path from the user, no child example given, so
  the marker assumes each child is one item named by its `Name`).
- Containers are the children of `workspace.Lootables` (1360+). Each keeps its items in a child named
  `Loot_<kind>` (e.g. `Loot_CarWreck`, containing `Black Ski Mask`); the marker heading is `<kind>` and
  emptied containers are skipped.
- The user wants no constant scanning: containers and corpses rescan on a slider (5-60 s, default 10).
  Floor loot rescans every second.
- Loot Filter tab: one global filter for everything loot-related. With it on, only items whose exact
  name is in `filter.names` pass `allowed(name)`; containers and corpses with no passing item are hidden.
  Auto loot must go through `allowed` too. Names are added from the Available Loot dropdown (every item
  name in floor loot, containers and corpses, rebuilt on load and by the Refresh button, never on a
  timer) and removed by clicking them in the right-hand section. Saved to
  `hul1ans-hub/walking_dead_online_filter.json` in the executor workspace on every change.
- Remote seen by the user while looting a fridge: `ReplicatedStorage.CLIENT_REMOTES.UpdateStorageUI`
  with one argument shown as `Loot_Fridge`. It fired when the fridge was opened, so it is the open /
  refresh call, not the take action. Not known yet: the remote for taking an item, the method
  (FireServer / InvokeServer), and whether the argument is the folder instance or a string.
- Auto Loot is a placeholder toggle only. Per the user it should only act on an inventory that is already
  open (a container or corpse the player opened), so it has no range setting and never walks to loot. Needed from Dex: how the game picks an item up
  (ProximityPrompt, ClickDetector, touch or a remote).
- The Player and Misc tabs are still placeholders too.

## BloxStrike

- Place id `114234929420007`, universe (`game.GameId`) `7633926880`, from Roblox's universes API.
- `games/bloxstrike.lua` is the universal Combat and ESP tabs, a Silent Aim section in Combat, and Eject.
  It turns the aim assist's Team Check on by default.
- Everything below comes from a third-party script the user supplied (`scriptsource.txt`, an unverified
  ScriptBlox post), not from Dex, so treat it as unconfirmed until seen working:
  - Bullets go through a class table found only via `getgc(true)`: a table with a `_performRaycast`
    function and a `getTrueSpread` field. `_performRaycast` returns a result table with `Hits` (array of
    hit tables with `Instance`, `Position`, `Exit`), `Origin`, `Direction`, `Distance`.
  - Silent aim hooks `_performRaycast` with `hookfunction` and rewrites the last hit to `aim.target`.
    It only changes a shot that already hit something. Undone on unload by hooking the original back.
  - Teams are probably named `Terrorists` / `Counter-Terrorists`; that script guessed at how they are
    stored, so the hub just compares `player.Team`.
  - Characters may carry `Dead` and `Invincible` attributes and dead ones may be moved under a
    `Debris` parent. The hub doesn't use these yet.
- Not ported from that script: third person camera, anti-aim, night mode, bullet tracers, hit explosion,
  box-adornment chams, and its auto fire's `mouse1click` path (the hub uses `VirtualInputManager`).
