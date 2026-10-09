local hub = ...

local esp = hub.require("core/esp.lua")
esp.start()

local settings = esp.settings

return function(window)
	local tab = window:CreateTab("ESP")

	tab:CreateSection("ESP"):CreateToggle("Enabled", settings.Enabled, function(value)
		settings.Enabled = value
	end)

	for _, source in esp.sources do
		local section = tab:CreateSection(source.name)
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

	local options = tab:CreateSection("Options")
	local function toggle(name, key)
		options:CreateToggle(name, settings[key], function(value)
			settings[key] = value
		end)
	end
	toggle("Box", "Box")
	toggle("Health Bar", "HealthBar")
	toggle("Name", "Name")
	toggle("Distance", "Distance")
end
