local hub = ...

local window = hub.ui.createWindow("The Walking Dead Online")

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

local config = hub.require("core/config.lua")
local FILTER_FILE = "walking_dead_online_filter"

-- names are exact item names; with the filter on only those items are shown or looted
local filter = config.load(FILTER_FILE) or { enabled = false, names = {} }

local function allowed(name)
	return not filter.enabled or table.find(filter.names, name) ~= nil
end

-- one line per item that passes the filter, to go under a marker's heading
local function itemLines(items)
	local body = ""
	for _, item in items do
		if allowed(item.Name) then
			body ..= "\n" .. item.Name
		end
	end
	return body
end

local floorLoot = markers.add(Color3.fromRGB(120, 190, 255), function()
	return children("PhysicalLoot")
end, function(item)
	if not allowed(item.Name) then
		return nil
	end
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
			local body = itemLines(child:GetChildren())
			if body == "" then
				return nil
			end
			return kind, body
		end
	end
	return nil
end)
containers.maxDistance = 300
containers.interval = 10

-- an empty corpse is still marked unless the filter is on
local corpses = markers.add(Color3.fromRGB(200, 170, 90), function()
	return children("Corpses")
end, function(corpse)
	local items = corpse:FindFirstChild("Loot_Corpse")
	local body = items and itemLines(items:GetChildren()) or ""
	if filter.enabled and body == "" then
		return nil
	end
	return corpse.Name, body
end)
corpses.interval = 10

hub.require("universal.lua")(window)

local loot = window:CreateTab("Loot", "folder")

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

loot:CreateSection("Auto Loot", "RightSide"):CreateToggle("Enabled", false, placeholder("Auto Loot"))

local filterTab = window:CreateTab("Loot Filter", "layers")
local filterSection = filterTab:CreateSection("Loot Filter", "LeftSide")
local filterItems = filterTab:CreateSection("Filter (click to remove)", "RightSide")
local filterButtons = {}

local function filterChanged()
	config.save(FILTER_FILE, filter)
	markers.rescan()
end

local function addFilterButton(name)
	filterButtons[name] = filterItems:CreateButton(name, function()
		table.remove(filter.names, table.find(filter.names, name))
		filterButtons[name]:Remove()
		filterButtons[name] = nil
		filterChanged()
	end)
end

for _, name in filter.names do
	addFilterButton(name)
end

filterSection:CreateToggle("Enabled", filter.enabled, function(value)
	filter.enabled = value
	if ready then
		filterChanged()
	end
end)

-- every item name in floor loot, containers and corpses right now
local function availableLoot()
	local names = {}
	local found = {}
	local function add(items)
		for _, item in items do
			if not found[item.Name] then
				found[item.Name] = true
				table.insert(names, item.Name)
			end
		end
	end

	add(children("PhysicalLoot"))
	for _, folder in { "Lootables", "Corpses" } do
		for _, holder in children(folder) do
			for _, child in holder:GetChildren() do
				if child.Name:match("^Loot_") then
					add(child:GetChildren())
				end
			end
		end
	end

	table.sort(names)
	return names
end

local available = filterSection:CreateDropdown("Available Loot", availableLoot(), function(name)
	if not table.find(filter.names, name) then
		table.insert(filter.names, name)
		addFilterButton(name)
		filterChanged()
	end
end)
filterSection:CreateButton("Refresh Available Loot", function()
	available:ClearOptions()
	for _, name in availableLoot() do
		available:AddOption(name)
	end
end)
filterSection:CreateButton("Clear Filter", function()
	for _, button in filterButtons do
		button:Remove()
	end
	table.clear(filterButtons)
	table.clear(filter.names)
	filterChanged()
end)

local player = window:CreateTab("Player", "hanger")
local movement = player:CreateSection("Movement")
movement:CreateSlider("Speed", 16, 100, 16, true, placeholder("Speed"))
movement:CreateToggle("Infinite Stamina", false, placeholder("Infinite Stamina"))

local misc = window:CreateTab("Misc", "settings")
local utility = misc:CreateSection("Utility")
utility:CreateButton("Teleport", placeholder("Teleport"))
misc:CreateSection("Hub"):CreateButton("Eject", hub.unload)

ready = true
