local hub = ...

local window = hub.ui.createWindow("The Walking Dead Online")

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

-- names are exact item names; with the filter on only those items are shown
local filter = config.load(FILTER_FILE) or { enabled = false, names = {} }

local function allowed(name)
	return not filter.enabled or table.find(filter.names, name) ~= nil
end

-- a container's loot part also holds its own SurfaceAppearance, Highlight and Sound; only an item has an ID
local function lootItems(holder)
	local items = {}
	for _, child in holder:GetChildren() do
		if child:GetAttribute("ID") then
			table.insert(items, child)
		end
	end
	return items
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
			local body = itemLines(lootItems(child))
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
	section:CreateColorpicker("Color", function(color)
		group.color = color
	end):UpdateColor(group.color)
	if rescan then
		section:CreateSlider("Rescan Delay", 5, 60, group.interval, true, function(value)
			group.interval = value
		end)
	end
end

markerSection("Floor Loot ESP", floorLoot, false)
markerSection("Container ESP", containers, true)
markerSection("Corpse ESP", corpses, true)

local filterTab = window:CreateTab("Loot Filter", "layers")
local filterSection = filterTab:CreateSection("Loot Filter", "LeftSide")

local function filterChanged()
	config.save(FILTER_FILE, filter)
	markers.rescan()
end

-- every item name in floor loot, containers and corpses right now
local function scanLoot()
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
					-- corpse items haven't been seen, so they aren't asked for an ID yet
					add(folder == "Lootables" and lootItems(child) or child:GetChildren())
				end
			end
		end
	end

	table.sort(names)
	return names
end

local scanned = scanLoot()

-- Matcha has no removable buttons: a name is added from Available Loot and taken out by picking it in In Filter
local sync

local inFilter = filterTab:CreateSection("Filter (pick to remove)", "RightSide"):CreateDropdown("In Filter", {}, function(name)
	table.remove(filter.names, table.find(filter.names, name))
	sync()
	filterChanged()
end)

local available = filterSection:CreateDropdown("Available Loot", {}, function(name)
	if not table.find(filter.names, name) then
		table.insert(filter.names, name)
		sync()
		filterChanged()
	end
end)

-- the current lists: every name in the filter, and every scanned name not in it
function sync()
	inFilter:ClearOptions()
	for _, name in filter.names do
		inFilter:AddOption(name)
	end
	available:ClearOptions()
	for _, name in scanned do
		if not table.find(filter.names, name) then
			available:AddOption(name)
		end
	end
end
sync()

filterSection:CreateToggle("Enabled", filter.enabled, function(value)
	filter.enabled = value
	filterChanged()
end)
filterSection:CreateButton("Refresh Available Loot", function()
	scanned = scanLoot()
	sync()
end)
filterSection:CreateButton("Clear Filter", function()
	table.clear(filter.names)
	sync()
	filterChanged()
end)

window:CreateTab("Misc", "settings"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
