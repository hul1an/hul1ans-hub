local hub = ...

local window = hub.bracket.createWindow("The Walking Dead Online")

-- Bracket fires every callback once while the controls are built
local ready = false

local function placeholder(name)
	return function(value)
		if ready then
			print("[hub] " .. name .. " (placeholder)", value)
		end
	end
end

local combat = window:CreateTab("Combat")
local aim = combat:CreateSection("Aim")
local aimAssist = aim:CreateToggle("Aim Assist", false, placeholder("Aim Assist"))
aimAssist:CreateKeybind("NONE")
aim:CreateSlider("FOV", 0, 360, 90, true, placeholder("FOV"))
aim:CreateDropdown("Target Part", { "Head", "Torso" }, placeholder("Target Part"), "Head")
combat:CreateSection("Melee"):CreateToggle("Kill Aura", false, placeholder("Kill Aura"))

local visuals = window:CreateTab("Visuals")
visuals:CreateSection("ESP"):CreateColorpicker("ESP Color", placeholder("ESP Color"))

local warned = false
hub.require("core/esp.lua").addSource("Zombies", function()
	local ai = workspace:FindFirstChild("AI")
	local walkers = ai and ai:FindFirstChild("Walkers")
	if not walkers then
		if not warned then
			warned = true
			warn("[hub] workspace.AI.Walkers not found, zombie ESP skipped")
		end
		return {}
	end
	return walkers:GetChildren()
end, function(model)
	return model.Name
end)

hub.require("universal.lua")(window)

local player = window:CreateTab("Player")
local movement = player:CreateSection("Movement")
movement:CreateSlider("Speed", 16, 100, 16, true, placeholder("Speed"))
movement:CreateToggle("Infinite Stamina", false, placeholder("Infinite Stamina"))

local misc = window:CreateTab("Misc")
local utility = misc:CreateSection("Utility")
utility:CreateButton("Teleport", placeholder("Teleport"))
utility:CreateToggle("Auto Loot", false, placeholder("Auto Loot"))
misc:CreateSection("Hub"):CreateButton("Eject", hub.unload)

ready = true
