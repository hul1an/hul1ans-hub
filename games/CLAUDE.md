# Game notes

## The Walking Dead Online

- Place id `128039018996175`, universe (`game.GameId`) `7208219743`, from Roblox's universes API.
- Zombies are the children of `workspace.AI.Walkers` (150+ of them), each with a `HumanoidRootPart`
  (path given by the user from Dex). Registered as the "Zombies" ESP source (also what the aim assist targets when Target Zombies is on), labelled with the model's
  `Name`. Not known yet: whether they have a `Humanoid` (no health bar without one) and what they are named.
- Everything else in `games/walking_dead_online.lua` is still a placeholder.
