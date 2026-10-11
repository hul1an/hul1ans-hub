local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Lighting = cloneref(game:GetService("Lighting"))
local TweenService = cloneref(game:GetService("TweenService"))
local Debris = cloneref(game:GetService("Debris"))

local esp = hub.require("core/esp.lua")
local aim = hub.require("core/aim.lua")
-- adding this puts the Silent Aim toggle under the aim's Enabled; the shot hook reads it
aim.settings.SilentAim = false
-- dead or spectating, the camera is on someone else and there is nothing to shoot with
aim.blocked = function()
	local player = Players.LocalPlayer
	return player:GetAttribute("Dead") or player:GetAttribute("IsSpectating")
end

-- the game's spread is the angle across a shot's cone in degrees, and it never uses more than this
local MAX_SPREAD = 69
-- the bullet object of the gun that is out, kept by the hook on the game's spread update below
local equipped

-- setting this puts Seeded and Hitchance on the trigger. It follows the game's Bullet.create: the spread is the gun's
-- own plus what moving adds, an unscoped sniper's own spread is raised to a floor, and so is all of an AWP's in the
-- first 0.2 s of its scope
aim.spread = function()
	if not (equipped and equipped.IsActive) then
		return nil
	end
	local config = equipped.ActiveSpreadConfig or equipped.Properties.Spread
	local weapon = equipped.Weapon
	local own = equipped:getBaseSpreadForConfig(config)
	local least = 0
	if equipped.Properties.AimingOptions == "SniperScope" then
		local floor = config.MovementMultiplier == 2 and 6 or config.MovementMultiplier == 3 and 12 or 15
		if not weapon.IsAiming then
			own = math.max(own, floor)
		elseif weapon.Name == "AWP" and tick() - weapon.ScopeStartTick < 0.2 then
			least = floor
		end
	end
	local spread = math.max(own + equipped:getMovementSpreadForConfig(config), least)
	return math.min(spread, MAX_SPREAD) / 2
end

local THIRD_PERSON_STEP = "HubThirdPerson"
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

-- the game's numbers are CS2's, where damage falls by the gun's RangeModifier every 500 units; a unit is 0.075 studs here
local FALLOFF = 37.5

-- setting this puts Min Damage on the trigger. The server works damage out, so this is CS2's rule on the gun's own
-- figures: the part's damage, less for range, and less again where armour covers the part
aim.damage = function(part, distance)
	if not (equipped and equipped.IsActive) then
		return nil
	end
	local properties = equipped.Properties
	local name = part.Name
	local group = "Torso"
	if name == "Head" then
		group = "Head"
	elseif name:find("Arm") or name:find("Hand") then
		group = "Arms"
	elseif name:find("Leg") or name:find("Foot") then
		group = "Legs"
	end
	local damage = properties.DamagePerPart[group] * properties.RangeModifier ^ (distance / FALLOFF)

	-- a player's armour is JSON on the Player, its Health and a Type of "Kevlar" or "Kevlar + Helmet"
	local owner = ownerOf(part.Parent)
	local armor = owner and owner:GetAttribute("Armor")
	if type(armor) == "string" and (tonumber(armor:match('"Health":(%d+)')) or 0) > 0 then
		if group == "Head" and armor:find("Helmet", 1, true) or group == "Torso" or group == "Arms" then
			damage *= properties.ArmorPenetration
		end
	end
	return damage
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

-- the server leaves an enemy it has hidden out of the movement stream but still sends the sounds they make, and
-- the game plays each from a part at the spot. A footstep or shot that no shown character made is a hidden enemy,
-- kept as a bare root part for the ESP to draw until it goes quiet
local HEARD_OWNER_RANGE = 10
-- a runner's footsteps are about 5 studs apart
local HEARD_TRACK_RANGE = 15
local heard = { memory = 3 }
-- by model: root, at (when it was last heard), character (who it is taken to be) and certain
local ghosts = {}
-- by character: where it was last heard, and where its hidden model stood then
local lastHeard = {}

local function shownNear(position, range, skipTeammates)
	for _, character in players.models(skipTeammates) do
		if (character.HumanoidRootPart.Position - position).Magnitude <= range then
			return true
		end
	end
	return false
end

-- the living enemies the game has hidden, which it keeps in a folder of their own
local function hiddenEnemies()
	local characters = {}
	local folder = ReplicatedStorage:FindFirstChild("_PVS_CulledCharacters")
	if folder then
		local team = Players.LocalPlayer:GetAttribute("Team")
		for _, character in folder:GetChildren() do
			if character:FindFirstChild("HumanoidRootPart")
				and not character:GetAttribute("Dead")
				and not (team and teamOf(character) == team) then
				table.insert(characters, character)
			end
		end
	end
	return characters
end

-- a hidden model stays where it was last shown, so a sound heard since then is the later word
local function lastKnown(character)
	local frozen = character.HumanoidRootPart.Position
	local memory = lastHeard[character]
	return memory and memory.frozen == frozen and memory.position or frozen
end

-- a player's equipped weapon and a bot's loadout are both JSON with the weapon under Name
local function holds(character, weapon)
	local owner = ownerOf(character)
	local items = owner and owner:GetAttribute("CurrentEquipped") or character:GetAttribute("BotLoadout")
	return items ~= nil and items:find('"Name":"' .. weapon .. '"', 1, true) ~= nil
end

-- a sound doesn't say who made it: of the hidden enemies no other ghost has, and for a shot those with that
-- weapon, it is taken to be the one last known nearest. The second value is whether there was no one else
local function identify(ghost, position, weapon)
	local taken = {}
	for _, other in ghosts do
		if other ~= ghost and other.character then
			taken[other.character] = true
		end
	end

	local candidates, holders = {}, {}
	for _, character in hiddenEnemies() do
		if not taken[character] then
			table.insert(candidates, character)
			if weapon and holds(character, weapon) then
				table.insert(holders, character)
			end
		end
	end
	if #holders > 0 then
		candidates = holders
	end

	local nearest, best
	for _, character in candidates do
		local distance = (lastKnown(character) - position).Magnitude
		if not best or distance < best then
			nearest, best = character, distance
		end
	end
	return nearest, #candidates == 1
end

local heardSource = esp.addSource("Heard", Color3.fromRGB(150, 150, 150), function()
	local now = os.clock()
	local models = {}
	for model, ghost in ghosts do
		-- gone quiet, or shown again and drawn as itself
		if now - ghost.at > heard.memory or shownNear(ghost.root.Position, HEARD_TRACK_RANGE, true) then
			ghosts[model] = nil
			model:Destroy()
		else
			-- shown somewhere else or dead, it was someone else
			local character = ghost.character
			if character and (character:IsDescendantOf(workspace) or character:GetAttribute("Dead")) then
				ghost.character, ghost.certain = nil, false
			end
			table.insert(models, model)
		end
	end
	return models
end, function(model)
	local ghost = ghosts[model]
	if not ghost.character then
		return ""
	end
	return players.label(ghost.character) .. (ghost.certain and "" or "?")
end)

heardSource.toggle = "Dormant ESP"
heardSource.aimToggle = "Dormant Aimbot"
heardSource.opacityOf = function(model)
	return 1 - (os.clock() - ghosts[model].at) / heard.memory
end

-- weapon is the gun's name for a shot, nil for a footstep
local function hear(position, weapon)
	local nearest, best
	for _, ghost in ghosts do
		local distance = (ghost.root.Position - position).Magnitude
		if distance <= HEARD_TRACK_RANGE and (not best or distance < best) then
			nearest, best = ghost, distance
		end
	end
	if not nearest then
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = model
		nearest = { root = root, certain = false }
		ghosts[model] = nearest
	end
	nearest.root.Position = position
	nearest.at = os.clock()

	if not nearest.certain then
		nearest.character, nearest.certain = identify(nearest, position, weapon)
	end
	local character = nearest.character
	if character then
		lastHeard[character] = { position = position, frozen = character.HumanoidRootPart.Position }
	end
end

local soundBank = ReplicatedStorage:FindFirstChild("Sounds")
local debris = workspace:FindFirstChild("Debris")
if soundBank and debris then
	-- Sounds.<class>.<name>.<variant>, a gun's class being its name; what plays is a clone under another name,
	-- which keeps the id
	local noisy = {}
	for _, sound in soundBank:GetDescendants() do
		if sound:IsA("Sound") then
			local class = sound.Parent.Parent.Name
			if class == "FloorSounds" or sound.Parent.Name == "Shoot" then
				noisy[sound.SoundId] = class
			end
		end
	end

	hub.cleanup.add(debris.DescendantAdded:Connect(function(sound)
		if not (esp.settings.Enabled and heardSource.enabled and sound:IsA("Sound") and noisy[sound.SoundId]) then
			return
		end
		local part = sound.Parent
		if part:IsA("BasePart") and not shownNear(part.Position, HEARD_OWNER_RANGE, false) then
			local class = noisy[sound.SoundId]
			hear(part.Position, class ~= "FloorSounds" and class or nil)
		end
	end))
else
	local missing = soundBank and "workspace.Debris" or "ReplicatedStorage.Sounds"
	warn("[hub] " .. missing .. " not found: heard enemies unavailable")
	hub.ui.notify(missing .. " not found, no heard enemies", "error")
end

hub.cleanup.add(function()
	for model in ghosts do
		model:Destroy()
	end
	table.clear(ghosts)
end)

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
	local target = aim.settings.SilentAim and aim.target
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
		warn("[hub] BloxStrike bullet class (_performRaycast) not found: silent aim, seeded, hitchance, tracers and hit effect unavailable")
		return
	end

	local shotWarned = false
	local original
	original = hookfunction(bullets._performRaycast, function(self, spread, ...)
		-- the trigger's Seeded narrows its own shots
		local returns = table.pack(original(self, spread * aim.spreadScale(), ...))
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

	-- the game steps the spread of the gun that is out every frame, which is how the hub learns which bullet object that is
	local step
	step = hookfunction(bullets.updateSpread, function(self, ...)
		if self.IsActive then
			equipped = self
		end
		return step(self, ...)
	end)

	hub.cleanup.add(function()
		hookfunction(bullets.updateSpread, step)
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

	if antiAim.disableOnFire and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
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

-- the game sends the jump button for as long as the key is held and its simulation only jumps on a fresh press,
-- so bunnyhop drops the button from every command but the first one on the ground
local JUMP = 1
local movement = { bunnyhop = false }

local function hop(input, state)
	if bit32.band(input.Buttons, JUMP) == 0 or state.MovementMode ~= "Walking" then
		return
	end
	-- on the ground with the button already down the jump was refused, so it is released to be pressed again
	if not state.OnGround or bit32.band(state.PreviousButtons, JUMP) ~= 0 then
		input.Buttons -= JUMP
	end
end

-- the movement runtime's class, whose _buildCommandInput gets each command's input and the state it will run on
local runtime
for _, object in getgc(true) do
	if type(object) == "table" and type(rawget(object, "_buildCommandInput")) == "function" then
		runtime = object
		break
	end
end

if runtime then
	local hopWarned = false
	local original
	original = hookfunction(runtime._buildCommandInput, function(self, input, state, ...)
		if movement.bunnyhop then
			-- an error here would otherwise stop the game's own movement
			local ok, err = pcall(hop, input, state)
			if not ok and not hopWarned then
				hopWarned = true
				warn("[hub] bunnyhop hook failed: " .. tostring(err))
			end
		end
		return original(self, input, state, ...)
	end)

	hub.cleanup.add(function()
		hookfunction(runtime._buildCommandInput, original)
	end)
else
	warn("[hub] BloxStrike movement runtime (_buildCommandInput) not found: bunnyhop unavailable")
	hub.ui.notify("MovementV2.Client.Runtime._buildCommandInput not found, no bunnyhop", "error")
end

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
espSection:CreateSlider("Fade Out", 1, 10, heard.memory, true, function(value)
	heard.memory = value
end, "%.0f s")

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

local jumping = window:CreateTab("Movement", "layers"):CreateSection("Jumping", "LeftSide")
if runtime then
	jumping:CreateToggle("Bhop",movement.bunnyhop, function(value)
		movement.bunnyhop = value
	end)
end

window:CreateTab("Misc", "settings"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
