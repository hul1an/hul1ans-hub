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

local markers = hub.require("core/markers.lua")
markers.start()

local warned = {}

-- children of workspace.<path>, warning once if the path is missing
local function children(...)
	local instance = workspace
	for _, name in { ... } do
		instance = instance:FindFirstChild(name)
		if not instance then
			local path = "workspace." .. table.concat({ ... }, ".")
			if not warned[path] then
				warned[path] = true
				warn("[hub] " .. path .. " not found")
			end
			return {}
		end
	end
	return instance:GetChildren()
end

hub.require("core/esp.lua").addSource("Zombies", Color3.fromRGB(110, 150, 90), function()
	return children("AI", "Walkers")
end, function(model)
	return model.Name
end)

local corpses = markers.add(Color3.fromRGB(200, 170, 90), function()
	return children("Corpses")
end, function(corpse, distance)
	local lines = { corpse.Name .. " [" .. math.floor(distance) .. "]" }
	local items = corpse:FindFirstChild("Loot_Corpse")
	if items then
		for _, item in items:GetChildren() do
			table.insert(lines, item.Name)
		end
	end
	return table.concat(lines, "\n")
end)

hub.require("universal.lua")(window)

local loot = window:CreateTab("Loot")
local lootEsp = loot:CreateSection("Loot ESP", "LeftSide")
lootEsp:CreateToggle("Enabled", false, placeholder("Loot ESP"))
lootEsp:CreateSlider("Max Distance", 0, 3000, 500, true, placeholder("Loot ESP Max Distance"))
local autoLoot = loot:CreateSection("Auto Loot", "RightSide")
autoLoot:CreateToggle("Enabled", false, placeholder("Auto Loot"))
autoLoot:CreateSlider("Range", 0, 50, 15, true, placeholder("Auto Loot Range"))

local corpseEsp = loot:CreateSection("Corpse ESP", "LeftSide")
corpseEsp:CreateToggle("Enabled", corpses.enabled, function(value)
	corpses.enabled = value
end)
-- a new picker shows black until it is given a colour
corpseEsp:CreateColorpicker("Color", function(color)
	corpses.color = color
end):UpdateColor(corpses.color)
corpseEsp:CreateSlider("Max Distance", 0, 3000, corpses.maxDistance, true, function(value)
	corpses.maxDistance = value
end)

local player = window:CreateTab("Player")
local movement = player:CreateSection("Movement")
movement:CreateSlider("Speed", 16, 100, 16, true, placeholder("Speed"))
movement:CreateToggle("Infinite Stamina", false, placeholder("Infinite Stamina"))

local misc = window:CreateTab("Misc")
local utility = misc:CreateSection("Utility")
utility:CreateButton("Teleport", placeholder("Teleport"))
misc:CreateSection("Hub"):CreateButton("Eject", hub.unload)

ready = true
