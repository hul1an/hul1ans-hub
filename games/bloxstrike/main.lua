local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Lighting = cloneref(game:GetService("Lighting"))
local TweenService = cloneref(game:GetService("TweenService"))
local Debris = cloneref(game:GetService("Debris"))
local HttpService = cloneref(game:GetService("HttpService"))

local esp =hub.require("games/bloxstrike/esp.lua")
local aim = hub.require("games/bloxstrike/aim.lua")
local view = hub.require("games/bloxstrike/view.lua")
local entities = hub.require("games/bloxstrike/entities.lua")
local movement = hub.require("games/bloxstrike/movement.lua")
local misc = hub.require("games/bloxstrike/misc.lua")
local hud = hub.require("games/bloxstrike/hud.lua")
-- dead or spectating, the camera is on someone else and there is nothing to shoot with
aim.blocked = function()
	local player = Players.LocalPlayer
	return player:GetAttribute("Dead") or player:GetAttribute("IsSpectating")
end

-- the game's spread is the angle across a shot's cone in degrees, and it never uses more than this
local MAX_SPREAD = 69
-- the bullet object of the gun that is out, kept by the hook on the game's spread update below
local equipped

-- the spread behind the trigger's Seeded and Hitchance. It follows the game's Bullet.create: the spread is the gun's
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
local NIGHT = {
	ClockTime = 0,
	Brightness = 2,
	OutdoorAmbient = Color3.fromRGB(70, 70, 90),
	Ambient = Color3.fromRGB(60, 60, 70),
	GlobalShadows = true,
	ExposureCompensation = 0.5,
}

local visuals = {
	thirdPersonDistance = 12,
	tracers = false,
	tracerColor = Color3.fromRGB(255, 41, 116),
	tracerSize = 0.08,
	tracerDuration = 1.2,
	hitEffect = false,
	sky = "none",
	precipitation = false,
	weather = { "rain" },
	outdoors = false,
	particles = 256,
	fog = false,
	fogDensity = 50,
	fogStart = 0,
	fogEnd = 4000,
	hitMarkers = {},
	damageMarker = false,
	damageColor = Color3.new(1, 1, 1),
	-- the three that leave the game's bloom as it is
	bloom = false,
	bloomScale = 100,
	bloomThreshold = 0.75,
	bloomBlur = 43,
	motionBlur = false,
	motionBlurAmount = 0.5,
	killEffects = false,
	killKinds = {},
	killShake = false,
	killShakeStrength = 10,
	sparks = false,
	sparkCount = 32,
}
local random = Random.new()

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

-- auto scope: zooms the gun that is out if it is a sniper not yet scoped, with the call the game's secondary fire key
-- makes, and returns whether it had to. The call starts a thread of its own so that no hub function is under it,
-- because the game has functions that look down the stack for an executor's
aim.scope = function()
	local weapon = equipped and equipped.IsActive and equipped.Weapon
	if not weapon or equipped.Properties.AimingOptions ~= "SniperScope" or weapon.IsAiming then
		return false
	end
	task.spawn(weapon.scope, weapon, true)
	return true
end

-- for the view card's force crosshair: whether the gun that is out is one with a sniper's scope
view.sniper = function()
	return equipped and equipped.IsActive and equipped.Properties.AimingOptions == "SniperScope"
end

-- for its scope overlay and scoped transparency: whether the gun that is out is zoomed in, and whether through a
-- sniper's scope, which is when the game draws its scope picture. The gun says; the Player's IsSniperScoped attribute
-- is only set for the AWP
view.scoped = function()
	local weapon = equipped and equipped.IsActive and equipped.Weapon
	if not (weapon and weapon.IsAiming) then
		return false, false
	end
	return true, equipped.Properties.AimingOptions == "SniperScope"
end

-- whether the gun that is out could fire now: not between two shots, reloading or empty
aim.ready = function()
	local weapon = equipped and equipped.IsActive and equipped.Weapon
	return weapon and not (weapon.IsShooting or weapon.IsReloading) and weapon.Rounds > 0
end

-- the game's numbers are CS2's, where damage falls by the gun's RangeModifier every 500 units; a unit is 0.075 studs here
local FALLOFF = 37.5

-- the damage behind the trigger's Min Damage. The server works damage out, so this is CS2's rule on the gun's own
-- figures: the part's damage, less for range, less again where armour covers the part, and by the gun's
-- WallbangMultiplier once for a shot that goes through something
aim.damage = function(part, distance, walled)
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
	if walled then
		damage *= properties.WallbangMultiplier
	end
	return damage
end

-- the game's bullet ray (Shared.Raycast): the studs of a material a bullet crosses before the gun's Penetration
-- starts to count, none for a material not listed; these two material variants give none whatever they are made of
local SOFT = {
	[Enum.Material.Plastic] = 10,
	[Enum.Material.SmoothPlastic] = 10,
	[Enum.Material.Wood] = 10,
	[Enum.Material.WoodPlanks] = 10,
	[Enum.Material.Cardboard] = 10,
	[Enum.Material.Glass] = 25,
	[Enum.Material.Fabric] = 25,
}
local HARD = { ["Sandy Brick"] = true, IndoorWall = true }
-- by the workspace's Map attribute: what a material that gives none gives there instead
local MAP_FLOOR = { Reactor = -1 }
local bulletRay = RaycastParams.new()
bulletRay.FilterType = Enum.RaycastFilterType.Exclude
bulletRay.CollisionGroup = "Bullet"
local exitRay = RaycastParams.new()
exitRay.FilterType = Enum.RaycastFilterType.Include
exitRay.CollisionGroup = "Bullet"

-- what the game's bullet ray leaves out (Components.Common.GetRayIgnore)
local function bulletIgnore()
	local ignore = { workspace.CurrentCamera, Players.LocalPlayer.Character }
	local function add(parent, name)
		local child = parent and parent:FindFirstChild(name)
		if child then
			table.insert(ignore, child)
		end
	end
	local map = workspace:FindFirstChild("Map")
	local zones = map and map:FindFirstChild("Zones")
	add(workspace, "Debris")
	add(map, "Cameras")
	add(map, "Barriers")
	add(map, "Ambience")
	add(zones, "Spawns")
	add(zones, "Sites")
	return ignore
end

-- auto wall: whether a bullet of the gun that is out would get from origin to a point on a model. It follows the
-- game's ray: a part is gone through while the studs crossed of its material so far are within what the material
-- gives plus the gun's Penetration, its thickness being measured by a ray back from the far side
aim.pierces = function(origin, point, model)
	if not (equipped and equipped.IsActive) then
		return false
	end
	local offset = point - origin
	local unit, length = offset.Unit, offset.Magnitude
	local crossed = {}
	local from = origin
	bulletRay.FilterDescendantsInstances = bulletIgnore()
	for _ = 1, 100 do
		local left = length - (from - origin):Dot(unit)
		local hit = left > 0 and workspace:Raycast(from, unit * left, bulletRay)
		if not hit or hit.Instance:IsDescendantOf(model) then
			return true
		end
		local part = hit.Instance
		bulletRay:AddToFilter(part)
		-- the ray passes these as if they weren't there
		if not (part:FindFirstAncestorWhichIsA("Accessory")
			or part:HasTag("CharacterAccessory")
			or part.Name == "CollisionCapsule"
			or part.Name == "HumanoidRootPart") then
			local far = hit.Position + unit * 1000
			exitRay.FilterDescendantsInstances = { part }
			local exit = workspace:Raycast(far, hit.Position - far, exitRay)
			if not exit then
				return false
			end

			local key, gives = part.MaterialVariant, 0
			if not HARD[key] then
				-- a breakable door counts as metal
				key = part.Parent:HasTag("BreakableDoor") and Enum.Material.Metal or part.Material
				gives = SOFT[key] or 0
			end
			if gives == 0 then
				gives = MAP_FLOOR[workspace:GetAttribute("Map")] or 0
			end
			crossed[key] = (crossed[key] or 0) + (hit.Position - exit.Position).Magnitude
			if crossed[key] > gives + (equipped.Properties.Penetration or 0) then
				return false
			end
			from = exit.Position
		end
	end
	return false
end

-- the game moves characters it has culled out of workspace.Characters and leaves their last position on them,
-- so only models still in that folder are real; it has no Humanoids or Roblox teams, only attributes.
-- the folder is read directly because bots are in it but not in the Players list
local players = esp.sources[1]
local charactersWarned = false

-- the living characters in the folder but the user's own: all of them, or with mates given only those who are (true)
-- or aren't (false) on the user's side. With the user on no side no one is
local function shown(mates)
	local characters = {}
	local folder = workspace:FindFirstChild("Characters")
	if not folder then
		if not charactersWarned then
			charactersWarned = true
			warn("[hub] workspace.Characters not found")
		end
		return characters
	end

	local team = Players.LocalPlayer:GetAttribute("Team")
	local mine = Players.LocalPlayer.Character
	for _, character in folder:GetChildren() do
		if character ~= mine
			and character:FindFirstChild("HumanoidRootPart")
			and not character:GetAttribute("Dead")
			and (mates == nil or (team ~= nil and teamOf(character) == team) == mates) then
			table.insert(characters, character)
		end
	end
	return characters
end

players.models = function(skipTeammates)
	return shown(if skipTeammates then false else nil)
end

esp.teammates.models = function()
	return shown(true)
end

-- the esp's source a character or a ragdoll is one of: the user's own, the teammates or the players
local function sourceOf(model)
	if ownerOf(model) == Players.LocalPlayer then
		return esp.own
	end
	local team = Players.LocalPlayer:GetAttribute("Team")
	return team and teamOf(model) == team and esp.teammates or players
end

players.label = function(character)
	local owner = ownerOf(character)
	return owner and owner.DisplayName or character.Name
end

players.health = function(character)
	return character:GetAttribute("Health"), character:GetAttribute("MaxHealth")
end

-- the game's file on each weapon, a module by the weapon's name: its Icon, and for a gun the Rounds a magazine takes
local database = ReplicatedStorage:FindFirstChild("Database")
local custom = database and database:FindFirstChild("Custom")
local weaponFiles = custom and custom:FindFirstChild("Weapons")
entities.files = weaponFiles
if not weaponFiles then
	warn("[hub] ReplicatedStorage.Database.Custom.Weapons not found: weapon icon and ammo bar unavailable")
	hub.ui.notify("ReplicatedStorage.Database.Custom.Weapons not found, no weapon icon or ammo bar", "error")
end

-- what a player holds is JSON on the Player, with the weapon's Name and the Rounds left in it. A bot's loadout doesn't
-- say which of its guns is out
players.weapon = function(character)
	local owner = ownerOf(character)
	local held = owner and owner:GetAttribute("CurrentEquipped")
	local name = held and held:match('"Name":"([^"]*)"')
	if not name then
		return nil
	end
	local file = weaponFiles and weaponFiles:FindFirstChild(name)
	local properties = file and require(file)
	return name, properties and properties.Icon, tonumber(held:match('"Rounds":(%d+)')), properties and properties.Rounds
end

players.avatar = function(character)
	local userId = tonumber(character:GetAttribute("PresentationOwnerUserId"))
	return userId and "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=48&h=48"
end

-- all but the last are read off the Player, which a bot doesn't have
players.flags = function(character, kinds)
	local flags = {}
	local owner = ownerOf(character)
	if owner then
		if table.find(kinds, "money") then
			table.insert(flags, "$" .. owner:GetAttribute("Money"))
		end
		local armor = owner:GetAttribute("Armor")
		if table.find(kinds, "armor") and type(armor) == "string" and (tonumber(armor:match('"Health":(%d+)')) or 0) > 0 then
			table.insert(flags, armor:find("Helmet", 1, true) and "HK" or "K")
		end
		if table.find(kinds, "kit") and (owner:GetAttribute("HasDefuseKit") or owner:GetAttribute("HasRescueKit")) then
			table.insert(flags, "kit")
		end
		if table.find(kinds, "scoped") and owner:GetAttribute("IsSniperScoped") then
			table.insert(flags, "scoped")
		end
	end
	if table.find(kinds, "bot") and character:GetAttribute("Bot") then
		table.insert(flags, "bot")
	end
	return flags
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

-- the shown character nearest a position, within a range of it
local function shownNear(position, range, skipTeammates)
	local nearest
	for _, character in players.models(skipTeammates) do
		local distance = (character.HumanoidRootPart.Position - position).Magnitude
		if distance <= range then
			nearest, range = character, distance
		end
	end
	return nearest
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

local heardSource = esp.addSource("heard", Color3.fromRGB(150, 150, 150), function()
	local now = os.clock()
	local models = {}
	for model, ghost in ghosts do
		local character = ghost.character
		local elsewhere = character and (character:IsDescendantOf(workspace) or character:GetAttribute("Dead"))
		-- gone quiet; or known to be someone who is now shown or dead; or a guess with a shown enemy where it stands,
		-- who is taken to be the one heard. A ghost known to be someone stays beside another enemy who is still shown
		if now - ghost.at > heard.memory
			or elsewhere and ghost.certain
			or not ghost.certain and shownNear(ghost.root.Position, HEARD_TRACK_RANGE, true) then
			ghosts[model] = nil
			model:Destroy()
		else
			-- a guess that was shown somewhere else or dead was someone else
			if elsewhere then
				ghost.character = nil
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

heardSource.toggle = "dormant esp"
heardSource.aimToggle = "dormant aimbot"
-- a ghost is nothing but its box
heardSource.box = true
heardSource.options = function(section)
	section:CreateSlider("fade out", 1, 10, heard.memory, true, function(value)
		heard.memory = value
	end, "%.0f s")
end
heardSource.opacityOf = function(model)
	return 1 - (os.clock() - ghosts[model].at) / heard.memory
end

-- puts a ghost at a position and starts its fade over, a new ghost when none is given
local function place(ghost, position)
	if not ghost then
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = model
		ghost = { root = root, certain = false }
		ghosts[model] = ghost
	end
	ghost.root.Position = position
	ghost.at = os.clock()
	return ghost
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
	nearest = place(nearest, position)

	if not nearest.certain then
		nearest.character, nearest.certain = identify(nearest, position, weapon)
	end
	local character = nearest.character
	if character then
		lastHeard[character] = { position = position, frozen = character.HumanoidRootPart.Position }
	end
end

-- the fog of war shows an enemy for a moment now and then. One the game hides again stands where it was last shown,
-- so it gets a ghost there, named for certain: the one it had, or one heard where it stands, or a new one
local shownFolder = workspace:FindFirstChild("Characters")
if shownFolder then
	-- the characters that were left in the folder since they were last hidden. The game makes a character there and
	-- hides it in the same breath, which is no sighting; its signals are deferred, so these run once it is done
	local sighted = setmetatable({}, { __mode = "k" })
	for _, character in shownFolder:GetChildren() do
		sighted[character] = true
	end
	hub.cleanup.add(shownFolder.ChildAdded:Connect(function(character)
		if character.Parent == shownFolder then
			sighted[character] = true
		end
	end))
	hub.cleanup.add(shownFolder.ChildRemoved:Connect(function(character)
		local seen = sighted[character]
		sighted[character] = nil
		if not (seen and esp.settings.Enabled and heardSource.enabled and table.find(hiddenEnemies(), character)) then
			return
		end
		local position = character.HumanoidRootPart.Position
		local own, best
		for _, ghost in ghosts do
			local distance = ghost.character == character and 0 or (ghost.root.Position - position).Magnitude
			if distance <= HEARD_TRACK_RANGE and (not best or distance < best) then
				own, best = ghost, distance
			end
		end
		own = place(own, position)
		own.character, own.certain = character, true
	end))
else
	warn("[hub] workspace.Characters not found: dormant esp won't keep the enemies the fog of war hides")
	hub.ui.notify("workspace.Characters not found, dormant esp won't keep the enemies the fog of war hides", "error")
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
		if not (sound:IsA("Sound") and noisy[sound.SoundId]) then
			return
		end
		local part = sound.Parent
		if not part:IsA("BasePart") then
			return
		end
		-- the shown character it is beside made it, and with no one there a hidden enemy did
		local maker = shownNear(part.Position, HEARD_OWNER_RANGE, false)
		if maker then
			esp.audible[maker] = os.clock()
			if not esp.override(maker).hidden then
				esp.sound(part.Position, sourceOf(maker))
			end
		elseif esp.settings.Enabled then
			esp.sound(part.Position, players)
			if heardSource.enabled then
				local class = noisy[sound.SoundId]
				hear(part.Position, class ~= "FloorSounds" and class or nil)
			end
		end
	end))

	-- the user's own sounds aren't played from a part under workspace.Debris: the game puts a footstep on the
	-- character's root part
	local characters = workspace:FindFirstChild("Characters")
	if characters then
		hub.cleanup.add(characters.DescendantAdded:Connect(function(sound)
			if not (sound:IsA("Sound") and noisy[sound.SoundId]) then
				return
			end
			local mine = Players.LocalPlayer.Character
			if mine and sound:IsDescendantOf(mine) then
				esp.audible[mine] = os.clock()
				esp.sound(mine:GetPivot().Position, esp.own)
			end
		end))
	else
		warn("[hub] workspace.Characters not found: only audible and sounds unavailable on the local page")
		hub.ui.notify("workspace.Characters not found, no only audible or sounds on the local page", "error")
	end
else
	local missing = soundBank and "workspace.Debris" or "ReplicatedStorage.Sounds"
	warn("[hub] " .. missing .. " not found: heard enemies, only audible and sounds unavailable")
	hub.ui.notify(missing .. " not found, no heard enemies, only audible or sounds", "error")
end

hub.cleanup.add(function()
	for model in ghosts do
		model:Destroy()
	end
	table.clear(ghosts)
end)

-- the game keeps a copy of every character ready under workspace.Debris and turns it into the ragdoll on death: one in
-- use has ClientRagdoll and Dead set, and its character's attributes, so whose it is is found as a character's is.
-- The ragdolls in use, each with its source
if debris then
	esp.ragdolls = function()
		local models = {}
		for _, model in debris:GetChildren() do
			if model:GetAttribute("ClientRagdoll") and model:GetAttribute("Dead") then
				models[model] = sourceOf(model)
			end
		end
		return models
	end
end

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
	part.Size = Vector3.new(visuals.tracerSize, visuals.tracerSize, length)
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

-- an emitter of the hub's dot texture that is put at a place and made to throw particles there. size is the box they
-- start in
local function burster(size, properties)
	local part = effectPart()
	part.Transparency = 1
	part.Size = size
	part.Parent = effects
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = hub.ui.asset("weather-dot.png")
	emitter.LightInfluence = 0
	emitter.SpreadAngle = Vector2.new(180, 180)
	for name, value in properties do
		emitter[name] = value
	end
	emitter.Parent = part
	return function(position, count)
		part.CFrame = CFrame.new(position)
		emitter:Emit(count)
	end
end

-- impact sparks, and the kill effect of the name
local spark = burster(Vector3.one * 0.2, {
	Color = ColorSequence.new(Color3.fromRGB(255, 200, 90)),
	LightEmission = 1,
	Size = NumberSequence.new(0.12, 0),
	Lifetime = NumberRange.new(0.2, 0.5),
	Speed = NumberRange.new(15, 35),
	Acceleration = Vector3.new(0, -60, 0),
	Drag = 2,
})
-- motes that leave a body's height of air and drift up
local dissolve = burster(Vector3.new(2, 5, 2), {
	Color = ColorSequence.new(Color3.new(1, 1, 1)),
	Size = NumberSequence.new(0.25, 0),
	Transparency = NumberSequence.new(0.2, 1),
	Lifetime = NumberRange.new(1, 2),
	Speed = NumberRange.new(1, 4),
	Acceleration = Vector3.new(0, 6, 0),
})

-- a jagged line of thin glowing parts from one point to another, gone in a moment
local function bolt(from, to, color, width, seconds)
	local pieces = 8
	local stray = (to - from).Magnitude / pieces * 0.4
	local last = from
	for piece = 1, pieces do
		local point = from:Lerp(to, piece / pieces)
		if piece < pieces then
			point += random:NextUnitVector() * stray
		end
		local length = (point - last).Magnitude
		local part = effectPart()
		part.Color = color
		part.Size = Vector3.new(width, width, length)
		part.CFrame = CFrame.lookAt(last, point) * CFrame.new(0, 0, -length / 2)
		part.Parent = effects
		fade(part, seconds, { Transparency = 1 })
		last = point
	end
end

-- starline's kill effects by name, each played where the shot that killed got to. What they look like is the hub's own
local KILL = {
	explosion = function(position)
		local part = effectPart()
		part.Shape = Enum.PartType.Ball
		part.Color = Color3.fromRGB(255, 150, 50)
		part.Size = Vector3.one
		part.CFrame = CFrame.new(position)
		part.Parent = effects
		fade(part, 0.6, { Size = Vector3.one * 14, Transparency = 1 })
	end,
	taser = function(position)
		for _ = 1, 5 do
			local from = position + random:NextUnitVector() * 2.5
			bolt(from, position + random:NextUnitVector() * 2.5, Color3.fromRGB(90, 170, 255), 0.08, 0.5)
		end
	end,
	lightning = function(position)
		bolt(position + Vector3.new(0, 80, 0), position, Color3.fromRGB(200, 220, 255), 0.35, 0.5)
	end,
	sparks = function(position)
		spark(position, 60)
	end,
	dissolve = function(position)
		dissolve(position, 80)
	end,
	shockwave = function(position)
		local part = effectPart()
		part.Shape = Enum.PartType.Cylinder
		part.Color = Color3.new(1, 1, 1)
		part.Transparency = 0.3
		part.Size = Vector3.new(0.2, 2, 2)
		-- a cylinder's length is its X, stood upright here so the disc lies flat
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		part.Parent = effects
		fade(part, 0.7, { Size = Vector3.new(0.2, 36, 36), Transparency = 1 })
	end,
}

-- the kill effects' screen shake: for a moment after a kill the view is turned a little at random, less and less. It
-- is done after the game's camera step and the hub's third person, so only what is shown moves and not where shots go
local SHAKE_STEP = "HubShake"
local SHAKE_TIME = 0.4
-- starline's strength runs 2 to 40; this many degrees for each
local SHAKE_DEGREES = 0.05
local shaken = 0

RunService:BindToRenderStep(SHAKE_STEP, Enum.RenderPriority.Camera.Value + 3, function()
	local left = 1 - (os.clock() - shaken) / SHAKE_TIME
	if left > 0 then
		local most = math.rad(visuals.killShakeStrength * SHAKE_DEGREES) * left
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(random:NextNumber(-most, most), random:NextNumber(-most, most), 0)
	end
end)
hub.cleanup.add(function()
	RunService:UnbindFromRenderStep(SHAKE_STEP)
end)

-- hit markers and damage numbers: drawings that are up for a moment. A mark is its drawings, when it began, how long it
-- lasts and where in the world it is, the middle of the screen without. A number drifts up; a hit marker is four
-- strokes out towards the corners
local marks = {}

local function mark(drawings, seconds, at)
	table.insert(marks, { drawings = drawings, began = os.clock(), seconds = seconds, at = at })
end

local function strokes()
	local lines = {}
	for index = 1, 4 do
		local line = Drawing.new("Line")
		line.Thickness = 1
		line.Color = Color3.new(1, 1, 1)
		lines[index] = line
	end
	return lines
end

local function marksStep()
	local camera = workspace.CurrentCamera
	local now = os.clock()
	for index = #marks, 1, -1 do
		local entry = marks[index]
		local age = (now - entry.began) / entry.seconds
		if age >= 1 then
			for _, drawing in entry.drawings do
				drawing:Remove()
			end
			table.remove(marks, index)
		else
			local center, shown = camera.ViewportSize / 2, true
			if entry.at then
				local point = camera:WorldToViewportPoint(entry.at)
				center, shown = Vector2.new(point.X, point.Y), point.Z > 0
			end
			for corner, drawing in entry.drawings do
				drawing.Visible = shown
				drawing.Transparency = 1 - age
				if #entry.drawings == 1 then
					drawing.Position = center - Vector2.new(0, 20 + 30 * age)
				else
					local way = Vector2.new(corner % 2 == 0 and 1 or -1, corner > 2 and 1 or -1)
					drawing.From = center + way * 4
					drawing.To = center + way * 10
				end
			end
		end
	end
end

hub.cleanup.add(function()
	for _, entry in marks do
		for _, drawing in entry.drawings do
			drawing:Remove()
		end
	end
	table.clear(marks)
end)

-- what a shot that hurt an enemy sets off besides the logs and the on hit chams. position is where it got to, killed
-- whether that was the end of them
local function hitEffects(position, damage, killed)
	if table.find(visuals.hitMarkers, "screen") then
		mark(strokes(), 0.4)
	end
	if table.find(visuals.hitMarkers, "world") then
		mark(strokes(), 1, position)
	end
	if visuals.damageMarker then
		local text = Drawing.new("Text")
		text.Size = 14
		text.Center = true
		text.Outline = true
		text.Color = visuals.damageColor
		text.Text = string.format("%.0f", damage)
		mark({ text }, 1, position)
	end
	if killed and visuals.killEffects then
		for _, kind in visuals.killKinds do
			KILL[kind](position)
		end
		if visuals.killShake then
			shaken = os.clock()
		end
	end
end

-- rewrites a finished bullet raycast so its last hit is the target; returns whether it did
local function redirect(result, target, point)
	local position = point or target.Position
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
		-- a shot that got to nothing has no hit to rewrite, only its direction, which is what the server is sent
		result.Direction = (position - rawget(result, "Origin")).Unit
		return true
	end

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
local function shotEnd(result, origin, turned)
	if turned then
		return turned
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

-- the hit and miss logs. kinds is which of the two are written
local logs = { kinds = {} }
-- shots that got to an enemy, by character and oldest first, each waiting for the server's damage to show in its Health
local awaited = {}
-- how long a shot waits for that before it counts as missed
local REGISTER_TIME = 1
-- lines from the shot hook. It runs on the game's thread, which may not touch the hub's GUI, so they are written from
-- the hub's own on the next Heartbeat
local written = {}

-- how a log names the part of the body a part is
local function limb(part)
	local name = part.Name
	for _, word in { "Arm", "Hand", "Leg", "Foot" } do
		if name:find(word) then
			return word:lower()
		end
	end
	return name == "UpperTorso" and "upper torso" or name == "LowerTorso" and "lower torso" or name:lower()
end

-- the enemy a part belongs to
local function enemyOf(part)
	local folder = workspace:FindFirstChild("Characters")
	local character = part
	while character and character.Parent ~= folder do
		character = character.Parent
	end
	if folder and character and teamOf(character) ~= Players.LocalPlayer:GetAttribute("Team") then
		return character
	end
	return nil
end

-- the end of a log line: what the shot was meant for, left out when it got just that
local function expectation(shot, got)
	if not shot.expected then
		return ""
	end
	local chance = string.format(" with %.0f%% hitchance", shot.chance)
	return (shot.expected == got and "" or " | expected " .. shot.expected) .. chance
end

-- angle is how far off the view ray the shot's spread could take it, target the part the shot was turned to if it was
-- and point the place on it
local function logShot(result, angle, target, point)
	local camera = workspace.CurrentCamera
	local model, part, chance = aim.expected(camera, angle)
	local shot = { at = os.clock(), expected = part and limb(part), chance = chance }

	local struck = target
	if not struck then
		for _, hit in rawget(result, "Hits") do
			if enemyOf(hit.Instance) then
				struck, point = hit.Instance, hit.Position
				break
			end
		end
	end
	local victim = struck and enemyOf(struck)
	if victim then
		local queue = awaited[victim] or {}
		awaited[victim] = queue
		-- a shotgun's pellets are one shot
		if not (queue[#queue] and shot.at - queue[#queue].at < 0.02) then
			shot.struck = limb(struck)
			shot.position = point
			shot.health = victim:GetAttribute("Health")
			-- where the on hit chams will stand, if the shot turns out to have hurt
			shot.pose = esp.settings.HitChams and esp.pose(victim)
			table.insert(queue, shot)
		end
		return
	end

	-- a shot at no one that got to no one isn't a miss
	if model and table.find(logs.kinds, "misses") then
		local reason = aim.missed(camera, model, part, rawget(result, "Origin"), rawget(result, "Direction"))
		local name = ghosts[model] and "heard enemy" or players.label(model)
		table.insert(written, "Missed " .. name .. " due to " .. reason .. expectation(shot))
	end
end

hub.cleanup.add(RunService.Heartbeat:Connect(function()
	for _, line in written do
		misc.log(line)
	end
	table.clear(written)

	local now = os.clock()
	for victim, queue in awaited do
		local shot = queue[1]
		-- a dead character is taken out of the folder or marked
		local dead = victim.Parent == nil or victim:GetAttribute("Dead")
		local health = dead and 0 or victim:GetAttribute("Health")
		if health < shot.health then
			if shot.pose then
				esp.flash(victim, shot.pose)
			end
			hitEffects(shot.position, shot.health - health, dead)
			misc.hit()
			if table.find(logs.kinds, "hits") then
				local damage = string.format(" for %.0f damage in ", shot.health - health)
				misc.log("Hit " .. players.label(victim) .. damage .. shot.struck .. expectation(shot, shot.struck))
			end
			table.remove(queue, 1)
			-- the shots after it are measured from what this one left
			for _, later in queue do
				later.health = health
			end
		elseif now - shot.at > REGISTER_TIME then
			if table.find(logs.kinds, "misses") then
				misc.log("Missed " .. players.label(victim) .. " due to no registration" .. expectation(shot))
			end
			table.remove(queue, 1)
		end
		if #queue == 0 then
			awaited[victim] = nil
		end
	end
end))

local function onShot(result, spread)
	-- silent aim turns the shot to the aim's target, backtrack to the place on an enemy whose old place it went through
	local target, point = aim.settings.SilentAim and aim.target, nil
	if not target then
		target, point = aim.rewind(rawget(result, "Origin"), rawget(result, "Direction"))
	end
	if not (target and target.Parent and redirect(result, target, point)) then
		target = nil
	end
	local turned = target and (point or target.Position)
	-- the logs, the on hit chams, the hit effects and the hitsound all go by which shots got to an enemy
	if #logs.kinds > 0
		or misc.settings.hitsound
		or esp.settings.HitChams
		or #visuals.hitMarkers > 0
		or visuals.damageMarker
		or visuals.killEffects then
		logShot(result, math.min(spread, MAX_SPREAD) / 2, target, turned)
	end

	if visuals.tracers or visuals.hitEffect or visuals.sparks then
		local origin = rawget(result, "Origin") or workspace.CurrentCamera.CFrame.Position
		local finish = typeof(origin) == "Vector3" and shotEnd(result, origin, turned)
		if finish then
			if visuals.tracers then
				tracer(origin, finish)
			end
			if visuals.hitEffect then
				hitEffect(finish)
			end
			if visuals.sparks then
				spark(finish, visuals.sparkCount)
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
		-- Seeded narrows the shot
		spread *= aim.spreadScale()
		local returns = table.pack(original(self, spread, ...))
		if type(returns[1]) == "table" then
			-- an error here would otherwise break the game's own shooting
			local ok, err = pcall(onShot, returns[1], spread)
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
			-- but for one a view row is holding at a value of its own
			if not view.held[property] then
				Lighting[property] = value
			end
		end
	end
end))

-- a CS2 unit in studs (MovementV2.SpeedProfile.HammerUnitToStud): starline's fog distances are in units
local UNIT = 0.075

-- the skybox row. The game keeps every map's lighting in a folder by the map's name, its Sky among it, and those are
-- the choices. The Sky in Lighting is given the chosen one's looks rather than swapped for it, because the game
-- destroys what is in Lighting whenever it sets a map's lighting up
local SKY = {
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
	"SkyboxOrientation",
	"SunTextureId",
	"SunAngularSize",
	"MoonTextureId",
	"MoonAngularSize",
	"StarCount",
	"CelestialBodiesShown",
}
local assets = ReplicatedStorage:FindFirstChild("Assets")
local mapLighting = assets and assets:FindFirstChild("Lighting")
local skies = {}
if mapLighting then
	for _, folder in mapLighting:GetChildren() do
		if folder:FindFirstChildOfClass("Sky") then
			table.insert(skies, folder.Name)
		end
	end
	table.sort(skies)
else
	warn("[hub] ReplicatedStorage.Assets.Lighting not found: no skyboxes")
	hub.ui.notify("ReplicatedStorage.Assets.Lighting not found, no skyboxes", "error")
end
table.insert(skies, 1, "none")

-- the Sky that was changed, the choice it was changed to, and what it had before
local sky, skyName, skyWas
-- the choice that is no sky at all, which no map is named
local BLANK = ""

local function skyStep()
	-- the view card's 2d skybox removal is a choice of its own, a sky with nothing in it
	local choice = table.find(view.settings.Removals, "2d skybox") and BLANK or visuals.sky
	local current = Lighting:FindFirstChildOfClass("Sky")
	if current == sky and choice == skyName then
		return
	end
	if sky then
		for property, value in skyWas do
			sky[property] = value
		end
	end
	sky, skyName, skyWas = current, choice, {}
	local folder = mapLighting and mapLighting:FindFirstChild(choice)
	local chosen = folder and folder:FindFirstChildOfClass("Sky")
	if current and (chosen or choice == BLANK) then
		for _, property in SKY do
			skyWas[property] = current[property]
			if chosen then
				current[property] = chosen[property]
			end
		end
		if not chosen then
			-- the first six are the faces
			for face = 1, 6 do
				current[SKY[face]] = ""
			end
			current.CelestialBodiesShown = false
			current.StarCount = 0
		end
	end
end

-- the fog row. Starline's fog is CS2's: none before start, thickest at end, and density the most it hides. Roblox's
-- runs from FogStart to a FogEnd where nothing shows, so FogEnd is put where the fog is as thick as the density at
-- starline's end. An Atmosphere in Lighting switches that fog off, so the game's is held out of it meanwhile
local fogWas, air

local function fogStep()
	if not visuals.fog then
		if fogWas then
			Lighting.FogStart, Lighting.FogEnd = fogWas[1], fogWas[2]
			fogWas = nil
			if air then
				air.Parent = Lighting
				air = nil
			end
		end
		return
	end
	fogWas = fogWas or { Lighting.FogStart, Lighting.FogEnd }
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		-- the one held is from a map since left, and out of Lighting the game doesn't destroy it
		if air then
			air:Destroy()
		end
		air = atmosphere
		atmosphere.Parent = nil
	end
	local start = visuals.fogStart * UNIT
	local reach = math.max(visuals.fogEnd * UNIT - start, 1)
	Lighting.FogStart = start
	Lighting.FogEnd = start + reach / math.max(visuals.fogDensity / 100, 0.001)
end

-- the precipitation row: an emitter for each type on a plate held over the camera, with the hub's own textures. speed
-- is in studs a second and life in seconds, which together are how far a particle falls; spread and spin are in degrees
local PLATE_HEIGHT = 35
local WEATHER = {
	rain = { texture = "weather-streak.png", speed = 80, life = 1, size = 2, color = Color3.fromRGB(190, 205, 225), fade = 0.5 },
	snow = { texture = "weather-dot.png", speed = 8, life = 8, size = 0.2, color = Color3.new(1, 1, 1), spread = 15 },
	leaves = { texture = "weather-leaf.png", speed = 7, life = 9, size = 0.6, color = Color3.fromRGB(170, 110, 50), spread = 25, spin = 180 },
	ashes = { texture = "weather-dot.png", speed = 4, life = 12, size = 0.12, color = Color3.fromRGB(120, 120, 120), spread = 20 },
	embers = { texture = "weather-dot.png", speed = 5, life = 10, size = 0.1, color = Color3.fromRGB(255, 130, 40), spread = 25, glow = 1 },
}
local plate = effectPart()
plate.Transparency = 1
plate.Size = Vector3.new(100, 1, 100)
plate.Parent = effects
local emitters = {}
for name, kind in WEATHER do
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = hub.ui.asset(kind.texture)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(kind.speed * 0.8, kind.speed)
	emitter.Lifetime = NumberRange.new(kind.life)
	emitter.Size = NumberSequence.new(kind.size)
	emitter.Color = ColorSequence.new(kind.color)
	emitter.Transparency = NumberSequence.new(kind.fade or 0)
	emitter.SpreadAngle = Vector2.one * (kind.spread or 0)
	emitter.Rotation = NumberRange.new(0, kind.spin and 360 or 0)
	emitter.RotSpeed = NumberRange.new(-(kind.spin or 0), kind.spin or 0)
	emitter.LightEmission = kind.glow or 0
	-- lit the same by day and under night mode
	emitter.LightInfluence = 0
	-- the rain's texture is a streak from left to right, which is the side of it this lays along the fall
	if name == "rain" then
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	end
	emitter.Parent = plate
	emitters[name] = emitter
end

local function weatherStep()
	local camera = workspace.CurrentCamera
	local eye = camera.CFrame.Position
	local falling = visuals.precipitation
	if falling then
		plate.CFrame = CFrame.new(eye + Vector3.new(0, PLATE_HEIGHT, 0))
		-- outdoors only: nothing falls while there is something over the camera. Particles don't stop at a roof, so
		-- this is as near as it gets
		if visuals.outdoors and not esp.visible(camera, eye + Vector3.new(0, 300, 0), plate) then
			falling = false
		end
	end
	for name, emitter in emitters do
		emitter.Enabled = falling and table.find(visuals.weather, name) ~= nil
		-- particles is how many are in the air at once, shared between the types
		emitter.Rate = visuals.particles / math.max(#visuals.weather, 1) / WEATHER[name].life
	end
end

-- the bloom row: the game's own BloomEffect, made anew for every map, is given the row's figures while it is on. Roblox
-- takes an intensity up to 1, a threshold from 0.8 to 4 and a size up to 56, and has no knee on the threshold
local BLOOM = { "Enabled", "Intensity", "Threshold", "Size" }
local bloom, bloomWas

local function bloomStep()
	local current = visuals.bloom and Lighting:FindFirstChildOfClass("BloomEffect") or nil
	if current ~= bloom then
		if bloom then
			for property, value in bloomWas do
				bloom[property] = value
			end
		end
		bloom, bloomWas = current, {}
		if current then
			for _, property in BLOOM do
				bloomWas[property] = current[property]
			end
		end
	end
	if bloom then
		bloom.Enabled = true
		bloom.Intensity = visuals.bloomScale / 100
		bloom.Threshold = 0.8 + visuals.bloomThreshold * 1.6
		bloom.Size = visuals.bloomBlur / 100 * 56
	end
end

-- the motion blur row. Roblox has no motion blur, so this is a BlurEffect whose size follows how fast the view is
-- turning: amount times this for each degree a second, up to a limit. It is under the camera, where it works as it
-- would in Lighting and the game doesn't destroy it
local BLUR_PER_DEGREE = 0.05
local BLUR_LIMIT = 24
local blur = hub.cleanup.add(Instance.new("BlurEffect"))
blur.Enabled = false
blur.Size = 0
blur.Parent = workspace.CurrentCamera
local lastLook

local function blurStep(dt)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local turn = lastLook and math.deg(look:Angle(lastLook)) / dt or 0
	lastLook = look
	blur.Enabled = visuals.motionBlur
	-- eased, so that it doesn't flicker with every frame's turn
	local wanted = math.min(turn * visuals.motionBlurAmount * BLUR_PER_DEGREE, BLUR_LIMIT)
	blur.Size += (wanted - blur.Size) * math.min(dt * 15, 1)
end

-- every frame, since the game makes what is in Lighting anew for each map
hub.cleanup.add(RunService.RenderStepped:Connect(function(dt)
	skyStep()
	fogStep()
	weatherStep()
	bloomStep()
	blurStep(dt)
	marksStep()
end))
hub.cleanup.add(function()
	visuals.sky, visuals.fog, visuals.bloom = "none", false, false
	view.settings.Removals = {}
	skyStep()
	fogStep()
	bloomStep()
end)

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

	-- shown, or as far hidden as the view card's scoped transparency has it
	setModifier(character, view.body())
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
		-- after the game's own camera step, which is one after the camera's
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

-- the user's own character is only there to see in third person, so that is when its page of the esp draws on it
esp.own.models = function()
	local character = thirdPerson and Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") and { character } or {}
end

-- every part inside something, added to a list
local function partsIn(root, parts)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

-- the game's names for the arms of a first person viewmodel, which carry the sleeves and gloves it puts on them, and
-- for the folders of a character with the gun in its hands and the ones it carries on its body
local ARMS = { "Left Arm", "Right Arm" }
local CARRIED = { Weapon = "WeaponModel", Attachments = "WeaponAttachments" }
local gearWarned = false

-- what the local page has chams rows for besides the body, each kind a list of parts by the model they are in. A
-- viewmodel is a Model under the camera named by its gun, holding the arms and the gun as a Model named Weapon, or
-- two for a pair of guns. What the character holds and carries is only there to see in third person
esp.gear = function()
	local gear = { Viewmodel = {}, Weapon = {}, Attachments = {} }
	for _, model in workspace.CurrentCamera:GetChildren() do
		if model:IsA("Model") then
			local arms = {}
			for _, name in ARMS do
				local arm = model:FindFirstChild(name)
				if arm then
					table.insert(arms, arm)
					partsIn(arm, arms)
				end
			end
			gear.Viewmodel[model] = arms
			for _, child in model:GetChildren() do
				if child:IsA("Model") and child.Name:find("^Weapon") then
					gear.Weapon[child] = partsIn(child, {})
				end
			end
		end
	end

	local character = thirdPerson and Players.LocalPlayer.Character
	if character then
		for kind, name in CARRIED do
			local folder = character:FindFirstChild(name)
			if folder then
				for _, model in folder:GetChildren() do
					gear[kind][model] = partsIn(model, {})
				end
			elseif not gearWarned then
				gearWarned = true
				warn("[hub] " .. name .. " not found in the local character: no chams on it in third person")
				hub.ui.notify(name .. " not found in the local character, no chams on it in third person", "error")
			end
		end
	end
	return gear
end

-- for the misc page's automatic pistol: the gun that is out
misc.weapon = function()
	return equipped and equipped.IsActive and equipped.Weapon
end

-- under this speed the game counts the character as standing still for spread
local STILL = 6.4

-- the trigger's auto stop: a counter-strafe, the move input turned against the way the character is going until it is
-- slow enough, and no move input after that
local function stop(input, state)
	if state.MovementMode ~= "Walking" then
		return
	end
	if not (state.OnGround or table.find(aim.settings.TriggerAutoStop, "in air")) then
		return
	end
	local velocity = state.Velocity
	local speed = math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
	if speed < STILL then
		input.Move = Vector2.zero
		return
	end
	-- the game's ProvenMath.moveVectorToWorld the other way round: a world direction as a move input for this yaw
	local sin, cos = math.sin(input.LookYaw), math.cos(input.LookYaw)
	local x, z = -velocity.X / speed, -velocity.Z / speed
	input.Move = Vector2.new(cos * x - sin * z, sin * x + cos * z)
end

-- the game's ground movement is Source's (MovementV2.Simulation.Config, the competitive figures): friction takes this
-- share of the speed a second, of StopSpeed when slower than it, and a move input adds this many times the gun's walk
-- speed a second
local FRICTION = 5.2
local ACCELERATE = 5.5
local STOP_SPEED = 6
local TICK = 1 / 60
-- the velocity the last movement command ran on
local velocity = Vector3.zero
entities.velocity = function()
	return velocity
end

-- for the trigger's early auto stop: how long a counter-strafe would take to still the character from the speed it has
aim.stopTime = function()
	if not (equipped and equipped.IsActive) then
		return 0
	end
	local walk = equipped.Properties.WalkSpeed
	local speed = math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
	local seconds = 0
	while speed > STILL do
		speed -= (math.max(speed, STOP_SPEED) * FRICTION + ACCELERATE * walk) * TICK
		seconds += TICK
	end
	return seconds
end

-- what the hub does to a movement command before the game builds and sends it: the movement page's features, then the
-- trigger's auto stop over them
local function command(input, state)
	velocity = state.Velocity
	movement.command(input, state)
	if aim.stopping then
		stop(input, state)
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
	local commandWarned = false
	local original
	original = hookfunction(runtime._buildCommandInput, function(self, input, state, ...)
		-- an error here would otherwise stop the game's own movement
		local ok, err = pcall(command, input, state)
		if not ok and not commandWarned then
			commandWarned = true
			warn("[hub] movement hook failed: " .. tostring(err))
		end
		return original(self, input, state, ...)
	end)

	hub.cleanup.add(function()
		hookfunction(runtime._buildCommandInput, original)
	end)
else
	warn("[hub] BloxStrike movement runtime (_buildCommandInput) not found: the movement page and auto stop unavailable")
	hub.ui.notify("MovementV2.Client.Runtime._buildCommandInput not found, no movement page or auto stop", "error")
end

-- the two sides of a match, as the Team attribute has them
local SIDES = { Terrorists = true, ["Counter-Terrorists"] = true }
-- the side the user was last on: dead, the user's own Team reads Spectators until the next round
local side

-- for the players › list page: everyone in the match, the enemies and the teammates, or nothing until the user has
-- been on a side. Each is an id (the name the character has, which the esp keeps a player's options by), a name, a
-- userId and whether it is the user. The hidden and the dead are among them: a Player is there either way, and a bot,
-- which has none, is its character in the game's folder of the shown or of the hidden
local function roster()
	local team = Players.LocalPlayer:GetAttribute("Team")
	if SIDES[team] then
		side = team
	end
	if not side then
		return nil
	end

	local enemies, teammates = {}, {}
	for _, player in Players:GetPlayers() do
		local you = player == Players.LocalPlayer
		local theirs = you and side or player:GetAttribute("Team")
		if SIDES[theirs] then
			table.insert(theirs == side and teammates or enemies, {
				id = player.Name,
				name = player.DisplayName,
				userId = player.UserId,
				you = you,
			})
		end
	end
	local function bots(folder)
		for _, character in folder and folder:GetChildren() or {} do
			if character:GetAttribute("Bot") then
				local list = character:GetAttribute("Team") == side and teammates or enemies
				table.insert(list, { id = character.Name, name = character.Name })
			end
		end
	end
	bots(workspace:FindFirstChild("Characters"))
	bots(ReplicatedStorage:FindFirstChild("_PVS_CulledCharacters"))

	-- by name, so that no one changes place as the game hides and shows them
	for _, list in { enemies, teammates } do
		table.sort(list, function(a, b)
			return a.name:lower() < b.name:lower()
		end)
	end
	return enemies, teammates
end

view.start()
entities.start()
movement.start()
misc.start()
hud.start()

local window = hub.ui.createWindow("BloxStrike")
hub.require("games/bloxstrike/tabs.lua")(window, {
	visuals = visuals,
	movement = movement.settings,
	misc = misc,
	hud = hud.settings,
	logs = logs,
	roster = roster,
	skies = skies,
	view = view,
	entities = entities,
	setNight = setNight,
	setThirdPerson = setThirdPerson,
})
-- the config that comes with the script, listed with the saved ones and not loaded until it is picked
window:AddConfig("default", HttpService:JSONDecode(hub.read("games/bloxstrike/default.json")))
