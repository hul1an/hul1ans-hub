local hub = ...

local esp = hub.require("core/esp.lua")
local aim = hub.require("core/aim.lua")
esp.start()
aim.start()

local function addCombat(window)
	local settings = aim.settings
	local tab = window:CreateTab("Combat", "crosshairs")

	local function toggle(section, name, key)
		return section:CreateToggle(name, settings[key], function(value)
			settings[key] = value
		end)
	end

	local section = tab:CreateSection("Aim Assist", "LeftSide")
	toggle(section, "Enabled", "Enabled"):CreateKeybind("NONE")
	section:CreateLabel("Hold right mouse to aim")
	section:CreateDropdown("Aim Mode", { "Distance", "Crosshair", "Health" }, function(value)
		settings.Mode = value
	end, settings.Mode)
	section:CreateDropdown("Target Part", { "Head", "Torso" }, function(value)
		settings.TargetPart = value
	end, settings.TargetPart)
	section:CreateSlider("Max Distance", 0, 3000, settings.MaxDistance, true, function(value)
		settings.MaxDistance = value
	end)
	section:CreateSlider("FOV Radius", 0, 500, settings.Fov, true, function(value)
		settings.Fov = value
	end)

	local options = tab:CreateSection("Options", "RightSide")
	toggle(options, "Team Check", "TeamCheck")
	toggle(options, "Visibility Check", "VisibilityCheck")
	toggle(options, "Draw FOV", "DrawFov")
	toggle(options, "Target Color", "TargetColor")
	toggle(options, "Auto Fire", "AutoFire")
	-- players are always targeted, the other sources are opt-in
	for index = 2, #esp.sources do
		local source = esp.sources[index]
		options:CreateToggle("Target " .. source.name, source.aim, function(value)
			source.aim = value
		end)
	end

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
		-- a new picker shows black until it is given a colour
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
	toggle("Chams", "Chams")
	toggle("Health Bar", "HealthBar")
	toggle("Name", "Name")
	toggle("Distance", "Distance")

	return tab
end

-- returns the tabs so a game file can add its own sections to them
return function(window)
	return { combat = addCombat(window), esp = addEsp(window) }
end
