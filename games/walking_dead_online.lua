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

-- one line per item, to go under a marker's heading
local function itemLines(items)
	local body = ""
	for _, item in items do
		body ..= "\n" .. item.Name
	end
	return body
end

local floorLoot = markers.add(Color3.fromRGB(120, 190, 255), function()
	return children("PhysicalLoot")
end, function(item)
	return item.Name, ""
end)
floorLoot.maxDistance = 300

-- a container keeps its items in a child named Loot_<kind>; emptied ones are skipped
local containers = markers.add(Color3.fromRGB(230, 160, 80), function()
	return children("Lootables")
end, function(container)
	for _, child in container:GetChildren() do
		local kind = child.Name:match("^Loot_(.+)")
		if kind then
			local items = child:GetChildren()
			if #items == 0 then
				return nil
			end
			return kind, itemLines(items)
		end
	end
	return nil
end)
containers.maxDistance = 300
containers.interval = 10

local corpses = markers.add(Color3.fromRGB(200, 170, 90), function()
	return children("Corpses")
end, function(corpse)
	local items = corpse:FindFirstChild("Loot_Corpse")
	return corpse.Name, items and itemLines(items:GetChildren()) or ""
end)
corpses.interval = 10

hub.require("universal.lua")(window)

local loot = window:CreateTab("Loot")

local function markerSection(title, group, rescan)
	local section = loot:CreateSection(title, "LeftSide")
	section:CreateToggle("Enabled", group.enabled, function(value)
		group.enabled = value
	end)
	-- a new picker shows black until it is given a colour
	section:CreateColorpicker("Color", function(color)
		group.color = color
	end):UpdateColor(group.color)
	section:CreateSlider("Max Distance", 0, 3000, group.maxDistance, true, function(value)
		group.maxDistance = value
	end)
	if rescan then
		section:CreateSlider("Rescan Delay", 5, 60, group.interval, true, function(value)
			group.interval = value
		end)
	end
end

markerSection("Floor Loot ESP", floorLoot, false)
markerSection("Container ESP", containers, true)
markerSection("Corpse ESP", corpses, true)

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
