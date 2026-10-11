local hub = ...

local esp = hub.require("core/esp.lua")
local aim = hub.require("core/aim.lua")
esp.start()
aim.start()

local HITGROUPS = { "Head", "Chest", "Stomach", "Pelvis", "Arms", "Legs", "Feet" }

-- starline's aimbot tab card for card, minus the placeholders that need game code the hub doesn't have
local function addCombat(window)
	local settings = aim.settings
	local tab = window:CreateTab("Combat", "crosshairs")

	local function toggle(section, name, key)
		return section:CreateToggle(name, settings[key], function(value)
			settings[key] = value
		end)
	end
	local function group(section, name, key)
		return section:CreateGroup(name, settings[key], function(value)
			settings[key] = value
		end)
	end
	local function slider(section, name, key, min, max, precise, format)
		section:CreateSlider(name, min, max, settings[key], precise, function(value)
			settings[key] = value
		end, format)
	end

	local general = tab:CreateSection("General", "LeftSide")
	toggle(general, "Enabled", "Enabled"):CreateKeybind("NONE")
	-- only a game file with a shot hook has this, and nothing on Matcha can hook, so it stays unset
	if settings.SilentAim ~= nil then
		toggle(general, "Silent Aim", "SilentAim")
	end
	toggle(general, "Draw FOV", "DrawFov")
	general:CreateColorpicker("FOV Color", function(color)
		settings.FovColor = color
	end):UpdateColor(settings.FovColor)
	general:CreateMultiDropdown("Disablers", { "Jump" }, function(value)
		settings.Disablers = value
	end, settings.Disablers)

	local targeting = tab:CreateSection("Targeting", "LeftSide")
	targeting:CreateDropdown("Target Selection", { "Crosshair", "Health", "Distance" }, function(value)
		settings.Selection = value
	end, settings.Selection)
	targeting:CreateDropdown("FOV Mode", { "Static", "Dynamic" }, function(value)
		settings.FovMode = value
	end, settings.FovMode)
	slider(targeting, "Max FOV", "Fov", 0, 30, false)
	targeting:CreateMultiDropdown("Hitgroups", HITGROUPS, function(value)
		settings.Hitgroups = value
	end, settings.Hitgroups)
	slider(group(targeting, "Multipoint", "Multipoint"), "Scale", "MultipointScale", 0, 100, true, "%.0f%%")

	local behavior = tab:CreateSection("Behavior", "LeftSide")
	local smoothing = group(behavior, "Smoothing", "Smoothing")
	slider(smoothing, "Value", "SmoothingValue", 5, 50, false, "%.1f")
	slider(smoothing, "Humanization", "Humanization", 0, 100, true, "%.0f%%")
	slider(smoothing, "Sticky", "Sticky", 0, 100, true, "%.0f%%")
	slider(behavior, "Switch Delay", "SwitchDelay", 0, 500, true, "%.0fms")
	slider(behavior, "Mouse Override", "MouseOverride", 0, 100, true, "%.0f%%")

	-- Force Baim is the only Accuracy card feature that needs no game hook
	local accuracy = tab:CreateSection("Accuracy", "LeftSide")
	toggle(accuracy, "Force Baim", "ForceBaim")

	local options = tab:CreateSection("Options", "RightSide")
	toggle(options, "Team Check", "TeamCheck")
	toggle(options, "Visibility Check", "VisibilityCheck")
	slider(options, "Max Distance", "MaxDistance", 0, 3000, true)
	toggle(options, "Target Color", "TargetColor")
	-- players are always targeted, the other sources are opt-in
	for index = 2, #esp.sources do
		local source = esp.sources[index]
		options:CreateToggle("Target " .. source.name, source.aim, function(value)
			source.aim = value
		end)
	end

	local trigger = tab:CreateSection("Triggerbot", "RightSide")
	toggle(trigger, "Enabled", "Trigger")
	trigger:CreateMultiDropdown("Hitgroups", HITGROUPS, function(value)
		settings.TriggerHitgroups = value
	end, settings.TriggerHitgroups)
	slider(trigger, "Delay", "TriggerDelay", 0, 250, true, "%.0fms")
	slider(trigger, "Visible Delay", "TriggerVisibleDelay", 0, 650, true, "%.0fms")
	slider(trigger, "Burst", "TriggerBurst", 0, 250, true, "%.0fms")
	toggle(trigger, "Randomize", "TriggerRandomize")

	return tab
end

local function addEsp(window)
	local settings = esp.settings
	local tab = window:CreateTab("ESP", "users")

	tab:CreateSection("ESP", "LeftSide"):CreateToggle("Enabled", settings.Enabled, function(value)
		settings.Enabled = value
	end)

	for _, source in esp.sources do
		local section = tab:CreateSection(source.name, "RightSide")
		section:CreateToggle("Show " .. source.name, source.enabled, function(value)
			source.enabled = value
		end)
		section:CreateColorpicker("Color", function(color)
			source.color = color
		end):UpdateColor(source.color)
		section:CreateSlider("Max Distance", 0, 3000, source.maxDistance, true, function(value)
			source.maxDistance = value
		end)
		section:CreateToggle("Tracers", source.tracers, function(value)
			source.tracers = value
		end)
	end

	local options = tab:CreateSection("Options", "LeftSide")
	local function toggle(name, key)
		options:CreateToggle(name, settings[key], function(value)
			settings[key] = value
		end)
	end
	toggle("Team Check", "TeamCheck")
	toggle("Box", "Box")
	toggle("Skeleton", "Skeleton")
	toggle("Health Bar", "HealthBar")
	toggle("Name", "Name")
	toggle("Distance", "Distance")

	return tab
end

-- returns the tabs so a game file can add its own sections to them
return function(window)
	return { combat = addCombat(window), esp = addEsp(window) }
end
