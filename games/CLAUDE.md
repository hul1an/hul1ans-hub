# Game notes

## The Walking Dead Online

- Place id `128039018996175`, universe (`game.GameId`) `7208219743`, from Roblox's universes API.
- Zombies are the children of `workspace.AI.Walkers` (150+ of them), each with a `HumanoidRootPart`
  (path given by the user from Dex). Registered as the "Zombies" ESP source (also what the aim assist targets when Target Zombies is on), labelled with the model's
  `Name`. Not known yet: whether they have a `Humanoid` (no health bar without one) and what they are named.
- The Loot tab (Loot ESP and Auto Loot sections) is placeholder controls only. Needed from Dex before
  either can work: where loot instances live, what they are (Model / Part / Tool), and how the game
  picks one up (ProximityPrompt, ClickDetector, touch or a remote).
- The Player and Misc tabs are still placeholders too.
