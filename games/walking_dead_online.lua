local hub = ...

local window = hub.ui.createWindow("The Walking Dead Online")

local function placeholder(name)
	window.button(name, function()
		window.notify(name .. " (placeholder)")
	end)
end

window.section("Combat")
placeholder("Aim Assist")
placeholder("Kill Aura")

window.section("Visuals")
placeholder("Zombie ESP")
placeholder("Player ESP")

window.section("Player")
placeholder("Speed")
placeholder("Infinite Stamina")

window.section("Misc")
placeholder("Teleport")
placeholder("Auto Loot")
