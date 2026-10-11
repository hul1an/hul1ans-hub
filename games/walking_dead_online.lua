local hub = ...

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

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

-- seconds between takes: by hand they went through 0.22 apart, faster is untried
local TAKE_DELAY = 0.2
-- source is the loot part of the inventory the game last opened, fresh until auto loot has gone through it
local autoLoot = { enabled = false }

-- ReplicatedStorage.CLIENT_REMOTES.<name>, with a notice if it is missing
local function clientRemote(name)
	local folder = ReplicatedStorage:FindFirstChild("CLIENT_REMOTES")
	local remote = folder and folder:FindFirstChild(name)
	if not remote then
		local message = "ReplicatedStorage.CLIENT_REMOTES." .. name .. " not found: auto loot unavailable"
		warn("[hub] " .. message)
		hub.ui.notify(message, "error")
	end
	return remote
end

local updateStorage = clientRemote("UpdateStorageUI")
local transferItem = clientRemote("TransferItem")
local toggleInventory = clientRemote("ToggleInventory")

if updateStorage and transferItem and toggleInventory then
	-- the game sends UpdateStorageUI with the loot part when an inventory is opened and ToggleInventory when it is closed
	local original
	original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		if getnamecallmethod() == "FireServer" then
			if self == updateStorage then
				autoLoot.source = (...)
				autoLoot.fresh = true
			elseif self == toggleInventory then
				autoLoot.source = nil
			end
		end
		return original(self, ...)
	end))
	hub.cleanup.add(function()
		hookmetamethod(game, "__namecall", original)
	end)

	-- the server answers an open, and every take, with an empty UpdateStorageUI
	hub.cleanup.add(updateStorage.OnClientEvent:Connect(function()
		local source = autoLoot.source
		if not (source and autoLoot.fresh and autoLoot.enabled) then
			return
		end
		autoLoot.fresh = false
		for _, item in lootItems(source) do
			-- closed, or another inventory opened
			if autoLoot.source ~= source or not autoLoot.enabled then
				return
			end
			if allowed(item.Name) then
				-- what the game sends for a quick move: the item, the inventory it goes to, the one it is in
				transferItem:FireServer(
					item:GetAttribute("ID"),
					"Main",
					item:GetAttribute("Container"),
					{ SourceObject = source }
				)
				task.wait(TAKE_DELAY)
			end
		end
	end))
end

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

loot:CreateSection("Auto Loot", "RightSide"):CreateToggle("Enabled", autoLoot.enabled, function(value)
	autoLoot.enabled = value
end)

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
					-- corpse items haven't been seen, so they aren't asked for an ID yet
					add(folder == "Lootables" and lootItems(child) or child:GetChildren())
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

-- temporary: the remote logger, to learn what the game sends when an item is taken from a container.
-- Its button records every remote call the game makes and what CLIENT_REMOTES fires back, and writes
-- hul1ans-hub/walking_dead_online_remotes.json every 2 seconds until Eject
local LOG_FILE = "walking_dead_online_remotes"
-- a remote that fires constantly would bury the rest
local LOG_PER_REMOTE = 25
local log = { counts = {}, events = {} }

-- a value as something JSONEncode takes; binary is written as hex, 2048 bytes of it at most
local function plain(value)
	local kind = typeof(value)
	if kind == "boolean" then
		return value
	elseif kind == "number" then
		return (value ~= value or math.abs(value) == math.huge) and tostring(value) or value
	elseif kind == "string" and not value:find("[^ -~]") then
		return value:sub(1, 200)
	elseif kind == "string" or kind == "buffer" then
		local bytes = kind == "buffer" and buffer.tostring(value) or value
		local hex = bytes:sub(1, 2048):gsub(".", function(byte)
			return ("%02x"):format(byte:byte())
		end)
		return ("%s[%d] %s"):format(kind, #bytes, hex)
	end
	return kind .. " " .. tostring(value)
end

local describe

-- a table as nested plain values, cut off at a depth and at 40 keys
local function shape(value, depth)
	if typeof(value) == "Instance" then
		return describe(value, 1)
	elseif type(value) ~= "table" then
		return plain(value)
	elseif depth == 0 then
		return "table"
	end
	local out, count = {}, 0
	for key, item in next, value do
		count += 1
		if count > 40 then
			out["..."] = "more"
			break
		end
		out[tostring(plain(key))] = shape(item, depth - 1)
	end
	return out
end

-- an instance with its attributes and, to a depth, its first 40 children: an item's id or amount may be on either
function describe(instance, depth)
	local out = {
		class = instance.ClassName,
		path = instance:GetFullName(),
		attributes = shape(instance:GetAttributes(), 1),
	}
	if instance:IsA("ValueBase") then
		out.value = shape(instance.Value, 0)
	end
	if depth > 0 then
		out.children = {}
		for index, child in instance:GetChildren() do
			if index > 40 then
				break
			end
			table.insert(out.children, describe(child, depth - 1))
		end
	end
	return out
end

local function record(method, remote, ...)
	local key = method .. " " .. remote:GetFullName()
	local count = (log.counts[key] or 0) + 1
	log.counts[key] = count
	if count <= LOG_PER_REMOTE then
		table.insert(log.events, {
			at = os.clock() - log.started,
			remote = key,
			arguments = shape(table.pack(...), 4),
		})
	end
end

local function logRemotes()
	if log.started then
		return
	end
	log.started = os.clock()

	local remotes = ReplicatedStorage:FindFirstChild("CLIENT_REMOTES")
	if remotes then
		for _, remote in remotes:GetDescendants() do
			if remote:IsA("BaseRemoteEvent") then
				hub.cleanup.add(remote.OnClientEvent:Connect(function(...)
					record("OnClientEvent", remote, ...)
				end))
			end
		end
	else
		warn("[hub] ReplicatedStorage.CLIENT_REMOTES not found: only the game's own calls are logged")
		hub.ui.notify("ReplicatedStorage.CLIENT_REMOTES not found: only the game's own calls are logged", "error")
	end

	local original
	original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local method = getnamecallmethod()
		if method == "FireServer" or method == "InvokeServer" then
			-- in its own thread: a method call made here would replace the name the game's call is about to
			-- use, and an error in it stays out of the game's call
			task.spawn(record, method, self, ...)
		end
		return original(self, ...)
	end))
	hub.cleanup.add(function()
		hookmetamethod(game, "__namecall", original)
	end)

	hub.cleanup.add(task.spawn(function()
		while true do
			config.save(LOG_FILE, log)
			task.wait(2)
		end
	end))
	hub.ui.notify("remote logger on: writing hul1ans-hub/" .. LOG_FILE .. ".json", "success")
end

local misc = window:CreateTab("Misc", "settings")
local utility = misc:CreateSection("Utility")
utility:CreateButton("Teleport", placeholder("Teleport"))
misc:CreateSection("Debug"):CreateButton("Remote Logger", logRemotes)
misc:CreateSection("Hub"):CreateButton("Eject", hub.unload)

ready = true
