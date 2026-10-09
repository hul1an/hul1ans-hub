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
- Auto Loot is placeholder controls only. Needed from Dex: how the game picks an item up
  (ProximityPrompt, ClickDetector, touch or a remote).
- The Player and Misc tabs are still placeholders too.
