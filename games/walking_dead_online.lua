local hub = ...

local window = hub.bracket.createWindow("The Walking Dead Online")

-- Bracket fires every callback once while the controls are built
local ready = false

local function placeholder(name)
	return function(value)
		if ready then
			print("[hub] " .. name .. " (placeholder)", value)
		end
	end
end

local warned = false
hub.require("core/esp.lua").addSource("Zombies", Color3.fromRGB(110, 150, 90), function()
	local ai = workspace:FindFirstChild("AI")
	local walkers = ai and ai:FindFirstChild("Walkers")
	if not walkers then
		if not warned then
			warned = true
			warn("[hub] workspace.AI.Walkers not found, zombie ESP skipped")
		end
		return {}
	end
	return walkers:GetChildren()
end, function(model)
	return model.Name
end)

hub.require("universal.lua")(window)

local loot = window:CreateTab("Loot")
local lootEsp = loot:CreateSection("Loot ESP", "LeftSide")
lootEsp:CreateToggle("Enabled", false, placeholder("Loot ESP"))
lootEsp:CreateSlider("Max Distance", 0, 3000, 500, true, placeholder("Loot ESP Max Distance"))
local autoLoot = loot:CreateSection("Auto Loot", "RightSide")
autoLoot:CreateToggle("Enabled", false, placeholder("Auto Loot"))
autoLoot:CreateSlider("Range", 0, 50, 15, true, placeholder("Auto Loot Range"))

local player = window:CreateTab("Player")
local movement = player:CreateSection("Movement")
movement:CreateSlider("Speed", 16, 100, 16, true, placeholder("Speed"))
movement:CreateToggle("Infinite Stamina", false, placeholder("Infinite Stamina"))

local misc = window:CreateTab("Misc")
local utility = misc:CreateSection("Utility")
utility:CreateButton("Teleport", placeholder("Teleport"))
misc:CreateSection("Hub"):CreateButton("Eject", hub.unload)

ready = true
