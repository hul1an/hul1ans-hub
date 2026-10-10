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
- `games/bloxstrike.lua` is the universal Combat and ESP tabs plus the game's own: Silent Aim (Combat),
  Team Colors (ESP), a Visuals tab (Third Person, Night Mode, Bullet Tracers, Hit Effect) and Eject.
  It turns the aim assist's Team Check on by default and replaces the built-in players source's
  `models`, `health` and `colorOf` with the game's own rules below. Confirmed by the user: ghost boxes
  are gone, Team Check works, silent aim works, and the Visuals tab, Team Colors, Skeleton, Chams and
  Auto Fire all work.
- One `_performRaycast` hook does silent aim, tracers and the hit effect, under a single pcall.
- Third person binds a render step two after the camera's (one after the aim assist), shows the local
  character and hides every Model under the camera through `LocalTransparencyModifier`, remembering the
  old values to restore. It does not touch zoom limits or `CameraMode`. Not known: whether shots still
  come from the right place with the camera pulled back.
- Night mode saves the six Lighting properties it changes and rewrites them every frame while on.
- Anti-aim (Combat tab) is a straight port, asked for by the user after being told it may only be
  visible locally: each frame it turns `HumanoidRootPart` so the character's back faces `aim.target` or
  the nearest un-culled enemy (or away from the camera), and offsets the `Neck` / `Waist` joints' `C0`
  by the chosen pitch and yaw, restoring the saved `C0` when off or while firing. Unconfirmed: whether the
  character has those joints at all, and whether any of it replicates to other players.
- From the user's dump (`hul1ans-hub/bloxstrike_dump.json`, one snapshot of a 10-player match):
  - Fog of war: the game culls players it decides you can't see (it calls this PVS). A live, visible
    player's `player.Character` is `workspace.Characters.<name>`; a culled one is moved to
    `ReplicatedStorage._PVS_CulledCharacters.<name>` and keeps a position on its root part. Whether
    that position keeps updating while culled is NOT known; drawing it gave boxes in the wrong place.
    The hub only uses characters whose parent is `workspace.Characters`, so ESP and aim cannot see
    culled players. This is a server-side limit, not a bug.
  - Characters are custom (`CharacterType = PlayerCustomCharacter`): R15 part names, an
    `AnimationController`, no `Humanoid`. Health is the character attributes `Health` / `MaxHealth`,
    death is `Dead` (also mirrored on the Player). A dead player's `Character` is nil.
  - Sides are the attribute `Team`: `Terrorists` or `Counter-Terrorists`, on the Player for players
    and on the character for bots. The Teams service is empty and `player.Team` is nil for everyone.
  - A player not in the match has a normal Roblox character directly under `workspace` (seen at
    0, 103, 0) with no game attributes. Ignored by the parent check.
  - Character models contain parts parked far away (one bounding box was 10,000 studs tall), which is
    why the ESP box must come from `HumanoidRootPart`.
  - Other top-level folders: `workspace.Debris`, `workspace.ThirdPersonWeaponStash`, `workspace.Map`;
    the camera holds `ViewmodelStash` and the held gun's model (e.g. `Galil AR`).
- From a third-party script the user supplied (`scriptsource.txt`, a ScriptBlox post). The user confirmed
  silent aim works well, so the bullet class and hit-result shape below are right:
  - Bullets go through a class table found only via `getgc(true)`: a table with a `_performRaycast`
    function and a `getTrueSpread` field. `_performRaycast` returns a result table with `Hits` (array of
    hit tables with `Instance`, `Position`, `Exit`), `Origin`, `Direction`, `Distance`.
  - Silent aim hooks `_performRaycast` with `hookfunction` and rewrites the last hit to `aim.target`.
    It only changes a shot that already hit something. Undone on unload by hooking the original back.
  - Characters may carry an `Invincible` attribute. Not seen in the dump, not used.
- Dormant ESP (ESP tab, off by default): for an enemy who is alive (`Dead` attribute false on the Player)
  but culled (character's parent is named `_PVS_CulledCharacters`), a box is drawn at the root position
  still on the culled character, with opacity falling to zero over the Fade Time slider (1-30 s, default
  10) counted from when the cull was first seen. Follows the ESP master toggle, Show Players and the
  players' max distance. If those boxes are seen moving, culled positions are live, which would answer
  the open question below.
- Bots (found in the user's second dump, `bloxstrike_dump_1.json`): matches are filled with bots. A bot
  is a model in `workspace.Characters` with `Bot = true`, its own `Team`, `Health`, `MaxHealth`, `Dead`,
  `ActorId` and `CombatantId` attributes, and no `PresentationOwnerUserId`. It has no Player object, so
  anything that walks `Players:GetPlayers()` never sees it. That was the "enemies with no ESP that silent
  aim won't pick". A player's character has `PresentationOwnerUserId` (their UserId) and no `Team`; the
  side is on the Player. The hub now reads `workspace.Characters` and the culled folder directly, takes
  the side from the character or its owner (`teamOf`), and labels bots by model name. Confirmed by the
  user: bots have ESP now.
- `workspace.Characters` also holds three childless-looking entries named `Terrorists`,
  `Counter-Terrorists` and `Hostages` with no root part; they are skipped by the root-part check.
- `workspace.Map.Barriers` holds fully invisible, collidable parts that sat between the camera and every
  enemy in that dump, so the aim assist's visibility ray reported everyone as hidden. `core/aim.lua` now
  looks through parts with Transparency 1.
- Both temporary dump buttons are removed. The dumps live on this machine in
  `AppData/Local/Potassium/workspace/hul1ans-hub/`. Still unknown: whether a culled character's root position keeps
  updating. To find out, re-add a dump and compare two snapshots a few seconds apart.
- Not ported from that script: box-adornment chams (Highlight chams cover it), the Explosion instance in
  its hit effect (only the expanding ball is ported), `mouse1click` auto fire (the hub uses
  `VirtualInputManager`).
- `games/bloxstrike.lua` was not touched by the starline combat port of 2026-10-10: Silent Aim and Anti-Aim
  are still its own sections on the Combat tab and silent aim still redirects to `aim.target`. The aim core
  under them is new, so Team Check, the silent aim target and Auto Fire need seeing again. Not known:
  whether a shot redirected to `HumanoidRootPart` (the Stomach hitgroup) does damage.
