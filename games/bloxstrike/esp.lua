local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(230, 60, 60)
local BLUE = Color3.fromRGB(80, 140, 255)

-- only audible draws a model for this long after its last sound, and a sound's mark fades over this long
local AUDIBLE_TIME = 1
local SOUND_TIME = 1
-- starline's sound radius is in CS2 units, which the game makes 0.075 studs
local UNIT = 0.075
local AVATAR_SIZE = 14
local ICON_SIZE = Vector2.new(48, 16)
local ARROW_SHADOW = Vector2.new(2, 2)
-- seconds between the invisible chams' looks at which parts of a body are in plain sight, a ray a part
local SIGHT_TIME = 0.1
-- how much bigger than the body an overlay or an on hit copy is, so that it wraps it
local SHELL = 1.05
-- the game's tick, which backtrack chams draw one copy for
local TICK = 1 / 60
-- where a backtrack copy waits while it has no record to stand at
local PARKED = CFrame.new(0, -100000, 0)
-- the chams materials as they go on a part, glass see-through even at full opacity. Each takes the part's Color.
-- solid is a colour with no shading, which no material is: it is a Highlight's fill, over this on an on hit copy
local MATERIALS = {
	solid = { material = Enum.Material.SmoothPlastic },
	flat = { material = Enum.Material.SmoothPlastic },
	glow = { material = Enum.Material.Neon },
	ghost = { material = Enum.Material.ForceField },
	glass = { material = Enum.Material.Glass, transparency = 0.5 },
}

local BONES_R15 = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}
local BONES_R6 = {
	{ "Head", "Torso" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
}

local esp = {
	settings = {
		Enabled = false,
		Box = true,
		BoxColor = WHITE,
		Skeleton = false,
		SkeletonColor = WHITE,
		Chams = false,
		ChamsColor = WHITE,
		ChamsOpacity = 1,
		VisibleChams = false,
		VisibleChamsColor = WHITE,
		VisibleChamsOpacity = 1,
		InvisibleChams = false,
		InvisibleChamsColor = WHITE,
		InvisibleChamsOpacity = 1,
		InvisibleChamsMaterial = "solid",
		OverlayChams = false,
		OverlayChamsColor = WHITE,
		OverlayChamsOpacity = 1,
		OverlayChamsMaterial = "ghost",
		RagdollChams = false,
		RagdollChamsColor = WHITE,
		RagdollChamsOpacity = 1,
		RagdollChamsMaterial = "solid",
		BacktrackChams = false,
		BacktrackChamsColor = WHITE,
		BacktrackChamsOpacity = 1,
		BacktrackChamsMaterial = "flat",
		BacktrackChamsPerTick = false,
		BacktrackChamsGradient = false,
		BacktrackChamsOldest = RED,
		BacktrackChamsOldestOpacity = 1,
		BacktrackChamsNewest = GREEN,
		BacktrackChamsNewestOpacity = 1,
		HitChams = false,
		HitChamsColor = WHITE,
		HitChamsOpacity = 1,
		HitChamsMaterial = "solid",
		HitChamsDuration = 1,
		HitChamsGlow = false,
		HitChamsGlowColor = WHITE,
		HitChamsGlowOpacity = 1,
		VisibleChamsMaterial = "solid",
		HealthBar = true,
		-- the bar's colour at full health; it runs to red as health drops
		HealthBarColor = GREEN,
		Name = true,
		NameColor = WHITE,
		OnlyVisible = false,
		OnlyAudible = false,
		Avatar = false,
		WeaponName = false,
		WeaponNameColor = WHITE,
		WeaponIcon = false,
		WeaponIconColor = WHITE,
		AmmoBar = false,
		AmmoBarColor = BLUE,
		Flags = {},
		Sounds = false,
		SoundsColor = WHITE,
		SoundsType = "circle",
		SoundsRadius = 20,
		Arrows = false,
		ArrowsColor = WHITE,
		ArrowsShadow = false,
		ArrowsShadowColor = BLACK,
		ArrowsOutline = false,
		ArrowsOutlineColor = BLACK,
		ArrowsSize = 12,
		ArrowsOffset = 24,
	},
	sources = {},
	-- by model, when it was last heard; main.lua writes it for only audible
	audible = setmetatable({}, { __mode = "k" }),
	-- by model, where each of its parts was on the frames of the backtrack time, oldest first: a record is at and
	-- frames, the CFrame by part. The aim keeps it for its backtrack and the backtrack chams draw it
	past = {},
}

local settings = esp.settings
local sets = {}
local bones = {}
local highlights = {}
-- by model, its avatar and weapon icon: ImageLabels, since a Drawing image can't show a Roblox asset
local images = {}
-- the marks of sounds: position, at and circle
local sounds = {}
-- by model, what visible chams has done to it: the material's name and the colour, and what each part (parts), skin
-- (taken, by where it was) and face decal (decals) had before
local skins = {}
-- the copies the other chams draw, each set a Model and its copies by part. By model: the invisible chams' set, the
-- overlay's, the backtrack's list of sets with one a tick, and the on hit set with when it began
local shades, shells, trails, flashes = {}, {}, {}, {}
-- the ragdolls the ragdoll chams had last frame
local ragdolls = {}
-- the folder in the world the copies are kept in
local world
local container, screen
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- whether the camera has a line to a point on a model
function esp.visible(camera, point, model)
	-- the camera is excluded because first person viewmodels are parented to it
	local ignore = { model, camera, Players.LocalPlayer.Character }
	local origin = camera.CFrame.Position
	-- fully invisible parts (map barriers, clip walls) are looked through, up to a few in a row
	for _ = 1, 8 do
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, point - origin, rayParams)
		if not hit then
			return true
		end
		if hit.Instance.Transparency < 1 then
			return false
		end
		table.insert(ignore, hit.Instance)
	end
	return false
end

-- main.lua calls this with where an enemy made a sound
function esp.sound(position)
	if settings.Enabled and settings.Sounds then
		local circle = Drawing.new("Circle")
		circle.Thickness = 1
		circle.NumSides = 32
		table.insert(sounds, { position = position, at = os.clock(), circle = circle })
	end
end

-- health and max health of a model: the source's own health(model) if it has one, else its Humanoid's
function esp.health(model, source)
	if source.health then
		return source.health(model)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health, humanoid.MaxHealth
	end
	return nil
end

-- models(skipTeammates) returns the models to draw, label(model) their name text.
-- a source given a colour is drawn in it throughout; one without, the players, in each element's colour from the settings.
-- a source may also have weapon(model), returning what the model holds: its name, its icon, the rounds left and the
-- rounds a magazine takes; avatar(model), returning an image of who it is; and flags(model, kinds), returning the texts
-- of those of the chosen flags that apply
function esp.addSource(name, color, models, label)
	local source = {
		name = name,
		enabled = true,
		color = color,
		maxDistance = 10000,
		aim = false,
		models = models,
		label = label,
	}
	table.insert(esp.sources, source)
	return source
end

local players = esp.addSource("players", nil, function(skipTeammates)
	local characters = {}
	local team = skipTeammates and Players.LocalPlayer.Team
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player.Character and not (team and player.Team == team) then
			table.insert(characters, player.Character)
		end
	end
	return characters
end, function(character)
	return Players:GetPlayerFromCharacter(character).DisplayName
end)
players.aim = true

local function draw(class, properties)
	local object = Drawing.new(class)
	for name, value in properties do
		object[name] = value
	end
	return object
end

local function createSet()
	return {
		boxOutline = draw("Square", { Thickness = 3, Color = BLACK }),
		box = draw("Square", { Thickness = 1 }),
		healthBack = draw("Square", { Filled = true, Color = BLACK }),
		health = draw("Square", { Filled = true }),
		name = draw("Text", { Size = 13, Center = true, Outline = true }),
		ammoBack = draw("Square", { Filled = true, Color = BLACK }),
		ammo = draw("Square", { Filled = true }),
		weapon = draw("Text", { Size = 13, Center = true, Outline = true }),
		flags = draw("Text", { Size = 13, Outline = true, Color = WHITE }),
		arrowShadow = draw("Triangle", { Filled = true }),
		arrow = draw("Triangle", { Filled = true }),
		arrowOutline = draw("Triangle", { Thickness = 1 }),
	}
end

-- a model's avatar or weapon icon, shown at a place on screen; without an image it is hidden
local function picture(model, key, image, position, size, color, opacity)
	local labels = images[model]
	local label = labels and labels[key]
	if not image then
		if label then
			label.Visible = false
		end
		return
	end
	if not label then
		label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.ScaleType = Enum.ScaleType.Fit
		label.Parent = screen
		labels = labels or {}
		images[model] = labels
		labels[key] = label
	end
	label.Image = image
	label.ImageColor3 = color
	label.ImageTransparency = 1 - opacity
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.Visible = true
end

-- bones, highlights and images only exist for models that have a set
local function hide(model)
	for _, object in sets[model] do
		object.Visible = false
	end
	if images[model] then
		for _, label in images[model] do
			label.Visible = false
		end
	end
	if bones[model] then
		for _, line in bones[model] do
			line.Visible = false
		end
	end
	if highlights[model] then
		highlights[model].Enabled = false
	end
end

local function destroy(model)
	for _, object in sets[model] do
		object:Remove()
	end
	sets[model] = nil
	if images[model] then
		for _, label in images[model] do
			label:Destroy()
		end
		images[model] = nil
	end
	if bones[model] then
		for _, line in bones[model] do
			line:Remove()
		end
		bones[model] = nil
	end
	if highlights[model] then
		highlights[model]:Destroy()
		highlights[model] = nil
	end
end

local function updateSkeleton(model, camera, color)
	local lines = bones[model]
	if not settings.Skeleton then
		if lines then
			for _, line in lines do
				line.Visible = false
			end
		end
		return
	end
	if not lines then
		lines = {}
		bones[model] = lines
	end

	local map = model:FindFirstChild("UpperTorso") and BONES_R15 or BONES_R6
	for index, pair in map do
		local line = lines[index]
		if not line then
			line = draw("Line", { Thickness = 1 })
			lines[index] = line
		end
		local from, to = model:FindFirstChild(pair[1]), model:FindFirstChild(pair[2])
		local a = from and camera:WorldToViewportPoint(from.Position)
		local b = to and camera:WorldToViewportPoint(to.Position)
		local visible = a ~= nil and b ~= nil and a.Z > 0 and b.Z > 0
		line.Visible = visible
		if visible then
			line.Color = color
			line.From = Vector2.new(a.X, a.Y)
			line.To = Vector2.new(b.X, b.Y)
		end
	end
	for index = #map + 1, #lines do
		lines[index].Visible = false
	end
end

-- the hub's Highlight on a model: a fill colour and an outline colour, each with its opacity and either left out for
-- none. A model shows one Highlight and that has one depth mode, so an outline, which is there to be seen through
-- walls, takes the fill through them with it; through does that for a fill with no outline
local function light(model, fill, fillOpacity, line, lineOpacity, through)
	local highlight = highlights[model]
	if not (fill or line) then
		if highlight then
			highlight.Enabled = false
		end
		return
	end
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Adornee = model
		highlight.Parent = container
		highlights[model] = highlight
	end
	highlight.DepthMode = (line or through) and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	highlight.FillColor = fill or WHITE
	highlight.FillTransparency = fill and 1 - fillOpacity or 1
	highlight.OutlineColor = line or WHITE
	highlight.OutlineTransparency = line and 1 - lineOpacity or 1
	highlight.Enabled = true
end

local function unlight(model)
	if highlights[model] then
		highlights[model]:Destroy()
		highlights[model] = nil
	end
end

-- a model's Highlight: the glow is its outline, and the solid visible chams its fill
local function updateChams(model, source, color)
	local solid = source == players and settings.VisibleChams and settings.VisibleChamsMaterial == "solid"
	light(
		model,
		solid and settings.VisibleChamsColor,
		settings.VisibleChamsOpacity,
		settings.Chams and color,
		settings.ChamsOpacity
	)
end

-- the parts visible chams repaint: the body, which is the model's own children, and the armour, not what it carries
local function bodyParts(model)
	local parts = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	local armor = model:FindFirstChild("CharacterArmor")
	if armor then
		for _, child in armor:GetDescendants() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end
	return parts
end

-- gives a model's parts a material, a colour and an opacity, remembering what each had. It runs every frame, so a part
-- the game adds later is done too
local function paint(model, name, color, opacity)
	local skin = skins[model]
	if not skin then
		skin = { parts = {}, taken = {}, textures = {} }
		skins[model] = skin
	end
	local changed = skin.name ~= name or skin.color ~= color or skin.opacity ~= opacity
	skin.name, skin.color, skin.opacity = name, color, opacity
	local look = MATERIALS[name]

	for _, part in bodyParts(model) do
		local old = skin.parts[part]
		local new = old == nil
		if new then
			-- a part that can't be seen, like the root, is left that way
			old = part.Transparency < 1
				and {
					Material = part.Material,
					MaterialVariant = part.MaterialVariant,
					Color = part.Color,
					Transparency = part.Transparency,
					TextureID = part:IsA("MeshPart") and part.TextureID or nil,
				}
			skin.parts[part] = old
			if old then
				-- the skin is a SurfaceAppearance, which covers the material while it is on the part; the face is decals,
				-- and a head that is a plain Part has its texture on a SpecialMesh
				for _, child in part:GetChildren() do
					if child:IsA("SurfaceAppearance") then
						skin.taken[child] = part
						child.Parent = nil
					elseif child:IsA("Decal") then
						skin.textures[child] = { "Transparency", child.Transparency }
						child.Transparency = 1
					elseif child:IsA("SpecialMesh") then
						skin.textures[child] = { "TextureId", child.TextureId }
						child.TextureId = ""
					end
				end
				if old.TextureID then
					part.TextureID = ""
				end
				part.MaterialVariant = ""
			end
		end
		if old and (new or changed) then
			part.Material = look.material
			part.Color = color
			part.Transparency = 1 - opacity * (1 - (look.transparency or old.Transparency))
		end
	end
end

-- puts back what paint changed
local function strip(model)
	local skin = skins[model]
	skins[model] = nil
	for part, old in skin.parts do
		if old then
			for property, value in old do
				part[property] = value
			end
		end
	end
	for appearance, part in skin.taken do
		-- a part the game has destroyed can't be given it back
		if part.Parent then
			appearance.Parent = part
		end
	end
	for child, old in skin.textures do
		child[old[1]] = old[2]
	end
end

-- whether a part of a model is one that shows, going by what it was before paint changed it
local function showing(model, part)
	local skin = skins[model]
	local old = skin and skin.parts[part]
	if old ~= nil then
		return old ~= false
	end
	return part.Transparency < 1
end

-- bare copies of some of a model's parts under a Model of their own, to be dressed and put where the model is or
-- was. Welded, each copy rides on its part; otherwise it stays where it is put. The result is the Model and the
-- copies by part
local function copyParts(model, parts, parent, scale, welded)
	local holder = Instance.new("Model")
	local copies = {}
	for _, part in parts do
		if showing(model, part) then
			local copy = part:Clone()
			-- a head that is a plain Part keeps the SpecialMesh that shapes it
			for _, child in copy:GetChildren() do
				if child:IsA("SpecialMesh") then
					child.TextureId = ""
				else
					child:Destroy()
				end
			end
			copy.Anchored = not welded
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.Massless = true
			copy.LocalTransparencyModifier = 0
			copy.Material = Enum.Material.SmoothPlastic
			copy.MaterialVariant = ""
			copy.Size = part.Size * scale
			if copy:IsA("MeshPart") then
				copy.TextureID = ""
			end
			if welded then
				local weld = Instance.new("Weld")
				weld.Part0 = part
				weld.Part1 = copy
				weld.Parent = copy
			end
			copy.Parent = holder
			copies[part] = copy
		end
	end
	holder.Parent = parent
	return { model = holder, copies = copies }
end

-- gives a set of copies a material, a colour and an opacity, writing only what has changed since it last did
local function dress(set, name, color, opacity)
	local look = MATERIALS[name]
	local material = set.name ~= name and look.material
	local tint = set.color ~= color
	local fade = (set.name ~= name or set.opacity ~= opacity) and 1 - opacity * (1 - (look.transparency or 0))
	if not (material or tint or fade) then
		return
	end
	set.name, set.color, set.opacity = name, color, opacity
	for _, copy in set.copies do
		if material then
			copy.Material = material
		end
		if tint then
			copy.Color = color
		end
		if fade then
			copy.Transparency = fade
		end
	end
end

-- destroys the copies kept by model for those that are gone, or all of them with the row off
local function prune(kept, on, seen)
	for model, set in kept do
		if not (on and seen[model]) then
			unlight(set.model)
			set.model:Destroy()
			kept[model] = nil
		end
	end
end

-- invisible chams: a Highlight through walls, solid its fill and glow its outline, on copies riding on the body. It
-- is on copies so that it can leave out what is in plain sight, which the model's own Highlight couldn't
local function shade(model, camera)
	local set = shades[model]
	if not set then
		set = copyParts(model, bodyParts(model), world, 1, true)
		shades[model] = set
	end
	local color, opacity = settings.InvisibleChamsColor, settings.InvisibleChamsOpacity
	local now = os.clock()
	if now - (set.checked or 0) > SIGHT_TIME then
		set.checked = now
		for part, copy in set.copies do
			-- a Highlight leaves a fully transparent part out, so a part in plain sight is left to the model itself and
			-- to the visible chams. A copy out of sight has the wall in front of it, and is only there to be highlit
			copy.Transparency = esp.visible(camera, part.Position, model) and 1 or 0
			copy.Color = color
		end
	end
	if settings.InvisibleChamsMaterial == "solid" then
		light(set.model, color, opacity, nil, nil, true)
	else
		light(set.model, nil, nil, color, opacity)
	end
end

-- overlay chams: a second skin a little bigger than the body, riding on it in the world
local function shell(model)
	local set = shells[model]
	if not set then
		set = copyParts(model, bodyParts(model), world, SHELL, true)
		shells[model] = set
	end
	dress(set, settings.OverlayChamsMaterial, settings.OverlayChamsColor, settings.OverlayChamsOpacity)
end

-- backtrack chams: copies standing in the world where the aim's backtrack has the model's parts on record. The
-- oldest place only, or with per tick one for every game tick on record, in a gradient from oldest to newest if set
local function trail(model, camera)
	local records = esp.past[model]
	if not records then
		return
	end
	local state = trails[model]
	if not state then
		state = { picked = {}, drawn = {}, spare = {}, folder = Instance.new("Folder") }
		trails[model] = state
	end
	local picked, drawn, spare = state.picked, state.drawn, state.spare

	-- a record is taken to draw once a game tick and kept until the aim has dropped it, and its copy stands where it
	-- was put: moving every copy every frame is what made per tick heavy
	local newest = records[#records]
	if #picked == 0 or newest.at - picked[#picked].at >= TICK then
		table.insert(picked, newest)
	end
	while picked[1] and picked[1].at < records[1].at do
		table.remove(picked, 1)
	end
	-- the copies are what costs, so they are only out for a model that is on screen and in plain sight
	local head = model:FindFirstChild("Head") or model.HumanoidRootPart
	local _, onScreen = camera:WorldToViewportPoint(head.Position)
	if not (onScreen and esp.visible(camera, head.Position, model)) then
		state.folder.Parent = nil
		return
	end
	state.folder.Parent = world

	-- the newest one taken is still where the model is, so it isn't drawn
	local last = settings.BacktrackChamsPerTick and #picked - 1 or math.min(#picked - 1, 1)
	local wanted = {}
	for index = 1, last do
		wanted[picked[index]] = true
	end
	for record, set in drawn do
		if not wanted[record] then
			drawn[record] = nil
			table.insert(spare, set)
		end
	end

	local name = settings.BacktrackChamsMaterial
	local gradient = settings.BacktrackChamsPerTick and settings.BacktrackChamsGradient and last > 1
	for index = 1, last do
		local record = picked[index]
		local set = drawn[record]
		if not set then
			set = table.remove(spare)
			if not set then
				local parts = {}
				for part in record.frames do
					table.insert(parts, part)
				end
				set = copyParts(model, parts, state.folder, 1)
			end
			for part, copy in set.copies do
				copy.CFrame = record.frames[part]
			end
			set.parked = false
			drawn[record] = set
		end
		local color, opacity = settings.BacktrackChamsColor, settings.BacktrackChamsOpacity
		if gradient then
			local along = (index - 1) / (last - 1)
			color = settings.BacktrackChamsOldest:Lerp(settings.BacktrackChamsNewest, along)
			opacity = settings.BacktrackChamsOldestOpacity
				+ (settings.BacktrackChamsNewestOpacity - settings.BacktrackChamsOldestOpacity) * along
		end
		dress(set, name, color, opacity)
	end
	-- a copy with no record to stand at waits out of the way
	for _, set in spare do
		if not set.parked then
			set.parked = true
			for _, copy in set.copies do
				copy.CFrame = PARKED
			end
		end
	end
end

local function endTrail(model)
	trails[model].folder:Destroy()
	trails[model] = nil
end

-- where a model's body parts are, for esp.flash later
function esp.pose(model)
	local frames = {}
	for _, part in bodyParts(model) do
		frames[part] = part.CFrame
	end
	return frames
end

-- on hit chams: main.lua calls this when a shot of the user's has hurt a model, with the pose it had when the shot was
-- fired. A copy stands there, a little bigger than the body it may still be around, and fades. One a model at a time
function esp.flash(model, frames)
	if not (settings.Enabled and settings.HitChams) then
		return
	end
	local old = flashes[model]
	if old then
		unlight(old.model)
		old.model:Destroy()
	end
	local set = copyParts(model, bodyParts(model), world, SHELL)
	for part, copy in set.copies do
		copy.CFrame = frames[part] or part.CFrame
	end
	set.at = os.clock()
	flashes[model] = set
end

local function renderFlashes()
	local now = os.clock()
	local name, color = settings.HitChamsMaterial, settings.HitChamsColor
	for model, set in flashes do
		local left = 1 - (now - set.at) / settings.HitChamsDuration
		if left <= 0 or not (settings.Enabled and settings.HitChams) then
			unlight(set.model)
			set.model:Destroy()
			flashes[model] = nil
		else
			local opacity = settings.HitChamsOpacity * left
			dress(set, name, color, opacity)
			local glow = settings.HitChamsGlow and settings.HitChamsGlowColor
			light(set.model, name == "solid" and color, opacity, glow, settings.HitChamsGlowOpacity * left)
		end
	end
end

-- ragdoll chams: the enemies' ragdolls, which main.lua lists, painted as the visible chams paint the living
local function renderRagdolls(painted)
	local lying = {}
	if settings.RagdollChams and esp.ragdolls then
		local name = settings.RagdollChamsMaterial
		for _, model in esp.ragdolls() do
			lying[model] = true
			if name == "solid" then
				light(model, settings.RagdollChamsColor, settings.RagdollChamsOpacity)
			else
				light(model)
				painted[model] = true
				paint(model, name, settings.RagdollChamsColor, settings.RagdollChamsOpacity)
			end
		end
	end
	for model in ragdolls do
		if not lying[model] then
			unlight(model)
		end
	end
	ragdolls = lying
end

-- undoes every kind of chams, for the esp going off and the hub unloading
local function clearChams()
	for model in skins do
		strip(model)
	end
	prune(shades, false)
	prune(shells, false)
	for model in trails do
		endTrail(model)
	end
	for model, set in flashes do
		unlight(set.model)
		set.model:Destroy()
		flashes[model] = nil
	end
	for model in ragdolls do
		unlight(model)
	end
	ragdolls = {}
end

-- an arrow towards a model that is off the screen, its tip the offset in from the screen's edge
local function point(set, camera, viewport, center, color)
	local offset = camera.CFrame:PointToObjectSpace(center)
	local direction = Vector2.new(offset.X, -offset.Y)
	-- straight behind, it points down
	direction = direction.Magnitude > 0.01 and direction.Unit or Vector2.yAxis
	local size = settings.ArrowsSize
	local at = viewport / 2 + direction * (viewport / 2 - Vector2.one * (size + settings.ArrowsOffset))
	local side = Vector2.new(-direction.Y, direction.X) * size / 2
	local a, b, c = at + direction * size, at - side, at + side

	local shadow, fill, outline = set.arrowShadow, set.arrow, set.arrowOutline
	shadow.Visible = settings.ArrowsShadow
	shadow.Color = settings.ArrowsShadowColor
	shadow.PointA, shadow.PointB, shadow.PointC = a + ARROW_SHADOW, b + ARROW_SHADOW, c + ARROW_SHADOW
	fill.Visible = true
	fill.Color = color
	fill.PointA, fill.PointB, fill.PointC = a, b, c
	outline.Visible = settings.ArrowsOutline
	outline.Color = settings.ArrowsOutlineColor
	outline.PointA, outline.PointB, outline.PointC = a, b, c
end

local function update(model, source, camera, viewport)
	local health, maxHealth = esp.health(model, source)
	if health and health <= 0 then
		return false
	end

	-- the root part is used when there is one: a model's bounding box is thrown off by parts kept elsewhere
	local root = model:FindFirstChild("HumanoidRootPart")
	local center, up, down
	if root then
		-- head top and feet as multiples of the root's height, so scaled characters still fit
		center, up, down = root.Position, root.Size.Y * 1.25, root.Size.Y * 1.5
	else
		local cframe, size = model:GetBoundingBox()
		center, up, down = cframe.Position, size.Y / 2, size.Y / 2
	end

	local distance = (camera.CFrame.Position - center).Magnitude
	if distance > source.maxDistance then
		return false
	end

	-- the two filters are for models that are really there, which a heard ghost isn't
	if source == players then
		local head = model:FindFirstChild("Head")
		if settings.OnlyVisible and not esp.visible(camera, head and head.Position or center, model) then
			return false
		end
		if settings.OnlyAudible and os.clock() - (esp.audible[model] or 0) > AUDIBLE_TIME then
			return false
		end
	end

	local top = camera:WorldToViewportPoint(center + Vector3.new(0, up, 0))
	local bottom = camera:WorldToViewportPoint(center - Vector3.new(0, down, 0))
	local _, onScreen = camera:WorldToViewportPoint(center)
	local pointed = settings.Arrows and not onScreen
	if not pointed and (top.Z <= 0 or bottom.Z <= 0) then
		return false
	end

	-- drawings are only made for models that are in range, and in front of the camera or pointed at
	local set = sets[model]
	if not set then
		set = createSet()
		sets[model] = set
	end

	-- a source may fade its models: opacityOf(model) gives 0 to 1, which is what a drawing's Transparency holds
	local opacity = source.opacityOf and source.opacityOf(model) or 1
	for _, object in set do
		object.Transparency = opacity
	end

	local own = source.color
	if pointed then
		hide(model)
		point(set, camera, viewport, center, own or settings.ArrowsColor)
		return true
	end
	set.arrowShadow.Visible, set.arrow.Visible, set.arrowOutline.Visible = false, false, false

	local height = math.abs(bottom.Y - top.Y)
	-- characters are about half as wide as they are tall
	local width = height / 2
	local x = top.X - width / 2
	local y = math.min(top.Y, bottom.Y)

	set.boxOutline.Visible = settings.Box
	set.boxOutline.Position = Vector2.new(x, y)
	set.boxOutline.Size = Vector2.new(width, height)
	set.box.Visible = settings.Box
	set.box.Color = own or settings.BoxColor
	set.box.Position = Vector2.new(x, y)
	set.box.Size = Vector2.new(width, height)

	local showHealth = health ~= nil and settings.HealthBar
	set.healthBack.Visible = showHealth
	set.health.Visible = showHealth
	if showHealth then
		local fraction = math.clamp(health / maxHealth, 0, 1)
		set.healthBack.Position = Vector2.new(x - 7, y - 1)
		set.healthBack.Size = Vector2.new(4, height + 2)
		set.health.Color = RED:Lerp(settings.HealthBarColor, fraction)
		set.health.Position = Vector2.new(x - 6, y + height * (1 - fraction))
		set.health.Size = Vector2.new(2, height * fraction)
	end

	set.name.Visible = settings.Name
	set.name.Color = own or settings.NameColor
	if settings.Name then
		set.name.Text = source.label(model)
		set.name.Position = Vector2.new(x + width / 2, y - 16)
	end

	-- the avatar goes left of the name, or in its place
	local left = settings.Name and set.name.TextBounds.X / 2 + 2 + AVATAR_SIZE or AVATAR_SIZE / 2
	local avatar = settings.Avatar and source.avatar and source.avatar(model)
	picture(model, "avatar", avatar, Vector2.new(x + width / 2 - left, y - 16), Vector2.one * AVATAR_SIZE, WHITE, opacity)

	-- under the box, from the top: ammo bar, weapon name, weapon icon
	local weapon, icon, rounds, magazine
	if source.weapon and (settings.AmmoBar or settings.WeaponName or settings.WeaponIcon) then
		weapon, icon, rounds, magazine = source.weapon(model)
	end
	local below = y + height + 2
	-- a knife or a grenade has no rounds
	local showAmmo = settings.AmmoBar and rounds ~= nil and magazine ~= nil
	set.ammoBack.Visible = showAmmo
	set.ammo.Visible = showAmmo
	if showAmmo then
		set.ammoBack.Position = Vector2.new(x - 1, below)
		set.ammoBack.Size = Vector2.new(width + 2, 4)
		set.ammo.Color = settings.AmmoBarColor
		set.ammo.Position = Vector2.new(x, below + 1)
		set.ammo.Size = Vector2.new(width * math.clamp(rounds / magazine, 0, 1), 2)
		below += 6
	end
	local showWeapon = settings.WeaponName and weapon ~= nil
	set.weapon.Visible = showWeapon
	if showWeapon then
		set.weapon.Color = settings.WeaponNameColor
		set.weapon.Text = weapon
		set.weapon.Position = Vector2.new(x + width / 2, below)
		below += 14
	end
	local iconAt = Vector2.new(x + width / 2 - ICON_SIZE.X / 2, below)
	picture(model, "icon", settings.WeaponIcon and icon, iconAt, ICON_SIZE, settings.WeaponIconColor, opacity)

	-- the flags run down the box's right side
	local showFlags = #settings.Flags > 0 and source.flags ~= nil
	set.flags.Visible = showFlags
	if showFlags then
		set.flags.Text = table.concat(source.flags(model, settings.Flags), "\n")
		set.flags.Position = Vector2.new(x + width + 4, y - 2)
	end

	updateSkeleton(model, camera, own or settings.SkeletonColor)
	updateChams(model, source, own or settings.ChamsColor)

	return true
end

-- a sound's mark fades where it was made: a circle of the radius in pixels, or as a ring one of that many units in the
-- world, growing as it goes
local function renderSounds(camera, viewport)
	local now = os.clock()
	for index = #sounds, 1, -1 do
		local sound = sounds[index]
		local age = (now - sound.at) / SOUND_TIME
		local circle = sound.circle
		if age > 1 or not (settings.Enabled and settings.Sounds) then
			circle:Remove()
			table.remove(sounds, index)
		else
			local at = camera:WorldToViewportPoint(sound.position)
			circle.Visible = at.Z > 0
			circle.Color = settings.SoundsColor
			circle.Transparency = 1 - age
			circle.Position = Vector2.new(at.X, at.Y)
			circle.Radius = settings.SoundsRadius
			if settings.SoundsType == "ring" then
				local perStud = viewport.Y / 2 / (at.Z * math.tan(math.rad(camera.FieldOfView / 2)))
				circle.Radius = settings.SoundsRadius * UNIT * age * perStud
			end
		end
	end
end

local function render()
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	renderSounds(camera, viewport)
	if not settings.Enabled then
		for model in sets do
			hide(model)
		end
		clearChams()
		return
	end

	-- solid is the Highlight's fill; every other visible chams material goes on the players' own parts
	local material = settings.VisibleChams and settings.VisibleChamsMaterial ~= "solid" and settings.VisibleChamsMaterial
	-- the models whose own parts chams have painted this frame
	local painted = {}
	local seen = {}
	for _, source in esp.sources do
		if source.enabled then
			for _, model in source.models(true) do
				seen[model] = true
				if source == players then
					if material then
						painted[model] = true
						paint(model, material, settings.VisibleChamsColor, settings.VisibleChamsOpacity)
					end
					if settings.InvisibleChams then
						shade(model, camera)
					end
					if settings.OverlayChams then
						shell(model)
					end
					if settings.BacktrackChams then
						trail(model, camera)
					end
				end
				if not update(model, source, camera, viewport) and sets[model] then
					hide(model)
				end
			end
		end
	end

	-- models that despawned or whose source was switched off
	for model in sets do
		if not seen[model] then
			destroy(model)
		end
	end
	renderRagdolls(painted)
	renderFlashes()
	for model in skins do
		if not painted[model] then
			strip(model)
		end
	end
	prune(shades, settings.InvisibleChams, seen)
	prune(shells, settings.OverlayChams, seen)
	for model in trails do
		if not (settings.BacktrackChams and seen[model]) then
			endTrail(model)
		end
	end
end

function esp.start()
	container = hub.cleanup.add(Instance.new("Folder"))
	container.Parent = gethui()
	-- its offsets are the viewport's, as a drawing's are, and the menu stays over it
	screen = hub.cleanup.add(Instance.new("ScreenGui"))
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = -1
	screen.Parent = gethui()
	-- under the camera, where the game's bullets and the aim's line of sight look past it
	world = hub.cleanup.add(Instance.new("Folder"))
	world.Parent = workspace.CurrentCamera

	hub.cleanup.add(function()
		for model in sets do
			destroy(model)
		end
		clearChams()
		for _, sound in sounds do
			sound.circle:Remove()
		end
		table.clear(sounds)
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
