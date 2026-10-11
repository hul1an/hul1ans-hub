local hub = ...

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local esp = hub.require("core/esp.lua")
local aim = hub.require("core/aim.lua")
aim.settings.TeamCheck = true

-- third person's wall check needs a raycast that ignores the character, and Matcha documents no RaycastParams
local hasParams = RaycastParams ~= nil

local TEAM_COLORS = {
	Terrorists = Color3.fromRGB(204, 170, 80),
	["Counter-Terrorists"] = Color3.fromRGB(100, 149, 200),
}
local NIGHT = {
	ClockTime = 0,
	Brightness = 2,
	OutdoorAmbient = Color3.fromRGB(70, 70, 90),
	Ambient = Color3.fromRGB(60, 60, 70),
	GlobalShadows = true,
	ExposureCompensation = 0.5,
}

local visuals = {
	teamColors = false,
	thirdPersonDistance = 12,
}

-- Matcha documents no CFrame.lookAt: the same orientation, built from the direction with no roll
local function lookAt(eye, point)
	local direction = (point - eye).Unit
	return CFrame.new(eye.X, eye.Y, eye.Z)
		* CFrame.fromOrientation(math.asin(math.clamp(direction.Y, -1, 1)), math.atan2(-direction.X, -direction.Z), 0)
end

-- a player's character names its owner; a bot's has no owner and no Player object at all
local function ownerOf(character)
	local userId = tonumber(character:GetAttribute("PresentationOwnerUserId"))
	if not userId then
		return nil
	end
	-- GetPlayerByUserId isn't documented, so the owner is found by scanning the player list
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
end

-- a bot carries its side on the character, a player on the Player
local function teamOf(character)
	local team = character:GetAttribute("Team")
	if team then
		return team
	end
	local owner = ownerOf(character)
	return owner and owner:GetAttribute("Team")
end

-- the game moves characters it has culled out of workspace.Characters and leaves their last position on them,
-- so only models still in that folder are real; it has no Humanoids or Roblox teams, only attributes.
-- the folder is read directly because bots are in it but not in the Players list
local players = esp.sources[1]
local charactersWarned = false

players.models = function(skipTeammates)
	local characters = {}
	local folder = workspace:FindFirstChild("Characters")
	if not folder then
		if not charactersWarned then
			charactersWarned = true
			warn("[hub] workspace.Characters not found")
		end
		return characters
	end

	local team = skipTeammates and Players.LocalPlayer:GetAttribute("Team")
	local mine = Players.LocalPlayer.Character
	for _, character in folder:GetChildren() do
		if character ~= mine
			and character:FindFirstChild("HumanoidRootPart")
			and not character:GetAttribute("Dead")
			and not (team and teamOf(character) == team) then
			table.insert(characters, character)
		end
	end
	return characters
end

players.label = function(character)
	local owner = ownerOf(character)
	return owner and owner.Name or character.Name
end

players.health = function(character)
	return character:GetAttribute("Health"), character:GetAttribute("MaxHealth")
end

players.colorOf = function(character)
	return visuals.teamColors and TEAM_COLORS[teamOf(character)] or nil
end

local window = hub.ui.createWindow("BloxStrike")
local tabs = hub.require("universal.lua")(window)

-- the game's own lighting, held while night mode is on so it can be put back
local daylight

local function setNight(enabled)
	if enabled and not daylight then
		daylight = {}
		for property in NIGHT do
			daylight[property] = Lighting[property]
		end
	elseif not enabled and daylight then
		for property, value in daylight do
			Lighting[property] = value
		end
		daylight = nil
	end
end

hub.cleanup.add(function()
	setNight(false)
end)
-- reapplied every frame because the game sets its own lighting
hub.cleanup.add(RunService.RenderStepped:Connect(function()
	if daylight then
		for property, value in NIGHT do
			Lighting[property] = value
		end
	end
end))

-- third person shows the local character, hides the gun viewmodel held under the camera, and pulls the camera back
local thirdPerson = false
local thirdPersonLoop
local modifiers = {}
local cameraRay = hasParams and RaycastParams.new() or nil

local function setModifier(root, value)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			if modifiers[part] == nil then
				modifiers[part] = part.LocalTransparencyModifier
			end
			part.LocalTransparencyModifier = value
		end
	end
end

local function thirdPersonStep()
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end

	setModifier(character, 0)
	for _, child in camera:GetChildren() do
		if child:IsA("Model") then
			setModifier(child, 1)
		end
	end

	local focus = head.Position + Vector3.new(0, 1.5, 0)
	local look = camera.CFrame.LookVector
	cameraRay.FilterDescendantsInstances = { character, camera }
	local wall = workspace:Raycast(focus, -look * visuals.thirdPersonDistance, cameraRay)
	local position = wall and wall.Position + look * 0.5 or focus - look * visuals.thirdPersonDistance
	camera.CFrame = lookAt(position, focus)
end

local function setThirdPerson(enabled)
	if enabled == thirdPerson then
		return
	end
	thirdPerson = enabled
	if enabled then
		thirdPersonLoop = RunService.RenderStepped:Connect(thirdPersonStep)
	else
		if thirdPersonLoop then
			thirdPersonLoop:Disconnect()
			thirdPersonLoop = nil
		end
		for part, value in modifiers do
			part.LocalTransparencyModifier = value
		end
		table.clear(modifiers)
	end
end

hub.cleanup.add(function()
	setThirdPerson(false)
end)

-- anti-aim turns the local character's back to the nearest enemy and bends its neck and waist joints
local antiAim = {
	enabled = false,
	pitch = "Down",
	customPitch = 0,
	yaw = "AtTargets",
	spinSpeed = 15,
	disableOnFire = true,
}
local originals = {}
local antiAimCharacter
local spin = 0
local jointsWarned = false

local function joint(parent, name)
	local child = parent and parent:FindFirstChild(name)
	return child and child:IsA("JointInstance") and child or nil
end

local function setJoint(target, offset)
	if originals[target] == nil then
		originals[target] = target.C0
	end
	target.C0 = originals[target] * offset
end

local function restoreJoints()
	for target, c0 in originals do
		target.C0 = c0
	end
end

local function nearestEnemy(position)
	local nearest, best
	for _, character in players.models(true) do
		local root = character:FindFirstChild("HumanoidRootPart")
		local distance = root and (root.Position - position).Magnitude
		if distance and (not best or distance < best) then
			nearest, best = root, distance
		end
	end
	return nearest
end

local function antiAimStep()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if character ~= antiAimCharacter then
		antiAimCharacter = character
		table.clear(originals)
	end

	if antiAim.disableOnFire and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		restoreJoints()
		return
	end

	-- back to the enemy, or to where the camera looks when there is none
	local enemy = aim.target or nearestEnemy(root.Position)
	local away = enemy and root.Position - enemy.Position or -workspace.CurrentCamera.CFrame.LookVector
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude > 0.001 then
		root.CFrame = lookAt(root.Position, root.Position + away.Unit)
	end

	local pitch = math.rad(-89)
	if antiAim.pitch == "Up" then
		pitch = math.rad(89)
	elseif antiAim.pitch == "Jitter" then
		pitch = math.rad(math.random() > 0.5 and -89 or 89)
	elseif antiAim.pitch == "Custom" then
		pitch = math.rad(antiAim.customPitch)
	end

	local yaw = 0
	if antiAim.yaw == "Spinbot" then
		spin = (spin + antiAim.spinSpeed) % 360
		yaw = math.rad(spin)
	elseif antiAim.yaw == "Jitter" then
		yaw = math.rad(math.random() > 0.5 and 90 or -90)
	elseif antiAim.yaw == "Sideways" then
		yaw = math.rad(90)
	elseif antiAim.yaw == "Backwards" then
		yaw = math.pi
	end

	local head = character:FindFirstChild("Head")
	local upper = character:FindFirstChild("UpperTorso")
	local neck = joint(head, "Neck") or joint(upper, "Neck")
	local waist = joint(upper, "Waist") or joint(character:FindFirstChild("LowerTorso"), "Waist")
	local rootJoint = joint(root, "RootJoint")
	if not (neck or waist) and not jointsWarned then
		jointsWarned = true
		warn("[hub] anti-aim: no Neck or Waist joint on the character, only the root part is turned")
	end

	if neck then
		setJoint(neck, CFrame.Angles(pitch, yaw, 0))
	end
	if waist then
		setJoint(waist, CFrame.Angles(pitch * 0.4, 0, 0))
	end
	if rootJoint then
		setJoint(rootJoint, antiAim.yaw == "Spinbot" and CFrame.Angles(0, 0, yaw) or CFrame.identity)
	end
end

hub.cleanup.add(RunService.RenderStepped:Connect(function()
	if antiAim.enabled then
		antiAimStep()
	elseif next(originals) then
		restoreJoints()
		table.clear(originals)
	end
end))
hub.cleanup.add(restoreJoints)

local antiAimSection = tabs.combat:CreateSection("Anti-Aim", "RightSide")
antiAimSection:CreateToggle("Enabled", antiAim.enabled, function(value)
	antiAim.enabled = value
end)
antiAimSection:CreateDropdown("Pitch", { "Down", "Up", "Jitter", "Custom" }, function(value)
	antiAim.pitch = value
end, antiAim.pitch)
antiAimSection:CreateSlider("Custom Pitch", -89, 89, antiAim.customPitch, true, function(value)
	antiAim.customPitch = value
end)
antiAimSection:CreateDropdown("Yaw", { "AtTargets", "Backwards", "Spinbot", "Jitter", "Sideways", "Off" }, function(value)
	antiAim.yaw = value
end, antiAim.yaw)
antiAimSection:CreateSlider("Spin Speed", 1, 50, antiAim.spinSpeed, true, function(value)
	antiAim.spinSpeed = value
end)
antiAimSection:CreateToggle("Disable On Fire", antiAim.disableOnFire, function(value)
	antiAim.disableOnFire = value
end)

local espSection = tabs.esp:CreateSection("BloxStrike", "LeftSide")
espSection:CreateToggle("Team Colors", visuals.teamColors, function(value)
	visuals.teamColors = value
end)

local visualsTab = window:CreateTab("Visuals", "eye")
if hasParams then
	local cameraSection = visualsTab:CreateSection("Camera", "LeftSide")
	cameraSection:CreateToggle("Third Person", false, setThirdPerson):CreateKeybind("NONE")
	cameraSection:CreateSlider("Distance", 5, 30, visuals.thirdPersonDistance, true, function(value)
		visuals.thirdPersonDistance = value
	end)
end
visualsTab:CreateSection("World", "LeftSide"):CreateToggle("Night Mode", false, setNight)

window:CreateTab("Misc", "settings"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
