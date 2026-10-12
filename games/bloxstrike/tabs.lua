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
-- starline's colours for the name of a whitelisted player on the list and of a high priority one
local WHITELISTED = Color3.new(0, 1, 0)
local PRIORITY = Color3.new(1, 0, 0)
-- where the list's trigger reaction slider ends, in seconds, which is its default
local REACTION = 0.65

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

-- starline's player list: everyone in the match, and for the one picked the options the esp keeps under their id.
-- roster is main.lua's, the enemies and the teammates, or nothing outside a match
local function addList(tab, roster)
	-- the picked player's options
	local options = {}
	-- the card's toggles by the option each keeps, its two sliders, and every row with who it is for: "enemy", "other"
	-- (anyone but the user) or "own"
	local flags, rows = {}, {}
	local fov, reaction

	local card = tab:CreateSubTab("list"):CreatePlayerList(function()
		local enemies, teammates = roster()
		if not enemies then
			return nil
		end
		for _, players in { enemies, teammates } do
			for _, player in players do
				local set = esp.overrides[player.id]
				player.color = set and (set.whitelist and WHITELISTED or set.priority and PRIORITY) or nil
				player.image = player.userId and "rbxthumb://type=AvatarHeadShot&id=" .. player.userId .. "&w=48&h=48"
				-- starline's are the steamid and the premier rating, which the game has nothing like
				player.info = {
					{ "userid", player.userId and tostring(player.userId) or "bot" },
					{ "premier rating (placeholder)", "unranked" },
				}
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

	-- starline's row with nothing behind it
	local function dead(name, who)
		row(card:CreateButton(name .. " (placeholder)", nothing), who):Disable()
	end

	flag("whitelist", "whitelist", "enemy")
	flag("high priority", "priority", "enemy")
	flag("auto wall (aimbot)", "autoWall", "enemy")
	flag("auto wall (trigger)", "triggerAutoWall", "enemy")
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
	dead("steal name", "other")
	dead("reset name", "other")
	dead("reset name", "own")
	dead("vote kick yourself", "own")
end

local function addPlayers(window, roster)
	local tab = window:CreateTab("players", "users")
	addPlayerPage(tab, "enemies", esp.settings)
	addPlayerPage(tab, "teammates", esp.teammates.settings)
	addPlayerPage(tab, "local", esp.own.settings)
	addList(tab, roster)
end

local function addVisuals(window, features)
	local visuals = features.visuals
	-- view.lua's settings, behind the modulation and view cards, and entities.lua's
	local options = features.view.settings
	local things = features.entities.settings
	local tab = window:CreateTab("visuals", "eye")
	local world = tab:CreateSubTab("world")

	local general = world:CreateSection("general")
	-- the skies of the game's own maps; the dump has no list
	dropdown(general, "skybox", visuals, "sky", features.skies)
	local rain = group(general, "precipitation", visuals, "precipitation")
	multi(rain, "types", visuals, "weather", { "rain", "snow", "leaves", "ashes", "embers" })
	toggle(rain, "outdoors only", visuals, "outdoors")
	slider(rain, "particles", visuals, "particles", 24, 1024, true)
	local fog = group(general, "fog", visuals, "fog")
	slider(fog, "density", visuals, "fogDensity", 0, 100, true, "%.0f%%")
	slider(fog, "start", visuals, "fogStart", 0, 8000, true)
	slider(fog, "end", visuals, "fogEnd", 0, 8000, true)
	-- the hub's own
	general:CreateToggle("night mode", false, features.setNight)

	-- a row's setting is its name with a capital, and its colour that with Color on the end
	local function tinted(card, label, settings, key)
		color(toggle(card, label, settings, key), settings, key .. "Color")
	end

	local modulation = world:CreateSection("modulation")
	tinted(modulation, "world", options, "World")
	tinted(modulation, "sun", options, "Sun")
	tinted(modulation, "light", options, "Light")
	-- a Roblox sky has no colour to set
	off.toggle(modulation, "sky", true)
	tinted(modulation, "molotov", options, "Molotov")
	tinted(modulation, "smoke", options, "Smoke")
	tinted(modulation, "ambience", options, "Ambience")

	local effects = world:CreateSection("effects")
	multi(effects, "hit markers", visuals, "hitMarkers", { "world", "screen" })
	color(toggle(effects, "damage marker", visuals, "damageMarker"), visuals, "damageColor")
	local bloom = group(effects, "bloom", visuals, "bloom")
	slider(bloom, "bloom scale", visuals, "bloomScale", 0, 100, true)
	slider(bloom, "threshold", visuals, "bloomThreshold", 0, 2, false, "%.2f")
	-- Roblox's bloom has no knee
	off.slider(bloom, "threshold knee", 0, 1, "%.2f")
	slider(bloom, "blur strength", visuals, "bloomBlur", 0, 100, true)
	slider(group(effects, "motion blur", visuals, "motionBlur"), "amount", visuals, "motionBlurAmount", 0, 1, false, "%.2f")
	local kill = group(effects, "kill effects", visuals, "killEffects")
	multi(kill, "effects", visuals, "killKinds", { "explosion", "taser", "lightning", "sparks", "dissolve", "shockwave" })
	toggle(kill, "screen shake", visuals, "killShake")
	slider(kill, "shake strength", visuals, "killShakeStrength", 2, 40, true)
	-- starline has no colour on this row; the hub's tracers have one
	local tracers = group(effects, "bullet tracers", visuals, "tracers")
	color(tracers.header, visuals, "tracerColor")
	slider(tracers, "size", visuals, "tracerSize", 0.05, 1, false)
	slider(tracers, "time", visuals, "tracerDuration", 0.05, 2, false)
	slider(group(effects, "impact sparks", visuals, "sparks"), "particles", visuals, "sparkCount", 16, 64, true)
	-- the hub's own
	toggle(effects, "hit effect", visuals, "hitEffect")

	local view = world:CreateSection("view")
	local zoom = group(view, "override fov", options, "Fov")
	slider(zoom, "field of view", options, "FovValue", 60, 120, true)
	slider(zoom, "zoom x1", options, "Zoom1", 0, 100, true, "%.0f%%")
	slider(zoom, "zoom x2", options, "Zoom2", 0, 100, true, "%.0f%%")
	slider(view, "aspect ratio", options, "AspectRatio", 0, 2, false, "%.2f")
	local third = view:CreateGroup("third person", false, features.setThirdPerson)
	third.header:CreateKeybind("NONE")
	off.toggle(third, "animation")
	-- in studs; starline's runs 50 to 160 of CS2's units
	slider(third, "distance", visuals, "thirdPersonDistance", 5, 30, true)
	local alpha = group(view, "scoped transparency", options, "ScopedAlpha")
	slider(alpha, "alpha", options, "ScopedAlphaValue", 0, 100, true, "%.0f%%")
	-- the dump's fold has no box of its own; the hub's has one, to switch it by
	local scope = group(view, "scope overlay", options, "Scope")
	color(scope.header, options, "ScopeColor")
	toggle(scope, "show viewmodel", options, "ScopeViewmodel")
	slider(scope, "length", options, "ScopeLength", 5, 100, true, "%.0f%%")
	toggle(scope, "dynamic gap", options, "ScopeDynamic")
	slider(scope, "gap", options, "ScopeGap", 0, 100, true)
	-- the placeholders are things the game doesn't have to take away
	multi(view, "visual removals", options, "Removals", {
		"3d skybox (placeholder)",
		"2d skybox",
		"shadows",
		"lights",
		"smoke",
		"torso (placeholder)",
		"flash",
		"overhead name (placeholder)",
		"overhead name team (placeholder)",
		"ragdoll",
		"post process",
		"fog",
		"viewmodel bob",
		"bullet decals (placeholder)",
	})
	toggle(group(view, "force crosshair", options, "Crosshair"), "while scoped", options, "CrosshairScoped")
	local viewmodel = group(view, "viewmodel changer", options, "Viewmodel")
	-- Roblox draws everything with the camera's one field of view
	off.slider(viewmodel, "fov", 50, 120, "%.1f")
	for _, label in { "x", "pitch", "y", "yaw", "z", "roll" } do
		slider(viewmodel, label, options, "Viewmodel" .. label:gsub("^%l", string.upper), -65, 65, true)
	end

	local entities = tab:CreateSubTab("entities")

	local projectiles = entities:CreateSection("projectiles")
	toggle(projectiles, "enabled", things, "Projectiles")
	tinted(projectiles, "bounding box", things, "ProjectileBox")
	tinted(projectiles, "name", things, "ProjectileName")
	tinted(projectiles, "icon", things, "ProjectileIcon")
	tinted(projectiles, "glow", things, "ProjectileGlow")
	local prediction = group(projectiles, "grenade prediction", things, "Prediction")
	toggle(prediction, "pin pulled", things, "PredictionPin")
	off.slider(prediction, "auto release", 0, 100)
	toggle(group(projectiles, "trajectory", things, "Trajectory"), "proximity warning", things, "TrajectoryWarning")
	tinted(projectiles, "timers", things, "Timers")
	tinted(projectiles, "inferno spread", things, "Inferno")
	tinted(projectiles, "smoke spread", things, "Smoke")

	local dropped = entities:CreateSection("dropped weapons")
	toggle(dropped, "enabled", things, "Dropped")
	tinted(dropped, "bounding box", things, "DroppedBox")
	tinted(dropped, "name", things, "DroppedName")
	tinted(dropped, "icon", things, "DroppedIcon")
	-- the game doesn't tell the client how many rounds a weapon on the ground has
	off.toggle(dropped, "ammo")
	tinted(dropped, "glow", things, "DroppedGlow")
	slider(dropped, "max distance", things, "DroppedDistance", 100, 2000, true)

	local bomb = entities:CreateSection("bomb")
	toggle(bomb, "enabled", things, "Bomb")
	toggle(bomb, "screen info", things, "BombScreen")
	multi(group(bomb, "world info", things, "BombWorld"), "show", things, "BombShow", { "name", "timer", "distance" })
end

local function addMisc(window, features)
	local misc, hud, movement, logs = features.misc.settings, features.hud, features.movement, features.logs
	local tab = window:CreateTab("misc", "settings")
	local general = tab:CreateSubTab("general")

	-- every starline row of this page the hub has nothing for was taken out at the user's request: auto accept,
	-- panorama extensions, unlock inventory, unlock spectators, reveal ranks, console filter, media player, team damage
	-- list, opposite hand knife, instant hand switch, fake 0ms, region changer and server lagger
	local main = general:CreateSection("main")
	toggle(main, "engine radar", misc, "radar")
	toggle(main, "preserve killfeed", misc, "killfeed")
	local hitsound = group(main, "hitsound", misc, "hitsound")
	dropdown(hitsound, "sound", misc, "hitsoundName", features.misc.sounds)
	slider(hitsound, "volume", misc, "hitsoundVolume", 20, 125, true, "%.0f%%")
	-- the hub's own
	main:CreateButton("eject", hub.unload)

	local overlays = general:CreateSection("hud")
	-- starline keeps the watermark's parts on the widget itself
	multi(group(overlays, "watermark", hud, "watermark"), "show", hud, "watermarkShow", {
		"username",
		"time",
		"ping",
		"k/d",
		"fps",
		"hs%",
	})
	toggle(overlays, "keybind list", hud, "keybinds")
	toggle(overlays, "spectator list", hud, "spectators")
	toggle(overlays, "movement indicators", hud, "indicators")

	local others = general:CreateSection("others")
	toggle(others, "automatic pistol", misc, "pistol")
	-- the hub's own two in place of starline's hurt, harm, votes, edgebug and pixelsurf
	multi(others, "logs", logs, "kinds", { "hits", "misses" })
	multi(others, "log output", misc, "output", { "chat", "console", "screen" })
	group(others, "custom bomb code", misc, "bombCode"):CreateTextBox("text", "7355608", false, function(value)
		misc.bombText = value
	end)

	local page = tab:CreateSubTab("movement")

	local card = page:CreateSection("movement")
	-- starline's auto jump is the hub's bunnyhop
	toggle(card, "auto jump", movement, "bunnyhop")
	toggle(group(card, "edge jump", movement, "edgeJump"), "long jump", movement, "longJump")
	-- starline's jump bug, mini jump, fireman, subtick strafe, slide walk, pixel surf and edge bug assist were taken out
	-- at the user's request: tricks of CS2's own movement code, which the game's simulation has none of
	toggle(group(card, "null binds", movement, "nullBinds"), "on ground", movement, "nullGround")
	toggle(card, "auto strafe", movement, "autoStrafe")
	toggle(card, "quick stop", movement, "quickStop")
	toggle(card, "block bot", movement, "blockBot")

	local graph = page:CreateSection("velocity graph")
	color(toggle(graph, "enabled", hud, "graph"), hud, "graphColor", "graphOpacity")
	-- the three of starline's seven that the hub's movement has
	multi(graph, "log events", hud, "graphEvents", { "landing speed", "long jump", "jump length" })
	slider(graph, "width", hud, "graphWidth", 200, 700, true)
	slider(graph, "height", hud, "graphHeight", 70, 260, true)
	slider(graph, "bg opacity", hud, "graphBack", 0, 1, false)
end

-- starline's tabs, sub-tabs and cards in its order. features is what main.lua has behind them: its visuals and logs
-- settings, the movement page's and the hud's, misc.lua, the roster, the skybox choices, view.lua and entities.lua,
-- setNight and setThirdPerson
return function(window, features)
	addAimbot(window)
	addPlayers(window, features.roster)
	addVisuals(window, features)
	-- the dump has no cards for the inventory changer; its page is kept so the tab row matches. starline's scripts tab,
	-- as empty, was taken out at the user's request
	window:CreateTab("changer", "hanger"):CreateSubTab("inventory")
	addMisc(window, features)
end
