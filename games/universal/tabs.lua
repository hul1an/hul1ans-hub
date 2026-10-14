local hub = ...

local esp = hub.require("games/universal/esp.lua")
local aim = hub.require("games/universal/aim.lua")

-- the hub's own, the R15 body with the R6 parts that stand in for it; starline's are head, chest, stomach, pelvis, arms,
-- legs and feet
local HITGROUPS = { "head", "upper torso", "lower torso", "arms", "hands", "legs", "feet" }
-- what a Highlight can draw through walls: its fill and its outline
local THROUGH = { "solid", "glow" }
-- starline's colours for the name of a whitelisted player on the list and of a high priority one
local WHITELISTED = Color3.new(0, 1, 0)
local PRIORITY = Color3.new(1, 0, 0)
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

-- one of starline's player pages, its esp and chams cards, on the options of the enemies, the teammates or the user's
-- own character. Only the enemies' page has chams: Roblox draws 31 Highlights
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
	row(card, "avatar", "Avatar", true)
	row(card, "weapon name", "WeaponName")
	row(card, "skeleton", "Skeleton")
	row(card, "health bar", "HealthBar")
	local arrows = group(card, "offscreen arrows", settings, "Arrows")
	color(arrows.header, settings, "ArrowsColor")
	color(toggle(arrows, "shadow", settings, "ArrowsShadow"), settings, "ArrowsShadowColor")
	color(toggle(arrows, "outline", settings, "ArrowsOutline"), settings, "ArrowsOutlineColor")
	slider(arrows, "size", settings, "ArrowsSize", 4, 24, true)
	slider(arrows, "offset", settings, "ArrowsOffset", 0, 48, true)

	if settings ~= esp.enemies.settings then
		return
	end
	local chams = page:CreateSection("chams", "RightSide")
	-- a chams row: its fold, with the colour and opacity on its header. key is the row's esp setting, which the others
	-- are named after
	local function fold(label, key)
		local control = group(chams, label, settings, key)
		color(control.header, settings, key .. "Color", key .. "Opacity")
		return control
	end
	fold("visible", "VisibleChams")
	-- a Highlight shows one thing through walls, so this takes the place of the visible row when both are on
	dropdown(fold("invisible", "InvisibleChams"), "material", settings, "InvisibleChamsMaterial", THROUGH)
end

-- starline's player list: everyone in the game, and for the one picked the options the esp keeps under their name.
-- roster is main.lua's, the enemies and the teammates
local function addList(tab, roster)
	-- the picked player's options
	local options = {}
	-- the card's toggles by the option each keeps, its two sliders, and every row with who it is for: "enemy", "other"
	-- (anyone but the user) or "own"
	local flags, rows = {}, {}
	local fov, reaction

	local card = tab:CreateSubTab("list"):CreatePlayerList(function()
		local enemies, teammates = roster()
		for _, players in { enemies, teammates } do
			for _, player in players do
				local set = esp.overrides[player.id]
				player.color = set and (set.whitelist and WHITELISTED or set.priority and PRIORITY) or nil
				player.image = "rbxthumb://type=AvatarHeadShot&id=" .. player.userId .. "&w=48&h=48"
				player.info = { { "userid", tostring(player.userId) } }
			end
		end
		return { { name = "enemies", players = enemies }, { name = "teammates", players = teammates } }
	end, function(player, group)
		options = esp.overrides[player.id] or {}
		esp.overrides[player.id] = options
		local kind = player.you and "own" or group == "enemies" and "enemy" or "other"
		for _, entry in rows do
			entry.control.row.Visible = entry.who == kind or entry.who == "other" and kind == "enemy"
		end
		for key, control in flags do
			control:Set(options[key] or false)
		end
		fov:Set(options.fov or 0)
		reaction:Set(options.reaction and options.reaction / 1000 or REACTION)
	end)

	local function row(control, who)
		table.insert(rows, { control = control, who = who })
		return control
	end

	local function flag(name, key, who)
		flags[key] = row(card:CreateToggle(name, false, function(value)
			options[key] = value or nil
		end), who)
	end

	flag("whitelist", "whitelist", "enemy")
	flag("high priority", "priority", "enemy")
	-- both sliders say default at the end that leaves the player to the aimbot's and the trigger's own settings
	fov = row(card:CreateSlider("fov amount", 0, 30, 0, false, function(value)
		options.fov = value > 0 and value or nil
	end, function(value)
		return value > 0 and string.format("%.1f", value) or "default"
	end), "enemy")
	reaction = row(card:CreateSlider("trigger reaction", 0, REACTION, REACTION, false, function(value)
		options.reaction = value < REACTION and value * 1000 or nil
	end, function(value)
		return value < REACTION and string.format("%.3fs", value) or "default"
	end), "enemy")
	flag("disable visuals", "hidden", "other")
end

local function addPlayers(window, roster)
	local tab = window:CreateTab("players", "users")
	addPlayerPage(tab, "enemies", esp.enemies.settings)
	addPlayerPage(tab, "teammates", esp.teammates.settings)
	addPlayerPage(tab, "local", esp.own.settings)
	addList(tab, roster)
end

local function addVisuals(window, features)
	local options = features.world.settings
	local tab = window:CreateTab("visuals", "eye")
	local page = tab:CreateSubTab("world")

	local general = page:CreateSection("general")
	local rain = group(general, "precipitation", options, "precipitation")
	multi(rain, "types", options, "weather", { "rain", "snow", "leaves", "ashes", "embers" })
	toggle(rain, "outdoors only", options, "outdoors")
	slider(rain, "particles", options, "particles", 24, 1024, true)
	local fog = group(general, "fog", options, "fog")
	slider(fog, "density", options, "fogDensity", 0, 100, true, "%.0f%%")
	slider(fog, "start", options, "fogStart", 0, 2000, true)
	slider(fog, "end", options, "fogEnd", 0, 5000, true)
	-- the hub's own
	general:CreateToggle("night mode", false, features.world.setNight)

	-- a row's setting is its colour's name without Color on the end
	local function tinted(card, label, key)
		color(toggle(card, label, options, key), options, key .. "Color")
	end

	local modulation = page:CreateSection("modulation")
	tinted(modulation, "world", "tint")
	tinted(modulation, "sun", "sun")
	tinted(modulation, "light", "light")
	tinted(modulation, "ambience", "ambience")

	local effects = page:CreateSection("effects")
	local bloom = group(effects, "bloom", options, "bloom")
	slider(bloom, "bloom scale", options, "bloomScale", 0, 100, true)
	slider(bloom, "threshold", options, "bloomThreshold", 0, 2, false, "%.2f")
	slider(bloom, "blur strength", options, "bloomBlur", 0, 100, true)
	slider(group(effects, "motion blur", options, "motionBlur"), "amount", options, "motionBlurAmount", 0, 1, false, "%.2f")

	local view = page:CreateSection("view")
	slider(group(view, "override fov", options, "fov"), "field of view", options, "fovValue", 30, 120, true)
	slider(view, "aspect ratio", options, "aspectRatio", 0, 2, false, "%.2f")
	local third = group(view, "third person", options, "thirdPerson")
	third.header:CreateKeybind("NONE")
	-- in studs
	slider(third, "distance", options, "thirdPersonDistance", 5, 30, true)
	multi(view, "visual removals", options, "removals", { "2d skybox", "shadows", "lights", "post process", "fog" })
end

local function addMisc(window, features)
	local hud, movement = features.hud.settings, features.movement.settings
	local tab = window:CreateTab("misc", "settings")
	local general = tab:CreateSubTab("general")

	local main = general:CreateSection("main")
	-- the hub's own
	main:CreateButton("eject", hub.unload)

	local overlays = general:CreateSection("hud")
	-- starline keeps the watermark's parts on the widget itself
	multi(group(overlays, "watermark", hud, "watermark"), "show", hud, "watermarkShow", { "username", "time", "ping", "fps" })
	toggle(overlays, "keybind list", hud, "keybinds")

	local page = tab:CreateSubTab("movement")

	local card = page:CreateSection("movement")
	-- starline's auto jump is the hub's bunnyhop
	toggle(card, "auto jump", movement, "bunnyhop")

	local graph = page:CreateSection("velocity graph")
	color(toggle(graph, "enabled", hud, "graph"), hud, "graphColor", "graphOpacity")
	-- the two of starline's seven that the hub's movement has
	multi(graph, "log events", hud, "graphEvents", { "landing speed", "jump length" })
	slider(graph, "width", hud, "graphWidth", 200, 700, true)
	slider(graph, "height", hud, "graphHeight", 70, 260, true)
	slider(graph, "bg opacity", hud, "graphBack", 0, 1, false)
end

-- starline's tabs, sub-tabs and cards in its order. features is what main.lua has behind them: the roster, world.lua,
-- movement.lua and hud.lua
return function(window, features)
	addAimbot(window)
	addPlayers(window, features.roster)
	addVisuals(window, features)
	addMisc(window, features)
end
