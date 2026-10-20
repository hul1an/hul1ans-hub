local hub = ...

local Players = game:GetService("Players")

local esp = hub.require("games/universal/esp.lua")
local aim = hub.require("games/universal/aim.lua")
local world = hub.require("games/universal/world.lua")
local hud = hub.require("games/universal/hud.lua")

aim.blocked = function()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return not humanoid or humanoid.Health <= 0
end

-- for the players › list page: everyone in the game, the enemies and the teammates, the user among the teammates. Each
-- is an id (the name the esp keeps a player's options by), a name and whether it is the user. Matcha documents no
-- DisplayName
local function roster()
	local enemies, teammates = {}, {}
	for _, player in Players:GetPlayers() do
		local you = player == Players.LocalPlayer
		table.insert((you or esp.teammate(player)) and teammates or enemies, {
			id = player.Name,
			name = player.Name,
			you = you,
		})
	end
	-- by name, so that no one changes place as players join and leave
	for _, list in { enemies, teammates } do
		table.sort(list, function(a, b)
			return a.name:lower() < b.name:lower()
		end)
	end
	return enemies, teammates
end

esp.start()
aim.start()
world.start()
hud.start()

local window = hub.ui.createWindow("Universal")
hub.require("games/universal/tabs.lua")(window, {
	roster = roster,
	world = world,
	hud = hud,
})
