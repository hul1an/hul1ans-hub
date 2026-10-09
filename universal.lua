local hub = ...

local esp = hub.require("core/esp.lua")
esp.start()

local settings = esp.settings

return function(window)
	local tab = window:CreateTab("ESP")

	local general = tab:CreateSection("ESP")
	general:CreateToggle("Enabled", settings.Enabled, function(value)
		settings.Enabled = value
	end)
	general:CreateSlider("Max Distance", 0, 3000, settings.MaxDistance, true, function(value)
		settings.MaxDistance = value
	end)

	local targets = tab:CreateSection("Targets")
	for _, source in esp.sources do
		targets:CreateToggle(source.name, source.enabled, function(value)
			source.enabled = value
		end)
	end

	local options = tab:CreateSection("Options")
	local function toggle(name, key)
		options:CreateToggle(name, settings[key], function(value)
			settings[key] = value
		end)
	end
	toggle("Box", "Box")
	toggle("Tracers", "Tracers")
	toggle("Health Bar", "HealthBar")
	toggle("Name", "Name")
	toggle("Distance", "Distance")
end
