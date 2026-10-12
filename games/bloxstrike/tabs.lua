local hub = ...

local esp = hub.require("games/bloxstrike/esp.lua")
local aim = hub.require("games/bloxstrike/aim.lua")
esp.start()
aim.start()

-- the hub's own, the R15 body; starline's are head, chest, stomach, pelvis, arms, legs and feet
local HITGROUPS = { "head", "upper torso", "lower torso", "arms", "hands", "legs", "feet" }
-- the dump has no options for the esp's flags; these are what the game tells the client about an enemy
local FLAGS = { "money", "armor", "kit", "scoped", "bot" }
-- the hub's chams materials; starline's are default, flat, glow, ghost, pearlescent, galaxy and more
local MATERIALS = { "solid", "flat", "glow", "ghost", "glass" }
-- the two that show through walls, which only a Highlight does: its fill and its outline
local THROUGH = { "solid", "glow" }
-- overlay and backtrack are copies standing in the world, where solid has nothing to draw with
local COPIES = { "flat", "glow", "ghost", "glass" }

local function nothing() end

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

-- placeholders: starline's controls that need game code the hub doesn't have, drawn greyed out with nothing behind
-- them. swatch is whether starline has a colour on the row
local off = {}

function off.toggle(parent, name, swatch)
	local control = parent:CreateToggle(name .. " (placeholder)", false, nothing)
	if swatch then
		control:CreateColorpicker(nothing)
	end
	control:Disable()
end

function off.group(parent, name, swatch)
	local fold = parent:CreateGroup(name .. " (placeholder)", false, nothing)
	if swatch then
		fold.header:CreateColorpicker(nothing)
	end
	fold.header:Disable()
	return fold
end

function off.slider(parent, name, min, max, format)
	parent:CreateSlider(name .. " (placeholder)", min, max, math.clamp(0, min, max), true, nothing, format):Disable()
end

function off.dropdown(parent, name, options)
	parent:CreateDropdown(name .. " (placeholder)", options or {}, nothing, options and options[1]):Disable()
end

function off.multi(parent, name, options)
	parent:CreateMultiDropdown(name .. " (placeholder)", options or {}, nothing):Disable()
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
	-- the hub's own: silent aim, and a toggle for each source but the players, who are always targeted
	toggle(general, "silent aim", settings, "SilentAim")
	for index = 2, #esp.sources do
		local source = esp.sources[index]
		toggle(general, source.aimToggle or "target " .. source.name, source, "aim")
	end
	multi(general, "disablers", settings, "Disablers", { "flash (placeholder)", "smoke (placeholder)", "jump" })

	local targeting = page:CreateSection("targeting", "LeftSide")
	dropdown(targeting, "target selection", settings, "Selection", { "fov", "health", "distance" })
	targeting:CreateDropdown(
		"hitbox selection",
		{ "closest", "highest damage (placeholder)", "dynamic (placeholder)" },
		nothing,
		"closest"
	)
	dropdown(targeting, "fov mode", settings, "FovMode", { "static", "dynamic" })
	slider(targeting, "max fov", settings, "Fov", 0, 30, false)
	multi(targeting, "hitgroups", settings, "Hitgroups", HITGROUPS)
	slider(group(targeting, "multipoint", settings, "Multipoint"), "scale", settings, "MultipointScale", 0, 100, true, "%.0f%%")
	slider(group(targeting, "backtrack", settings, "Backtrack"), "amount", settings, "BacktrackAmount", 0, 200, true, "%.0f ms")

	local behavior = page:CreateSection("behavior", "RightSide")
	local smoothing = group(behavior, "smoothing", settings, "Smoothing")
	slider(smoothing, "value", settings, "SmoothingValue", 5, 50, false, "%.1f")
	slider(smoothing, "humanization", settings, "Humanization", 0, 100, true, "%.0f%%")
	slider(smoothing, "sticky", settings, "Sticky", 0, 100, true, "%.0f%%")
	slider(behavior, "switch delay", settings, "SwitchDelay", 0, 500, true, "%.0fms")
	slider(behavior, "mouse override", settings, "MouseOverride", 0, 100, true, "%.0f%%")

	local accuracy = page:CreateSection("accuracy", "RightSide")
	toggle(accuracy, "auto wall", settings, "AutoWall")
	slider(accuracy, "min damage", settings, "MinDamage", 0, 100, true)
	toggle(accuracy, "force baim", settings, "ForceBaim")
	toggle(accuracy, "baim if lethal", settings, "BaimIfLethal")
	toggle(accuracy, "auto scope", settings, "AutoScope")

	local assist = tab:CreateSubTab("assist")

	local trigger = assist:CreateSection("triggerbot", "LeftSide")
	toggle(trigger, "enabled", settings, "Trigger")
	toggle(trigger, "auto wall", settings, "TriggerAutoWall")
	slider(group(trigger, "seeded", settings, "TriggerSeeded"), "legitimacy", settings, "TriggerLegitimacy", 0, 100, true, "%.0f%%")
	multi(trigger, "hitgroups", settings, "TriggerHitgroups", HITGROUPS)
	slider(trigger, "delay", settings, "TriggerDelay", 0, 250, true, "%.0fms")
	slider(trigger, "visible delay", settings, "TriggerVisibleDelay", 0, 650, true, "%.0fms")
	slider(trigger, "burst", settings, "TriggerBurst", 0, 250, true, "%.0fms")
	toggle(trigger, "randomize", settings, "TriggerRandomize")
	slider(trigger, "min damage", settings, "TriggerMinDamage", 0, 100, true)
	-- in the place of starline's min accuracy
	slider(trigger, "hitchance", settings, "TriggerHitchance", 0, 100, true, "%.0f%%")
	toggle(trigger, "auto scope", settings, "TriggerAutoScope")
	multi(trigger, "auto stop", settings, "TriggerAutoStop", { "early", "between shots", "in air" })

	local rcs = assist:CreateSection("rcs", "RightSide")
	off.toggle(off.group(rcs, "enabled"), "standalone")
	off.slider(off.group(rcs, "humanize"), "amount", 0, 15)
	off.slider(rcs, "vertical", 0, 100, "%.0f%%")
	off.slider(rcs, "horizontal", 0, 100, "%.0f%%")
	off.slider(rcs, "smoothing", 0, 100)
end

-- one of starline's player pages, its esp and chams cards, on the options of the enemies, the teammates or the user's
-- own character. The enemies' page has rows the other two don't: what takes a Highlight, of which Roblox draws 31, is
-- kept for them
local function addPlayerPage(tab, name, settings)
	local page = tab:CreateSubTab(name)
	local enemies = settings == esp.settings
	local own = settings == esp.own.settings

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
	row(card, "only audible", "OnlyAudible", true)
	row(card, "bounding box", "Box")
	row(card, "name", "Name")
	row(card, "avatar", "Avatar", true)
	row(card, "weapon name", "WeaponName")
	row(card, "weapon icon", "WeaponIcon")
	row(card, "skeleton", "Skeleton")
	row(card, "health bar", "HealthBar")
	row(card, "ammo bar", "AmmoBar")
	multi(card, "flags", settings, "Flags", FLAGS)
	local sounds = group(card, "sounds", settings, "Sounds")
	color(sounds.header, settings, "SoundsColor")
	dropdown(sounds, "draw type", settings, "SoundsType", { "circle", "ring" })
	slider(sounds, "radius", settings, "SoundsRadius", 5, 40, true)
	local arrows = group(card, "offscreen arrows", settings, "Arrows")
	color(arrows.header, settings, "ArrowsColor")
	color(toggle(arrows, "shadow", settings, "ArrowsShadow"), settings, "ArrowsShadowColor")
	color(toggle(arrows, "outline", settings, "ArrowsOutline"), settings, "ArrowsOutlineColor")
	slider(arrows, "size", settings, "ArrowsSize", 4, 24, true)
	slider(arrows, "offset", settings, "ArrowsOffset", 0, 48, true)

	local chams = page:CreateSection("chams", "RightSide")
	-- a chams row: its fold, the colour and opacity on its header and its material. key is the row's esp setting,
	-- which the others are named after
	local function fold(label, key, materials)
		local row = group(chams, label, settings, key)
		color(row.header, settings, key .. "Color", key .. "Opacity")
		dropdown(row, "material", settings, key .. "Material", materials)
		return row
	end
	-- solid is a Highlight's fill
	local materials = enemies and MATERIALS or COPIES
	-- the rows are in starline's order, which has the local page's own in between
	fold("visible", "VisibleChams", materials)
	if enemies then
		fold("invisible", "InvisibleChams", THROUGH)
	end
	fold("overlay", "OverlayChams", COPIES)
	if own then
		fold("viewmodel", "ViewmodelChams", COPIES)
	end
	fold("ragdoll", "RagdollChams", materials)
	if own then
		fold("viewmodel overlay", "ViewmodelOverlayChams", COPIES)
	end
	-- the hub's own: per tick and its gradient. Without per tick only the oldest place is drawn
	local ticks = group(fold("backtrack", "BacktrackChams", COPIES), "per tick", settings, "BacktrackChamsPerTick")
	toggle(ticks, "gradient", settings, "BacktrackChamsGradient")
	for _, label in { "oldest", "newest" } do
		local key = "BacktrackChams" .. label:gsub("^%l", string.upper)
		ticks:CreateColorpicker(label, function(value, amount)
			settings[key] = value
			settings[key .. "Opacity"] = amount
		end, true):UpdateColor(settings[key], settings[key .. "Opacity"])
	end
	if own then
		fold("weapon", "WeaponChams", COPIES)
		fold("weapon overlay", "WeaponOverlayChams", COPIES)
		fold("attachments", "AttachmentsChams", COPIES)
		fold("attachments overlay", "AttachmentsOverlayChams", COPIES)
	end
	local hit = fold("on hit", "HitChams", materials)
	slider(hit, "duration", settings, "HitChamsDuration", 0.1, 5, false, "%.1fs")
	if not enemies then
		return
	end
	-- a Highlight's outline
	color(toggle(hit, "glow", settings, "HitChamsGlow"), settings, "HitChamsGlowColor", "HitChamsGlowOpacity")

	-- the hub's own: a card for each of the esp's sources but the players, whose rows are the esp card's
	for index = 2, #esp.sources do
		local source = esp.sources[index]
		local section = page:CreateSection(source.name, "RightSide")
		color(toggle(section, source.toggle or "show " .. source.name, source, "enabled"), source, "color")
		if source.options then
			source.options(section)
		end
	end
end

local function addPlayers(window)
	local tab = window:CreateTab("players", "users")
	addPlayerPage(tab, "enemies", esp.settings)
	addPlayerPage(tab, "teammates", esp.teammates.settings)
	addPlayerPage(tab, "local", esp.own.settings)
	tab:CreateSubTab("list")
end

local function addVisuals(window, features)
	local visuals = features.visuals
	local tab = window:CreateTab("visuals", "eye")
	local world = tab:CreateSubTab("world")

	local general = world:CreateSection("general")
	off.dropdown(general, "skybox", { "none" })
	local rain = off.group(general, "precipitation")
	off.multi(rain, "types", { "rain", "snow", "leaves", "ashes", "embers" })
	off.toggle(rain, "outdoors only")
	off.slider(rain, "particles", 24, 1024)
	off.toggle(general, "wetness")
	local fog = off.group(general, "fog")
	off.slider(fog, "density", 0, 100)
	off.slider(fog, "start", 0, 8000)
	off.slider(fog, "end", 0, 8000)
	-- the hub's own
	general:CreateToggle("night mode", false, features.setNight)

	local modulation = world:CreateSection("modulation")
	for _, label in { "world", "sun", "light", "sky", "molotov", "smoke", "ambience" } do
		off.toggle(modulation, label, true)
	end

	local effects = world:CreateSection("effects")
	off.multi(effects, "hit markers", { "world", "screen" })
	off.toggle(effects, "damage marker", true)
	local bloom = off.group(effects, "bloom")
	off.slider(bloom, "bloom scale", 0, 100)
	off.slider(bloom, "threshold", 0, 2, "%.2f")
	off.slider(bloom, "threshold knee", 0, 1, "%.2f")
	off.slider(bloom, "blur strength", 0, 100)
	off.slider(off.group(effects, "motion blur"), "amount", 0, 1, "%.2f")
	local kill = off.group(effects, "kill effects")
	off.multi(kill, "effects", { "explosion", "taser", "lightning", "sparks", "dissolve", "shockwave" })
	off.toggle(kill, "screen shake")
	off.slider(kill, "shake strength", 2, 40)
	-- starline has no colour on this row; the hub's tracers have one
	local tracers = group(effects, "bullet tracers", visuals, "tracers")
	color(tracers.header, visuals, "tracerColor")
	slider(tracers, "size", visuals, "tracerSize", 0.05, 1, false)
	slider(tracers, "time", visuals, "tracerDuration", 0.05, 2, false)
	off.slider(off.group(effects, "impact sparks"), "particles", 16, 64)
	-- the hub's own
	toggle(effects, "hit effect", visuals, "hitEffect")

	local view = world:CreateSection("view")
	local zoom = off.group(view, "override fov")
	off.slider(zoom, "field of view", 60, 120)
	off.slider(zoom, "zoom x1", 0, 100, "%.0f%%")
	off.slider(zoom, "zoom x2", 0, 100, "%.0f%%")
	off.slider(view, "aspect ratio", 0, 2, "%.2f")
	local third = view:CreateGroup("third person", false, features.setThirdPerson)
	third.header:CreateKeybind("NONE")
	off.toggle(third, "animation")
	-- in studs; starline's runs 50 to 160 of CS2's units
	slider(third, "distance", visuals, "thirdPersonDistance", 5, 30, true)
	off.slider(off.group(view, "scoped transparency"), "alpha", 0, 100, "%.0f%%")
	-- a fold with no box of its own
	local scope = view:CreateGroup("scope overlay (placeholder)")
	scope.header:Disable()
	off.toggle(scope, "show viewmodel")
	off.slider(scope, "length", 5, 100, "%.0f%%")
	off.toggle(scope, "dynamic gap")
	off.slider(scope, "gap", 0, 100)
	off.multi(view, "visual removals", {
		"3d skybox",
		"2d skybox",
		"shadows",
		"lights",
		"smoke",
		"torso",
		"flash",
		"overhead name",
		"overhead name team",
		"ragdoll",
		"post process",
		"fog",
		"viewmodel bob",
		"bullet decals",
	})
	off.toggle(off.group(view, "force crosshair"), "while scoped")
	local viewmodel = off.group(view, "viewmodel changer")
	off.slider(viewmodel, "fov", 50, 120, "%.1f")
	for _, label in { "x", "pitch", "y", "yaw", "z", "roll" } do
		off.slider(viewmodel, label, -65, 65)
	end

	local entities = tab:CreateSubTab("entities")

	local projectiles = entities:CreateSection("projectiles")
	off.toggle(projectiles, "enabled")
	for _, label in { "bounding box", "name", "icon", "glow" } do
		off.toggle(projectiles, label, true)
	end
	local prediction = off.group(projectiles, "grenade prediction")
	off.toggle(prediction, "pin pulled")
	off.slider(prediction, "auto release", 0, 100)
	off.toggle(off.group(projectiles, "trajectory"), "proximity warning")
	for _, label in { "timers", "inferno spread", "smoke spread" } do
		off.toggle(projectiles, label, true)
	end

	local dropped = entities:CreateSection("dropped weapons")
	off.toggle(dropped, "enabled")
	for _, label in { "bounding box", "name", "icon" } do
		off.toggle(dropped, label, true)
	end
	off.toggle(dropped, "ammo")
	off.toggle(dropped, "glow", true)
	off.slider(dropped, "max distance", 100, 2000)

	local bomb = entities:CreateSection("bomb")
	off.toggle(bomb, "enabled")
	off.toggle(bomb, "screen info")
	off.multi(off.group(bomb, "world info"), "show", { "name", "timer", "distance" })
end

local function addMisc(window, movement, logs)
	local tab = window:CreateTab("misc", "settings")
	local general = tab:CreateSubTab("general")

	local main = general:CreateSection("main")
	local accept = off.group(main, "auto accept")
	off.toggle(accept, "notification")
	off.slider(accept, "delay", 0, 15, "%.2f seconds")
	for _, label in {
		"panorama extensions",
		"unlock inventory",
		"unlock spectators",
		"reveal ranks",
		"console filter",
		"engine radar",
		"preserve killfeed",
	} do
		off.toggle(main, label)
	end
	local hitsound = off.group(main, "hitsound")
	off.dropdown(hitsound, "sound", { "default" })
	off.slider(hitsound, "volume", 20, 125, "%.0f%%")
	-- the hub's own
	main:CreateButton("eject", hub.unload)

	local hud = general:CreateSection("hud")
	for _, label in { "watermark", "media player", "keybind list", "spectator list", "team damage list", "movement indicators" } do
		off.toggle(hud, label)
	end

	local others = general:CreateSection("others")
	for _, label in { "opposite hand knife", "instant hand switch", "fake 0ms", "automatic pistol" } do
		off.toggle(others, label)
	end
	-- the hub's own two in place of starline's hurt, harm, votes, edgebug and pixelsurf
	multi(others, "logs", logs, "kinds", { "hits", "misses" })
	off.multi(others, "log output", { "chat", "console", "screen" })
	off.group(others, "custom bomb code"):CreateTextBox("text (placeholder)", "", false, nothing):Disable()
	off.multi(off.group(others, "region changer"), "allowed regions")
	local lagger = off.group(others, "server lagger")
	off.slider(lagger, "frequency", 1, 20)
	off.slider(lagger, "strength", 10, 6000)

	local page = tab:CreateSubTab("movement")

	local card = page:CreateSection("movement")
	-- starline's auto jump is the hub's bunnyhop
	toggle(card, "auto jump", movement, "bunnyhop")
	off.toggle(off.group(card, "edge jump"), "long jump")
	off.toggle(card, "jump bug")
	off.toggle(card, "mini jump")
	off.toggle(off.group(card, "fireman"), "auto detach")
	off.toggle(off.group(card, "null binds"), "on ground")
	off.toggle(off.group(card, "auto strafe"), "subtick strafe")
	off.toggle(card, "slide walk")
	local surf = off.group(card, "pixel surf")
	off.toggle(surf, "advanced")
	off.slider(surf, "fov", 1, 90)
	off.dropdown(surf, "hitsound", { "off" })
	off.slider(surf, "volume", 20, 125, "%.0f%%")
	local edge = off.group(card, "edge bug assist")
	off.toggle(edge, "advanced")
	off.slider(edge, "sim ticks", 2, 64, "%.0f ticks")
	off.toggle(edge, "indicator", true)
	off.dropdown(edge, "hitsound", { "off" })
	off.slider(edge, "volume", 20, 125, "%.0f%%")
	off.toggle(card, "quick stop")
	off.toggle(card, "block bot")

	local graph = page:CreateSection("velocity graph")
	off.toggle(graph, "enabled", true)
	off.multi(graph, "log events", {
		"landing speed",
		"edgebug",
		"jumpbug",
		"long jump",
		"mini jump",
		"jump length",
		"pixelsurf",
	})
	off.slider(graph, "width", 200, 700)
	off.slider(graph, "height", 70, 260)
	off.slider(graph, "bg opacity", 0, 1, "%.2f")
end

-- starline's tabs, sub-tabs and cards in its order. features is what main.lua has behind them: its visuals, movement
-- and logs settings, setNight and setThirdPerson
return function(window, features)
	addAimbot(window)
	addPlayers(window)
	addVisuals(window, features)
	-- the dump has no cards for the inventory changer or the script list; their pages are kept so the tab row matches
	window:CreateTab("changer", "hanger"):CreateSubTab("inventory")
	addMisc(window, features.movement, features.logs)
	window:CreateTab("scripts", "code"):CreateSubTab("list")
end
