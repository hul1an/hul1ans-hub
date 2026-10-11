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
- Containers are the children of `workspace.Lootables` (1360+), named `Loot_<kind>` (e.g. `Loot_AmmoBox`).
  Each keeps its items in a child of the same name, the loot part (a MeshPart in the ones seen); the marker
  heading is `<kind>` and emptied containers are skipped. From the remote log of 2026-10-11:
  - An item is a `Folder` named by the item (`.22LR`, `7.92x57mm`) with the attributes `ID` (a GUID), `Amt`,
    `Type` (`Ammo`), `Container` (`Storage` in a container), `GridX`, `GridY`, `Rotated`, `HotbarSlot` and
    `ServerSpawned`. The loot part also holds a `SurfaceAppearance`, a `Sound` and, while the cursor is on it,
    a `Highlight` and an `InteractBillboard`, so an item is a child with an `ID` (`lootItems`).
  - The loot part's own attributes: `GridRows`, `GridColumns`, `GridSlots`, `LootContext` / `ContextLootKey`
    (`GunStore`), `KeycardLootLocked`, `LastLootGeneratedAt`, `CommunityContainerId`.
- The user wants no constant scanning: containers and corpses rescan on a slider (5-60 s, default 10).
  Floor loot rescans every second.
- Loot Filter tab: one global filter for everything loot-related. With it on, only items whose exact
  name is in `filter.names` pass `allowed(name)`; containers and corpses with no passing item are hidden.
  Auto loot must go through `allowed` too. Names are added from the Available Loot dropdown (every item
  name in floor loot, containers and corpses, scanned on load and by the Refresh button, never on a
  timer) and removed by clicking them in the right-hand section. A name in the filter is left out of the
  dropdown, at the user's request, and comes back when it is removed. Saved to
  `hul1ans-hub/walking_dead_online_filter.json` in the executor workspace on every change.
- Looting, from the remote log (five takes from ammo boxes in a gun store). All are `FireServer` on events
  under `ReplicatedStorage.CLIENT_REMOTES`:
  - Open: `SetCursorHit(lootPart)` then `UpdateStorageUI(lootPart)`, the loot part instance. The server answers
    with an `UpdateStorageUI` client event carrying nothing, about 0.1 s later, and again after every take.
  - Take: `LootingSound(type)` then `TransferItem(id, "Main", "Storage", { SourceObject = lootPart })`: the
    item's `ID`, the inventory it goes to, the one it is in. The third argument matched the item's `Container`
    attribute every time, which is where auto loot reads it from. Three takes 0.22 s and 0.28 s apart all
    went through.
  - Close: `ToggleInventory(false)`.
- `CLIENT_REMOTES.ClientIntegrity` is an anti-tamper heartbeat: `("Heartbeat", "Gun" | "Inventory", counter,
  "", 16 hex digits)`, from the gun script every 2 s and the inventory script every 4 s. What the hex is a
  hash of is not known. A `__namecall` hook ran for 30 s under it with no kick.
- Other remotes seen: `NVGToggle("Destroy")` in bursts, `FootstepReplicate(material, "None")`.
- Auto Loot (written 2026-10-11, not run): per the user it only acts on an inventory the player opened, so it
  has no range setting and never walks to loot. A `__namecall` hook, on from load, notes the loot part the
  game opens and forgets it on `ToggleInventory`; on the server's answer it fires `TransferItem` for each item
  that passes `allowed`, 0.2 s apart, and stops if the inventory closes. It does not send `LootingSound`.
  Not known: whether a corpse opens through the same call and its items carry an `ID`, what the server does
  when `Main` is full, and whether a take with no `LootingSound` or a faster one is noticed.
- Temporary: the Remote Logger button (Misc, Debug), which found the calls above. It hooks `__namecall` and
  records the game's `FireServer` / `InvokeServer` calls on any remote, plus what the events under
  `CLIENT_REMOTES` fire at the client, the first 25 of each with a count of all, into
  `hul1ans-hub/walking_dead_online_remotes.json`. An Instance argument is written with its attributes and
  children. Kept until auto loot has been seen working on a corpse, then remove it.
- The Player and Misc tabs are still placeholders too.

## BloxStrike

- Place id `114234929420007`, universe (`game.GameId`) `7633926880`, from Roblox's universes API.
- `games/bloxstrike/` is starline's whole menu tree (`tabs.lua` over `esp.lua` and `aim.lua`, see the root
  `CLAUDE.md`) with what `main.lua` has behind it: Silent Aim, the trigger's Seeded, Hitchance and Min Damage,
  Anti-Aim, the Heard source, Third Person, Night Mode, Bullet Tracers, Hit Effect, Bhop (`auto jump`) and Eject.
  It replaces the built-in players source's
  `models`, `label` and `health` with the game's own rules below. Team Colors was removed by the user on 2026-10-11. Confirmed by the user: ghost boxes
  are gone, Team Check works, silent aim works, and the Visuals tab, Team Colors, Skeleton, Chams and
  Auto Fire all work.
- One `_performRaycast` hook does silent aim, tracers and the hit effect, under a single pcall.
- The aim and the triggerbot are off while the local Player's `Dead` or `IsSpectating` attribute is set
  (`aim.blocked`, confirmed working by the user on 2026-10-11), asked for because the triggerbot kept clicking
  while spectating. Both attributes read `false` on the living local player through the bridge.
  `Controllers.SpectateController` also counts its own spectate and
  freecam instances as spectating (`IsSpectatingNow`), which the hub doesn't read. The local player's `Team`
  can be `Spectators`, per that module.
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
    `ReplicatedStorage._PVS_CulledCharacters.<name>` and keeps a position on its root part, frozen
    where the model was last shown (the spawn, for one not seen yet this round). The hub only uses
    characters whose parent is `workspace.Characters`, so ESP and aim cannot see culled players. This is
    a server-side limit, confirmed by the probe below.
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
- Bots (found in the user's second dump, `bloxstrike_dump_1.json`): matches are filled with bots. A bot
  is a model in `workspace.Characters` with `Bot = true`, its own `Team`, `Health`, `MaxHealth`, `Dead`,
  `ActorId` and `CombatantId` attributes, and no `PresentationOwnerUserId`. It has no Player object, so
  anything that walks `Players:GetPlayers()` never sees it. That was the "enemies with no ESP that silent
  aim won't pick". A player's character has `PresentationOwnerUserId` (their UserId) and no `Team`; the
  side is on the Player. The hub now reads `workspace.Characters` and the culled folder directly, takes
  the side from the character or its owner (`teamOf`), and labels bots by model name. Confirmed by the
  user: bots have ESP now.
- Read again on 2026-10-10 for the fog of war work: in `bloxstrike_dump_1.json` all 7 characters in
  `_PVS_CulledCharacters` were dead, their root positions being where they died (the "boxes in the wrong
  place"), and all 5 living enemies were in `workspace.Characters`, 75 to 110 studs from the local player.
  The probe below is what caught living enemies in it.
- Every character has `ClientOwnedCharacterPresentation = true` and `ClientCharacterPresentationVisible`
  (false on the culled ones): the client builds the models itself, so positions reach it through the game's
  own networking, not Roblox character replication.
- Player objects replicate for everyone, with `Health`, `Armor`, `Dead`, `Team`, `Money`, `CurrentEquipped`,
  `LastKiller`, `IsWalking` / `IsCrouching` / `IsJumping` / `IsClimbing` / `IsSniperScoped` and
  `PresentationSpawnPosition` / `PresentationSpawnYaw` (where they spawned this round), but no live position.
- Seen by the user (2026-10-10): enemies are completely invisible until they are close enough to wallbang.
- The PVS probe (a temporary button, run by the user on 2026-10-10 and removed again; its output is
  `bloxstrike_pvs.json` beside the dumps, its code is in commit `adf9679`) settled the fog of war:
  - Other characters' movement arrives on `ReplicatedStorage.MovementV2Remotes.RemoteSnapshot`, an
    UnreliableRemoteEvent firing about 45 times a second with one buffer; your own on `OwnerSnapshot`.
    After a header (sequence, baseline sequence and server tick as u32 from byte 2; the tick runs at 60 a
    second) and a u16 count it lists only the actors that changed: the ActorId as a LEB128 varint, a mask
    byte, then per mask bit a position delta (3 i16), velocity (3 i16), yaw (u16), vertical look (1 byte)
    and, for bit 0x20, one more byte.
  - The server leaves a hidden enemy out of that stream. `luckyluis2` (ActorId 3945, running the whole
    time) was in the samples taken while his model was shown and in none of those taken while it was
    culled, and the client's records of two enemy bots culled all round still carried the round-start tick.
    So no script can read a hidden enemy's position: it is not on the client.
  - The cull is by line of sight, not distance: the same enemy was hidden at 229 and at 85 studs and shown
    at 107 and at 45.
  - The cull code is `ReplicatedStorage.Controllers.CharacterController.RemoteCharacters` (`setEntryVisible`,
    `tryBind`; an entry has `Player`, `Shell`, `Visible`, `LastPosePosition`, `LookYaw`) and `.BotCharacters`
    (`hide`, `LastPosition`), with `ReplicatedStorage.Components.Common.ClientCharacterPresentation`
    (`GetCulledFolder`). Players have ActorIds as bots do; the game's movement records are tables with
    `ActorId`, `UserId` (0 for a bot), `Position`, `Velocity`, `LookYaw`, `Stance`, `MovementMode`.
  - What the server does still send about a hidden enemy is sound. `NetworkRemotes.Sound.ReplicateSound`
    carries `Class` (`FloorSounds` for a footstep), `Name` (`Concrete`, `LandingConcrete`) and an exact
    `Position`, and the game plays it from a `Sound` under `workspace.Debris.Sound` at that position. While
    that enemy was culled and running 85 studs away, three such sounds traced his path in 1.3 s; none came
    while he was beyond about 107 studs. Your own footsteps are Sounds on your own `HumanoidRootPart`.
  - Every `NetworkRemotes` payload is a buffer of one byte and a zstd frame (magic `28 B5 2F FD`); small
    ones are stored uncompressed, so their strings can be read, larger ones can't without a decompressor.
  - Remotes seen firing that could give more: `NetworkRemotes.VFX.CreateImpact`, `.Projectile.Spawn`,
    `.Character.Action` (`ActionId`, `UserId`, `Generation`), `.UI.UIPlayerKilled`. Present but silent in the
    run: `.VFX.CreateCharacterMuzzleFlash`, `.Character.CharacterDamaged`, `.Ping.CreatePlayerPositionPing`,
    `.Spectate.UpdateCameraCFrame`, `MovementV2Remotes.BotCombat`.
- `ReplicatedStorage.MovementV2.Simulation.State` (decompiled by the user on 2026-10-11) is only the shape of
  the movement state, no logic: `new`, `clone`, `cloneInto`, and `canonicalMismatch` / `mismatchLabel`, which
  compare two states field by field (read as the client's prediction against the server's, not confirmed).
  The fields that matter for a bunnyhop: `OnGround`, `PreviousButtons` (a button bitmask, 0 at start),
  `LastJumpCommandNumber`, `JumpBufferTicksRemaining`, `JumpHullActive`, `Stamina` (100 at start), `Velocity`,
  `VelocityModifier`, `MovementTick`. Beside it are `Simulation.Config` (`Default.DefaultBaseMoveSpeed`) and
  `MovementV2.Types`. It also has `MovementMode` (`Walking` or `Ladder`).
- Jumping, from modules decompiled through the bridge on 2026-10-11:
  - `MovementV2.Buttons`: `Jump = 1`, `Duck = 2`, `Walk = 4`, `Scoped = 8`.
  - The Jump keybind (`Controllers.InputController.Actions.Jump`) calls `CharacterController.jump(true / false)`,
    or `jump()` for the mouse wheel. `Classes.Character:SampleInput` then sets the Jump button on every command
    while the key is held, and on one command for a wheel notch.
  - `MovementV2.Simulation` runs each command on the state before it: `Tick` is the command number, `JumpHeld`
    is the Jump bit of `PreviousButtons`. `Simulation.ProvenSimulator` jumps when the state is `OnGround`, the
    button is down and wasn't on the command before (or `Config.AutoBunnyHop`, or a buffered press), and the
    last jump was more than one command ago. A jump on the first ground command skips that command's friction.
    So a held key jumps once.
  - `Simulation.Config` profiles: `Competitive` is the default one, with no jump buffer; `Casual` and
    `Deathmatch` buffer a press for a tenth of a second and cut horizontal speed above 19 studs a second on
    landing; `Surf` has `AutoBunnyHop`. Stamina (100, floor 20, back at 60 a second) drops 0.08 per Hammer unit
    of jump speed and 0.05 per unit of landing speed outside Surf, and jump speed is scaled by it. The server
    runs the same simulation, so none of that can be changed from the client.
  - Commands are built in `MovementV2.Client.Runtime._stepPrediction`: `_options.SampleInput` gives the input
    (`Move`, `LookYaw`, `VerticalLook`, `Buttons`), `_buildCommandInput(input, state, ...)` finishes it with the
    predicted state the command will run on, and the result is both simulated locally and sent.
- Bhop, the auto bunnyhop toggle (confirmed working by the user on 2026-10-11), hooks `Runtime._buildCommandInput`, the class being found through
  `getgc(true)`. While walking it takes the Jump button out of a command unless the state is on the ground and
  the command before had no Jump, so a held key becomes a fresh press on the first ground command. Ladders and
  everything else about the input are left alone. The hook takes on the class's method. Not known: how much
  speed stamina and the casual landing cut leave over a run of hops.
- Spread, from `Components.Weapon.Classes.Bullet` and `Components.Weapon` decompiled through the bridge on
  2026-10-11. `Bullet` is the class the shot hook is on; each gun (`Components.Weapon`) has one as `.Bullet`,
  made with `Bullet.new(weapon, properties)`.
  - A gun's `Properties.Spread` (or the fire mode's, `ActiveSpreadConfig`) has `Range.Min` / `Range.Max`,
    `PerShot`, `RecoverySpeed`, `MovementMultiplier` and `JumpShotMinimum`. The gun's own spread is a
    `Shared.Spring` at `bullet.Spread` resting at `Range.Min`: a shot adds `PerShot` and it springs back at
    `RecoverySpeed`. `getTrueSpread()` is that, clamped to the range, plus `CharacterSpeed * MovementMultiplier`,
    the speed counting as 0 under 6.4 studs a second. In the air the speed is held at the take-off speed plus
    `JumpShotMinimum` (100 without one), except at the top of a jump with some snipers.
  - `Weapon.shoot` calls `Bullet:create(Properties.AimingOptions, weapon.IsAiming)` once per `BulletsPerShot`.
    `create` reads the spread, then adds `PerShot`, then calls `_performRaycast(spread)`. For `SniperScope` guns
    unscoped the own spread is first raised to 6, 12 or 15 (`MovementMultiplier` 2, 3, other), and an `AWP`
    scoped for under 0.2 s (`weapon.ScopeStartTick`, a `tick()`) has its whole spread raised to that.
  - `_performRaycast(spread)` seeds `Random.new` with `os.clock()` in microseconds, read inside the call, so no
    seed exists before the shot and none can be read ahead. The spread is degrees across the cone, capped at 69:
    the shot leaves the camera's centre ray by `NextNumber(0, spread / 2)` degrees, at `NextNumber(-pi, pi)` round it.
  - The client sends each bullet's `Origin` and `Direction` in `Remotes.Inventory.ShootWeapon` (with
    `IsSniperScoped`, `ShootingHand`, `Identifier`, `Seq`, `ViewTick`), so the server never sees the seed. Not
    known: whether it checks a direction against anything.
  - An equipped gun's bullet is `IsActive` and has `updateSpread(dt)` called on it every Stepped; `destroy` clears
    `Properties`, `Spread` and `Weapon`, after `setActive(false)`.
- Seeded and Hitchance (written 2026-10-11, not run). `aim.spread` in `main.lua` returns half of what `create`
  would pass for the next shot. The bullet object comes from a second hook, on `Bullet.updateSpread`, which keeps
  the last active one it is called for. The `_performRaycast` hook multiplies the spread it is given by
  `aim.spreadScale()`. Not known: whether a gun that is out when the hub loads is being stepped (if not,
  Hitchance does nothing until it is switched to), and whether the server notices narrowed shots.
- Damage, read through the bridge on 2026-10-11 for the trigger's Min Damage. No damage formula is on the
  client; the server works it out. What the client has:
  - Each gun's file (`Database.Custom.Weapons.<name>`, the bullet's `Properties`) has `DamagePerPart` (`Head`,
    `Torso`, `Arms`, `Legs`), `RangeModifier`, `ArmorPenetration`, `WallbangMultiplier`, `Penetration`, `Range`
    (1200 for most, 120 for shotguns, 13.584 for the Zeus) and `BulletsPerShot`. Knives and grenades have
    `DamagePerPart` too. The figures are CS2's: AK-47 143 / 44 / 35 / 21, 0.98, 0.775; AWP 459 / 143 / 115 / 85.
  - `MovementV2.SpeedProfile.HammerUnitToStud` is 0.075, so CS2's 500 units are 37.5 studs.
  - A Player's `Armor` attribute is JSON, seen as `{"Health":100,"Type":"Kevlar + Helmet"}`. The other type is
    taken to be `Kevlar` from `GameStats.Equipment`; what the attribute is with no armour wasn't seen, nor
    whether a bot has any.
  - `aim.damage` (written, not run) applies CS2's rule to those: the part's damage, times `RangeModifier` to
    the power of distance / 37.5, times `ArmorPenetration` when the armour has health left and the part is the
    torso or an arm, or the head under a helmet. Hands count as arms, feet as legs, everything else but the
    head as torso. Behind the 37.5: the Zeus (500 a part, modifier 0.011416) comes to 99 at its 13.584 stud
    range. Not known: whether the server uses that rule, its part to group map, and what a wall takes off
    (`WallbangMultiplier` is not applied). A shotgun's figure is one pellet's.
- `ReplicatedStorage.MovementV2` in Dex (screenshot from the user, 2026-10-11), all ModuleScripts:
  - Top level: `ActionLockTimeline`, `BotCombatCodec`, `Buttons`, `CommandCodec`, `Config`, `ControlCodec`,
    `DamageTag`, `DiagnosticProtocol`, `DoorSwing`, `Enums`, `JumpInputSampler`, `Mapping`,
    `MoverDescriptorCodec`, `MoverProgressCodec`, `MoverTrajectory`, `OwnerSnapshotCodec`, `Quantization`,
    `RemoteActorIdentity`, `RemoteSnapshotCodec`, `RootFrame`, `RuntimeKinematics`, `Serial`, `SpeedProfile`,
    `StateCodec`, `Transport`, `Types`, and the folders `Collision` (children not seen) and `Simulation`.
  - `Simulation`: `Config`, `DeterminismTrace`, `PlayerBroadphase`, `PlayerContactStep`, `PlayerContacts`,
    `PlayerHullClearance`, `PlayerLanding`, `PlayerSupportQuery`, `ProvenCollisionAdapter`, `ProvenMath`,
    `ProvenSimulator` (a module with the children `AirMove`, `Duck`, `GroundMove`, `Ladder`, `SlideMove`,
    `Trace`, `TraceRules`), `ProvenTypes`, `RuntimeSettings`, `Solver`, `State`, `Types`. Nothing is named
    for jumping.
  - `Client`: `ActionLockReplay`, `CommandClock`, `CommandState`, `CommandStream`, `CommandUplink`,
    `CorrectionDiagnostics`, `DamageTagReplay`, `DestructibleTimeline`, `DeterminismTraceCapture`,
    `DiagnosticOutput`, `MoverComposer`, `OwnerCommandFeedback`, `OwnerRecovery`, `OwnerReplay`,
    `PlayerContactAdapter`, `PredictionErrorSmoother`, `PredictionPacing`, `PredictionRing`, `Reconciler`,
    `RemoteBuffer`, `RemoteClock`, `Runtime`, `RuntimeDiagnostics`, `RuntimeTypes`, `WorldComposer`,
    `WorldReplay`. `Reconciler` and `PredictionRing` back the reading that the client predicts and the server
    corrects.
  - Beside it: `ReplicatedStorage.MovementV2CollisionCatalogs.Epoch_00026_d4e4c53d` and a `Control` remote
    under `MovementV2Remotes`.
- Fog of war, read again through the bridge on 2026-10-11 when the user asked for ESP despite it:
  - The game calls it `CS2FOW` (workspace attributes `CS2FOWReady`, `CS2FOWClusterCount` 2048,
    `CS2FOWRegionCount` 11149); `ReplicatedStorage.Visibility` holds its shared code (`PVSRuntime`, `PortalVis`,
    `StaticOcclusionRuntime`, ...), not read.
  - It only applies to a player in the round. With the user on no team (no `Team` attribute, in the menu) all
    12 characters of both sides were in `workspace.Characters` and none culled. Alive on Terrorists, every enemy
    was culled and every teammate shown, one of them 228 studs away. So a sound no shown character made is an
    enemy's.
  - `RemoteCharacters.Present` shows a character exactly while the movement runtime hands it a pose, and
    `RemoteSnapshotCodec` has `RemovedActorIds`: the server takes hidden actors out of the stream, as the probe found.
  - The game's own `Controllers.ESPController` (the `VIPESP` Player attribute) only highlights characters that
    are in `workspace`, and `Interface.Screens.Gameplay.Middle.Radar` works from the same characters, so neither
    knows more than the hub.
  - `MovementV2Remotes.BotCombat` carries bot events (`Shoot`, `Reload`, the throws) with `ActorId`,
    `WeaponName` and, for a shot, the `Target` point, no origin.
  - Sounds: `Controllers.SoundController` listens to `ReplicateSound` (`Class`, `Name`, `Position`, `Duration`,
    or `Parent` / `Path`, no word on who made it) and `Classes.Sound:PlaySoundAtPosition` plays a clone of
    `ReplicatedStorage.Sounds.<Class>.<Name>.<variant>` from a pooled part named `Sound` under `workspace.Debris`.
    The clone is renamed to a GUID and keeps its `SoundId`.
  - A 30 s sample while alive: 244 sounds. Footsteps (`FloorSounds`, named by floor, with `Jump` and
    `Landing<floor>`) were within 1 stud of the maker's root, gun `Shoot` sounds within 8. 14 footsteps and 2
    shots had no shown character near: hidden enemies 50 to 82 studs off, in runs 0.3 s and about 5 studs
    apart. `Bullet` sounds are at the impact, grenade and `C4` sounds at the object.
  - What the server hears of where the client is, read when the user asked about spoofing the camera to get
    round the fog: a movement command (`MovementV2.CommandCodec`) carries `Move`, `LookYaw`, `VerticalLook`,
    `Buttons`, the weapon selection and the predicted speeds, no position, so the server works the position out
    itself. The one place a camera position is sent is `SpectateController.Broadcast`:
    `Remotes.Spectate.UpdateCameraCFrame.Send({ CameraCFrame, UserId })` every 0.2 s while a weapon is equipped,
    every frame once the `Spectators` attribute is above 0. Not known: whether the fog reads that or `LookYaw`.
  - `Database.Security.Remotes` is a frozen table of namespaces (`Remotes.Spectate`, ...), each a frozen table of
    packets made by `Security.Network.CreatePacket`. A packet is a table of closures (`Send`, `Listen`, `Connect`,
    `Wait`, the server-side `SendTo...`); `Send(payload)` checks the payload against the packet's schema, encodes
    it with `Network.BufferCodec` and fires the remote. `UpdateCameraCFrame` is unreliable, a struct of
    `CameraCFrame` (CFrame) and `UserId`, limited to 60 a second.
- The camera spoof test (2026-10-11, run by the user, removed again; its code is in commit `65ef1de`) answered
  the question above: the fog does not read the reported camera. It swapped the `Send` field of the
  `UpdateCameraCFrame` packet table, found through `getgc(true)`, for a wrapper that moved the reported position
  to the last known spot of the nearest hidden enemy. The console showed a report moved to the enemy spawn,
  and with the toggle on and the user alive at their own spawn at the start of a round, all six enemies stayed
  in `_PVS_CulledCharacters` at theirs. So the swap works as a way to change what a packet sends.
- Seen in the same session while the user was dead with `IsSpectating` true and `SpectatePerspective`
  `First-Person`: a living enemy was in `workspace.Characters` with a live position and a living teammate was
  culled, the opposite of what an alive player gets. Read as the server sending the view of whoever is being
  spectated (the game spectates `LastKiller` first), not confirmed: who was being spectated wasn't read.
- The spectate request test (2026-10-11, run by the user, removed again; its code is in commit `00995e1`): the
  server ignores a spectate request from a living player. From `SpectateController`, the client asks with
  `Remotes.Spectate.SpectatePlayer.Send(name)`, the Player's `Name` or for a bot `tostring(Participants.Key(bot))`,
  and ends with `Remotes.Spectate.StopSpectating.Send()`; `StartSpectating` and `SetSpectatePerspective` are in
  the same namespace and `SpectateController` sends neither. The test sent the request three times for a hidden
  enemy player while the user was alive. Eleven seconds after the last one that enemy was still in
  `_PVS_CulledCharacters` where it had been, and the user's `IsSpectating` was still false. A stop sent in
  between changed nothing either. Not tried: a bot's key, and the other two packets.
- Heard enemies (confirmed working by the user on 2026-10-11): an ESP source "Heard", added before `tabs.lua` so it gets its
  own section and a Target toggle. Its toggles read "Dormant ESP" and "Dormant Aimbot" (`toggle` and `aimToggle` on the source) and
  its memory slider "Fade Out", renamed at the user's request the same day; the section still says Heard. Fade Out
  sits under the Dormant ESP toggle (`options` on the source). A footstep or shot under `workspace.Debris` with no living shown character
  within 10 studs moves the ghost within 15 studs of it, or makes one. A ghost is an unparented Model holding
  a `HumanoidRootPart`, which is all the ESP needs for a box, and goes after Fade Out seconds (1-10,
  default 3) without a sound or once a shown enemy is within 15 studs. Only heard while ESP and the source
  are on. Asked for by the user the same day: it fades over that time (`opacityOf`), is dull grey by default,
  and shows a name in place of the word "Heard". A sound carries no name, so the name is a guess: of the living
  enemies in `_PVS_CulledCharacters` that no other ghost has, and for a shot those holding that gun, the one
  last known nearest (where its hidden model stands, or where it was heard since). It ends in `?` unless there
  was only one candidate, is looked up again on each sound until then, and is dropped if that enemy turns up
  shown elsewhere or dead. The gun comes from the sound's class, a player's from the `Name` in the Player's
  `CurrentEquipped` JSON, a bot's from its character's `BotLoadout` JSON, which lists every gun it has. Not known: why the Sound ESP of 2026-10-10 "didn't work" (it listened the same way and drew a 6 pixel
  ring), and how far footsteps carry (the probe's one case suggested about 107 studs).
- Removed at the user's request on 2026-10-10:
  - Dormant ESP, a fading box at a culled enemy's last shown position.
  - Sound ESP, a fading ring at each `Sound` under `workspace.Debris` that wasn't beside a shown character.
  - The spectate probe, which hooked `__namecall` to record the game's `NetworkRemotes.Spectate.*` requests
    and could replay one with an enemy's UserId.
  The last two were merged as PR #1 (commit `82cc35b`) and run by the user, who reported that it didn't work
  without saying how; the spectate probe left no output file. Dormant ESP's code is in the commits before.
- `workspace.Characters` also holds three childless-looking entries named `Terrorists`,
  `Counter-Terrorists` and `Hostages` with no root part; they are skipped by the root-part check.
- `workspace.Map.Barriers` holds fully invisible, collidable parts that sat between the camera and every
  enemy in that dump, so the aim assist's visibility ray reported everyone as hidden. The aim now
  looks through parts with Transparency 1.
- Both temporary dump buttons are removed. The dumps live on this machine in
  `AppData/Local/Potassium/workspace/hul1ans-hub/`. The probe's file is there too.
- Not ported from that script: box-adornment chams (Highlight chams cover it), the Explosion instance in
  its hit effect (only the expanding ball is ported), `mouse1click` auto fire (the hub's triggerbot clicks
  through `VirtualInputManager`).
- Since the starline combat port of 2026-10-10 silent aim is the setting `aim.settings.SilentAim`, whose
  toggle is under the aim's Enabled; the shot hook reads it and
  still redirects to `aim.target`. The aim core under it is new and Auto Fire is gone, so Team Check and the
  silent aim target need seeing again. Anti-aim's Disable On Fire now only looks at the left mouse button.
  Not known: whether a shot redirected to `HumanoidRootPart` (the Stomach hitgroup) does damage, and whether
  the triggerbot's `VirtualInputManager` click shows as that button being held.
