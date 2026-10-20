local hub = ...

local esp = hub.require("games/universal/esp.lua")
local aim = hub.require("games/universal/aim.lua")

-- the hub's own, the R15 body with the R6 parts that stand in for it; starline's are head, chest, stomach, pelvis, arms,
-- legs and feet
local HITGROUPS = { "head", "upper torso", "lower torso", "arms", "hands", "legs", "feet" }
-- where the list's trigger reaction slider ends, in seconds, which is its default
local REACTION = 0.65

-- controls kept in a key of a settings table
local function toggle(parent, name, settings, key)
	return parent:CreateToggle(name, settings[key], function(value)
		settings[key] = value
	end)
end

local function group(parent, name, settings, key)
	return parent:CreateGroup(name, settings[key], function(value)
		settings[key] = value
	end)
end

local function slider(parent, name, settings, key, min, max, precise, format)
	parent:CreateSlider(name, min, max, settings[key], precise, function(value)
		settings[key] = value
	end, format)
end

local function dropdown(parent, name, settings, key, options)
	parent:CreateDropdown(name, options, function(value)
		settings[key] = value
	end, settings[key])
end

local function multi(parent, name, settings, key, options)
	parent:CreateMultiDropdown(name, options, function(value)
		settings[key] = value
	end, settings[key])
end

-- the swatch of a toggle or of a group's header. opacity is the key of the setting its picker's opacity bar keeps, for
-- a colour that has one
local function color(control, settings, key, opacity)
	control:CreateColorpicker(function(value, amount)
		settings[key] = value
		if opacity then
			settings[opacity] = amount
		end
	end, opacity ~= nil):UpdateColor(settings[key], opacity and settings[opacity])
end

local function addAimbot(window)
	local settings = aim.settings
	local tab = window:CreateTab("aimbot", "crosshairs")
	local page = tab:CreateSubTab("aimbot")

	local general = page:CreateSection("general", "LeftSide")
	local enabled = group(general, "enabled", settings, "Enabled")
	enabled.header:CreateKeybind("NONE")
	local fov = toggle(enabled, "draw fov", settings, "DrawFov")
	color(fov, settings, "FovColor")
	multi(general, "disablers", settings, "Disablers", { "jump" })

	local targeting = page:CreateSection("targeting", "LeftSide")
	dropdown(targeting, "target selection", settings, "Selection", { "fov", "health", "distance" })
	dropdown(targeting, "fov mode", settings, "FovMode", { "static", "dynamic" })
	slider(targeting, "max fov", settings, "Fov", 0, 30, false)
	multi(targeting, "hitgroups", settings, "Hitgroups", HITGROUPS)
	slider(group(targeting, "multipoint", settings, "Multipoint"), "scale", settings, "MultipointScale", 0, 100, true, "%.0f%%")

	local behavior = page:CreateSection("behavior", "RightSide")
	local smoothing = group(behavior, "smoothing", settings, "Smoothing")
	slider(smoothing, "value", settings, "SmoothingValue", 5, 50, false, "%.1f")
	slider(smoothing, "humanization", settings, "Humanization", 0, 100, true, "%.0f%%")
	slider(smoothing, "sticky", settings, "Sticky", 0, 100, true, "%.0f%%")
	slider(behavior, "switch delay", settings, "SwitchDelay", 0, 500, true, "%.0fms")
	slider(behavior, "mouse override", settings, "MouseOverride", 0, 100, true, "%.0f%%")

	local assist = tab:CreateSubTab("assist")

	local trigger = assist:CreateSection("triggerbot", "LeftSide")
	toggle(trigger, "enabled", settings, "Trigger")
	multi(trigger, "hitgroups", settings, "TriggerHitgroups", HITGROUPS)
	slider(trigger, "delay", settings, "TriggerDelay", 0, 250, true, "%.0fms")
	slider(trigger, "visible delay", settings, "TriggerVisibleDelay", 0, 650, true, "%.0fms")
	slider(trigger, "burst", settings, "TriggerBurst", 0, 250, true, "%.0fms")
	toggle(trigger, "randomize", settings, "TriggerRandomize")
end

-- one of starline's player pages, its esp card, on the options of the enemies, the teammates or the user's own
-- character. Matcha can't make a Highlight, so the chams card isn't here
local function addPlayerPage(tab, name, settings)
	local page = tab:CreateSubTab(name)

	-- key is the esp setting behind a row, whose colour is the same key with Color on the end; plain is a row starline
	-- has no colour on
	local function row(card, label, key, plain)
		local control = toggle(card, label, settings, key)
		if not plain then
			color(control, settings, key .. "Color")
		end
	end

	local card = page:CreateSection("esp", "LeftSide")
	row(card, "enabled", "Enabled", true)
	row(card, "only visible", "OnlyVisible", true)
	row(card, "bounding box", "Box")
	row(card, "name", "Name")
	row(card, "weapon name", "WeaponName")
	row(card, "skeleton", "Skeleton")
	row(card, "health bar", "HealthBar")
	local arrows = group(card, "offscreen arrows", settings, "Arrows")
	color(arrows.header, settings, "ArrowsColor")
	color(toggle(arrows, "shadow", settings, "ArrowsShadow"), settings, "ArrowsShadowColor")
	slider(arrows, "size", settings, "ArrowsSize", 4, 24, true)
	slider(arrows, "offset", settings, "ArrowsOffset", 0, 48, true)
end

-- starline's player list: everyone in the game, and for the one picked the options the esp keeps under their name.
-- roster is main.lua's, the enemies and the teammates. Matcha shows every row for everyone, and no colours
local function addList(tab, roster)
	-- the picked player's options
	local options = {}
	-- the card's toggles by the option each keeps, and its two sliders
	local flags = {}
	local fov, reaction

	local card = tab:CreateSubTab("list"):CreatePlayerList(function()
		local enemies, teammates = roster()
		return { { name = "enemies", players = enemies }, { name = "teammates", players = teammates } }
	end, function(player)
		options = esp.overrides[player.id] or {}
		esp.overrides[player.id] = options
		for key, control in flags do
			control:Set(options[key] or false)
		end
		fov:Set(options.fov or 0)
		reaction:Set(options.reaction and options.reaction / 1000 or REACTION)
	end)

	local function flag(name, key)
		flags[key] = card:CreateToggle(name, false, function(value)
			options[key] = value or nil
		end)
	end

	flag("whitelist", "whitelist")
	flag("high priority", "priority")
	-- both sliders leave the player to the aimbot's and the trigger's own settings at the end that is their default
	fov = card:CreateSlider("fov amount (0 is default)", 0, 30, 0, false, function(value)
		options.fov = value > 0 and value or nil
	end, "%.1f")
	reaction = card:CreateSlider("trigger reaction (max is default)", 0, REACTION, REACTION, false, function(value)
		options.reaction = value < REACTION and value * 1000 or nil
	end, "%.2f")
	flag("disable visuals", "hidden")
end

local function addPlayers(window, roster)
	local tab = window:CreateTab("players", "users")
	addPlayerPage(tab, "enemies", esp.enemies.settings)
	addPlayerPage(tab, "teammates", esp.teammates.settings)
	addPlayerPage(tab, "local", esp.own.settings)
	addList(tab, roster)
end

-- Matcha documents three Lighting properties and no way to make an effect, so the world page is night mode, ambience,
-- the field of view and the aspect ratio
local function addVisuals(window, features)
	local options = features.world.settings
	local tab = window:CreateTab("visuals", "eye")
	local page = tab:CreateSubTab("world")

	local general = page:CreateSection("general")
	-- the hub's own
	general:CreateToggle("night mode", false, features.world.setNight)

	local modulation = page:CreateSection("modulation")
	color(toggle(modulation, "ambience", options, "ambience"), options, "ambienceColor")

	local view = page:CreateSection("view")
	slider(group(view, "override fov", options, "fov"), "field of view", options, "fovValue", 30, 120, true)
	slider(view, "aspect ratio", options, "aspectRatio", 0, 2, false, "%.2f")
end

local function addMisc(window, features)
	local hud = features.hud.settings
	local tab = window:CreateTab("misc", "settings")
	local general = tab:CreateSubTab("general")

	local main = general:CreateSection("main")
	-- the hub's own
	main:CreateButton("eject", hub.unload)

	local overlays = general:CreateSection("hud")
	-- starline keeps the watermark's parts on the widget itself
	multi(group(overlays, "watermark", hud, "watermark"), "show", hud, "watermarkShow", { "username", "ping", "fps" })

	local page = tab:CreateSubTab("movement")

	local graph = page:CreateSection("velocity graph")
	color(toggle(graph, "enabled", hud, "graph"), hud, "graphColor", "graphOpacity")
	slider(graph, "width", hud, "graphWidth", 200, 700, true)
	slider(graph, "height", hud, "graphHeight", 70, 260, true)
	slider(graph, "bg opacity", hud, "graphBack", 0, 1, false, "%.2f")
end

-- starline's tabs, sub-tabs and cards in its order. features is what main.lua has behind them: the roster, world.lua
-- and hud.lua
return function(window, features)
	addAimbot(window)
	addPlayers(window, features.roster)
	addVisuals(window, features)
	addMisc(window, features)
end
