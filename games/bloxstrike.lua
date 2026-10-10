local hub = ...

local Players = cloneref(game:GetService("Players"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Lighting = cloneref(game:GetService("Lighting"))
local TweenService = cloneref(game:GetService("TweenService"))
local Debris = cloneref(game:GetService("Debris"))

local esp = hub.require("core/esp.lua")
local aim = hub.require("core/aim.lua")
aim.settings.TeamCheck = true

local THIRD_PERSON_STEP = "HubThirdPerson"
-- where the game parks the characters it has culled, under ReplicatedStorage
local CULLED_FOLDER = "_PVS_CulledCharacters"
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

local silent = { enabled = false }
local visuals = {
	teamColors = false,
	thirdPersonDistance = 12,
	tracers = false,
	tracerColor = Color3.fromRGB(255, 41, 116),
	tracerDuration = 1.2,
	hitEffect = false,
}

-- a player's character names its owner; a bot's has no owner and no Player object at all
local function ownerOf(character)
	local userId = tonumber(character:GetAttribute("PresentationOwnerUserId"))
	return userId and Players:GetPlayerByUserId(userId)
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
	return owner and owner.DisplayName or character.Name
end

players.health = function(character)
	return character:GetAttribute("Health"), character:GetAttribute("MaxHealth")
end

players.colorOf = function(character)
	return visuals.teamColors and TEAM_COLORS[teamOf(character)] or nil
end

local window = hub.ui.createWindow("BloxStrike")
local tabs = hub.require("universal.lua")(window)

-- tracers and hit effects live under the camera, where the aim assist's visibility ray ignores them
local effects = hub.cleanup.add(Instance.new("Folder"))
effects.Parent = workspace.CurrentCamera

local function effectPart()
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	return part
end

local function fade(part, seconds, goal)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, seconds)
end

local function tracer(from, to)
	local length = (to - from).Magnitude
	if length < 0.2 then
		return
	end
	local part = effectPart()
	part.Color = visuals.tracerColor
	part.Transparency = 0.15
	part.Size = Vector3.new(0.08, 0.08, length)
	part.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	part.Parent = effects
	fade(part, visuals.tracerDuration, { Transparency = 1 })
end

local function hitEffect(position)
	local part = effectPart()
	part.Shape = Enum.PartType.Ball
	part.Color = Color3.fromRGB(255, 120, 30)
	part.Transparency = 0.2
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.CFrame = CFrame.new(position)
	part.Parent = effects
	fade(part, 0.4, { Size = Vector3.new(7, 7, 7), Transparency = 1 })
end

-- rewrites a finished bullet raycast so its last hit is the target; returns whether it did
local function redirect(result, target)
	local hits = rawget(result, "Hits")
	if type(hits) ~= "table" then
		return false
	end

	local last
	for index, hit in hits do
		if type(hit) == "table" and (not last or index > last) then
			last = index
		end
	end
	if not last then
		return false
	end

	local position = target.Position
	local final = hits[last]
	final.Instance = target
	final.Position = position
	if final.Exit ~= nil then
		final.Exit = false
	end

	local origin = rawget(result, "Origin") or workspace.CurrentCamera.CFrame.Position
	if typeof(origin) ~= "Vector3" then
		return true
	end
	local delta = position - origin
	local length = delta.Magnitude
	if length < 0.001 then
		return true
	end
	result.Distance = length
	result.Direction = delta.Unit

	-- earlier hits that lie past the target are pulled back in front of it
	for index, hit in hits do
		if index ~= last and type(hit) == "table" and typeof(hit.Position) == "Vector3" then
			if (hit.Position - origin):Dot(delta.Unit) > length then
				hit.Position = origin + delta.Unit * (length * 0.5)
			end
		end
	end
	return true
end

-- where a shot ended: the redirected target, else its last hit, else the end of its ray
local function shotEnd(result, origin, target)
	if target then
		return target.Position
	end
	local hits = rawget(result, "Hits")
	local last = type(hits) == "table" and hits[#hits]
	if type(last) == "table" and typeof(last.Position) == "Vector3" then
		return last.Position
	end
	local direction = rawget(result, "Direction")
	if typeof(direction) == "Vector3" then
		return origin + direction * (rawget(result, "Distance") or 500)
	end
	return nil
end

local function onShot(result)
	local target = silent.enabled and aim.target
	if not (target and target.Parent and redirect(result, target)) then
		target = nil
	end

	if visuals.tracers or visuals.hitEffect then
		local origin = rawget(result, "Origin") or workspace.CurrentCamera.CFrame.Position
		local finish = typeof(origin) == "Vector3" and shotEnd(result, origin, target)
		if finish then
			if visuals.tracers then
				tracer(origin, finish)
			end
			if visuals.hitEffect then
				hitEffect(finish)
			end
		end
	end
end

local unloaded = false
hub.cleanup.add(function()
	unloaded = true
end)

-- the game's bullet class is only reachable through the garbage collector, and may not exist until a gun is out
task.spawn(function()
	local bullets
	for _ = 1, 45 do
		if unloaded then
			return
		end
		for _, object in getgc(true) do
			if type(object) == "table"
				and type(rawget(object, "_performRaycast")) == "function"
				and rawget(object, "getTrueSpread") ~= nil then
				bullets = object
				break
			end
		end
		if bullets then
			break
		end
		task.wait(0.5)
	end
	if not bullets then
		warn("[hub] BloxStrike bullet class (_performRaycast) not found: silent aim, tracers and hit effect unavailable")
		return
	end

	local shotWarned = false
	local original
	original = hookfunction(bullets._performRaycast, function(...)
		local returns = table.pack(original(...))
		if type(returns[1]) == "table" then
			-- an error here would otherwise break the game's own shooting
			local ok, err = pcall(onShot, returns[1])
			if not ok and not shotWarned then
				shotWarned = true
				warn("[hub] shot hook failed: " .. tostring(err))
			end
		end
		return table.unpack(returns, 1, returns.n)
	end)

	hub.cleanup.add(function()
		hookfunction(bullets._performRaycast, original)
	end)
end)

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
local modifiers = {}
local cameraRay = RaycastParams.new()
cameraRay.FilterType = Enum.RaycastFilterType.Exclude

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
	camera.CFrame = CFrame.lookAt(position, focus)
end

local function setThirdPerson(enabled)
	if enabled == thirdPerson then
		return
	end
	thirdPerson = enabled
	if enabled then
		-- after the aim assist's step, which is one after the camera's
		RunService:BindToRenderStep(THIRD_PERSON_STEP, Enum.RenderPriority.Camera.Value + 2, thirdPersonStep)
	else
		RunService:UnbindFromRenderStep(THIRD_PERSON_STEP)
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

	local firing = aim.settings.AutoFire and aim.target ~= nil
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	if antiAim.disableOnFire and firing then
		restoreJoints()
		return
	end

	-- back to the enemy, or to where the camera looks when there is none
	local enemy = aim.target or nearestEnemy(root.Position)
	local away = enemy and root.Position - enemy.Position or -workspace.CurrentCamera.CFrame.LookVector
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude > 0.001 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + away.Unit)
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

-- dormant esp: a culled enemy that is still alive gets a box at the position left on its character, fading out
local dormant = { enabled = false, fadeTime = 10 }
local culledSince = {}
local dormantBoxes = {}

local function dormantStep()
	local camera = workspace.CurrentCamera
	local now = os.clock()
	local drawing = dormant.enabled and esp.settings.Enabled and players.enabled
	local team = Players.LocalPlayer:GetAttribute("Team")
	local folder = ReplicatedStorage:FindFirstChild(CULLED_FOLDER)
	local shown = {}

	-- the culled folder is read directly so that bots are included
	for _, character in folder and folder:GetChildren() or {} do
		local root = character:FindFirstChild("HumanoidRootPart")
		local theirTeam = teamOf(character)
		if root and theirTeam and theirTeam ~= team and not character:GetAttribute("Dead") then
			-- timed even while the option is off, so switching it on doesn't show old positions as fresh
			culledSince[character] = culledSince[character] or now
			local opacity = 1 - (now - culledSince[character]) / dormant.fadeTime
			local center = root.Position
			local top = camera:WorldToViewportPoint(center + Vector3.new(0, root.Size.Y * 1.25, 0))
			local bottom = camera:WorldToViewportPoint(center - Vector3.new(0, root.Size.Y * 1.5, 0))
			if drawing
				and opacity > 0
				and top.Z > 0
				and bottom.Z > 0
				and (camera.CFrame.Position - center).Magnitude <= players.maxDistance then
				local boxes = dormantBoxes[character]
				if not boxes then
					boxes = { outline = Drawing.new("Square"), box = Drawing.new("Square") }
					boxes.outline.Thickness = 3
					boxes.outline.Color = Color3.new(0, 0, 0)
					boxes.box.Thickness = 1
					dormantBoxes[character] = boxes
				end

				local height = math.abs(bottom.Y - top.Y)
				local width = height / 2
				local position = Vector2.new(top.X - width / 2, math.min(top.Y, bottom.Y))
				for _, square in boxes do
					square.Visible = true
					square.Transparency = opacity
					square.Position = position
					square.Size = Vector2.new(width, height)
				end
				boxes.box.Color = visuals.teamColors and TEAM_COLORS[theirTeam] or players.color
				shown[character] = true
			end
		end
	end

	-- a character that is back in the world, dead or gone stops being timed
	for character in culledSince do
		if character.Parent ~= folder or character:GetAttribute("Dead") then
			culledSince[character] = nil
		end
	end
	for character, boxes in dormantBoxes do
		if not shown[character] then
			if character.Parent then
				boxes.outline.Visible = false
				boxes.box.Visible = false
			else
				boxes.outline:Remove()
				boxes.box:Remove()
				dormantBoxes[character] = nil
			end
		end
	end
end

hub.cleanup.add(function()
	for _, boxes in dormantBoxes do
		boxes.outline:Remove()
		boxes.box:Remove()
	end
	table.clear(dormantBoxes)
end)
hub.cleanup.add(RunService.RenderStepped:Connect(dormantStep))

local silentSection = tabs.combat:CreateSection("Silent Aim", "RightSide")
silentSection:CreateToggle("Enabled", silent.enabled, function(value)
	silent.enabled = value
end)
silentSection:CreateLabel("Uses the aim assist target")

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
espSection:CreateToggle("Dormant ESP", dormant.enabled, function(value)
	dormant.enabled = value
end)
espSection:CreateSlider("Dormant Fade Time", 1, 30, dormant.fadeTime, true, function(value)
	dormant.fadeTime = value
end)

local visualsTab = window:CreateTab("Visuals", "eye")

local cameraSection = visualsTab:CreateSection("Camera", "LeftSide")
cameraSection:CreateToggle("Third Person", false, setThirdPerson):CreateKeybind("NONE")
cameraSection:CreateSlider("Distance", 5, 30, visuals.thirdPersonDistance, true, function(value)
	visuals.thirdPersonDistance = value
end)

visualsTab:CreateSection("World", "LeftSide"):CreateToggle("Night Mode", false, setNight)

local shots = visualsTab:CreateSection("Shots", "RightSide")
shots:CreateToggle("Bullet Tracers", visuals.tracers, function(value)
	visuals.tracers = value
end)
-- a new picker shows black until it is given a colour
shots:CreateColorpicker("Tracer Color", function(color)
	visuals.tracerColor = color
end):UpdateColor(visuals.tracerColor)
shots:CreateSlider("Tracer Duration", 0.5, 4, visuals.tracerDuration, false, function(value)
	visuals.tracerDuration = value
end)
shots:CreateToggle("Hit Effect", visuals.hitEffect, function(value)
	visuals.hitEffect = value
end)

window:CreateTab("Misc", "settings"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
