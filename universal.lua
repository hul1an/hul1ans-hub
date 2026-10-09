local hub = ...

local esp = hub.require("core/esp.lua")
esp.start()

local settings = esp.settings

return function(window)
	local tab = window:CreateTab("ESP")

	local function toggle(section, name, key)
		section:CreateToggle(name, settings[key], function(value)
			settings[key] = value
		end)
	end

	local general = tab:CreateSection("ESP")
	toggle(general, "Enabled", "Enabled")
	general:CreateSlider("Max Distance", 0, 3000, settings.MaxDistance, true, function(value)
		settings.MaxDistance = value
	end)

	local options = tab:CreateSection("Options")
	toggle(options, "Box", "Box")
	toggle(options, "Tracers", "Tracers")
	toggle(options, "Health Bar", "HealthBar")
	toggle(options, "Name", "Name")
	toggle(options, "Distance", "Distance")
end
