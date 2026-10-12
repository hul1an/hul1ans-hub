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
-- and an invisible chams copy: where two Highlights cover the same pixel only one is drawn, and the copy's has to be
-- the nearer of it and the one on the body, the visible chams' solid fill or the game's own on a spectated player
local COVER = 1.03
-- the game's tick, which backtrack chams draw one copy for
local TICK = 1 / 60
-- where a backtrack copy waits while it has no record to stand at
local PARKED = CFrame.new(0, -100000, 0)
-- how far back the backtrack chams of the teammates and the user go: the longest the aim's backtrack does
local BACKTRACK_TIME = 0.2
-- what the user's own page has chams rows for besides the body, as esp.gear names them
local GEAR = { "Viewmodel", "Weapon", "Attachments" }
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
	-- the enemies' options; esp.teammates and esp.own, further down, each have their own under the same keys
	settings = {
		Enabled = false,
		Box = true,
		BoxColor = WHITE,
		Skeleton = false,
		SkeletonColor = WHITE,
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

-- every source that is drawn. esp.sources is those of them the enemies' page shows and the aim picks its targets from
local all = {}
local sets = {}
local bones = {}
local highlights = {}
-- by model, its avatar and weapon icon: ImageLabels, since a Drawing image can't show a Roblox asset
local images = {}
-- the marks of sounds: position, at, circle and the settings they are drawn by
local sounds = {}
-- by what it is on, a model or for the user's gear the model its parts are in, what chams have painted: the material's
-- name, the colour and the opacity, what each part (parts), skin (taken, by where it was) and face decal (textures)
-- had before, and the transparency last put on each part (wrote)
local skins = {}
-- the copies the other chams draw, each set a Model and its copies by part. By model: the invisible chams' set, the
-- overlay's, the backtrack's list of sets with one a tick, and the on hit set with when it began and its settings
local shades, shells, trails, flashes = {}, {}, {}, {}
-- the ragdolls the ragdoll chams had last frame
local ragdolls = {}
-- by model, for the teammates and the user: the backtrack chams' records, which the aim only keeps of its targets, and
-- the health last frame, for the on hit chams
local walked = setmetatable({}, { __mode = "k" })
local healths = setmetatable({}, { __mode = "k" })
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

-- main.lua calls this with where a model of a source made a sound
function esp.sound(position, source)
	local settings = source.settings
	if settings.Enabled and settings.Sounds then
		local circle = Drawing.new("Circle")
		circle.Thickness = 1
		circle.NumSides = 32
		table.insert(sounds, { position = position, at = os.clock(), circle = circle, settings = settings })
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
		settings = esp.settings,
	}
	table.insert(esp.sources, source)
	table.insert(all, source)
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
-- its models are bodies, for the chams to go on and the two filters to test, which a heard ghost isn't
players.real = true

-- the menu's other two pages, the user's teammates and the user's own character: drawn as the players are, with
-- whatever main.lua sets on the players source, but each by options of its own. main.lua sets their models
local function page()
	local settings = table.clone(esp.settings)
	-- solid is a Highlight's fill, and Roblox draws 31 Highlights: these two pages use none
	for _, row in { "Visible", "Ragdoll", "Hit" } do
		settings[row .. "ChamsMaterial"] = "flat"
	end
	local source = setmetatable({ settings = settings }, { __index = players })
	source.models = function()
		return {}
	end
	table.insert(all, source)
	return source
end
esp.teammates = page()
esp.own = page()
for _, kind in GEAR do
	local own = esp.own.settings
	for row, material in { [kind .. "Chams"] = "flat", [kind .. "OverlayChams"] = "ghost" } do
		own[row], own[row .. "Color"], own[row .. "Opacity"], own[row .. "Material"] = false, WHITE, 1, material
	end
end

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

local function updateSkeleton(model, camera, settings, color)
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

-- a model's Highlight: the solid visible chams are its fill
local function updateChams(model, source)
	local settings = source.settings
	local solid = source.real and settings.VisibleChams and settings.VisibleChamsMaterial == "solid"
	light(model, solid and settings.VisibleChamsColor, settings.VisibleChamsOpacity)
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

-- gives some parts a material, a colour and an opacity, remembering what each had, under what they are on: a model, or
-- for the user's gear the model its parts are in. It runs every frame, so a part the game adds later is done too
local function paint(holder, parts, name, color, opacity)
	local skin = skins[holder]
	if not skin then
		skin = { parts = {}, taken = {}, textures = {}, wrote = {} }
		skins[holder] = skin
	end
	local changed = skin.name ~= name or skin.color ~= color or skin.opacity ~= opacity
	skin.name, skin.color, skin.opacity = name, color, opacity
	local look = MATERIALS[name]

	for _, part in parts do
		local old = skin.parts[part]
		local now = part.Transparency
		-- a part that can't be seen is left that way: the root always, and a holstered gun or a scoped sniper's viewmodel,
		-- which the game hides at Transparency 1, until it shows
		if old or now < 1 then
			local new = old == nil
			if new then
				old = {
					Material = part.Material,
					MaterialVariant = part.MaterialVariant,
					Color = part.Color,
					Transparency = now,
					TextureID = part:IsA("MeshPart") and part.TextureID or nil,
				}
				skin.parts[part] = old
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
			if new or changed then
				part.Material = look.material
				part.Color = color
			end
			if now == 1 and now ~= skin.wrote[part] then
				-- the game has hidden it since it was painted
				skin.wrote[part] = nil
			elseif new or changed or now ~= skin.wrote[part] then
				-- the last is a part the game has shown again, which it does at a transparency of its own
				local shown = 1 - opacity * (1 - (look.transparency or old.Transparency))
				part.Transparency = shown
				skin.wrote[part] = shown
			end
		end
	end
end

-- puts back what paint changed
local function strip(holder)
	local skin = skins[holder]
	skins[holder] = nil
	for part, old in skin.parts do
		local shown = old.Transparency
		-- a part the game has hidden since stays hidden
		if part.Transparency == 1 and skin.wrote[part] ~= 1 then
			old.Transparency = nil
		end
		for property, value in old do
			part[property] = value
		end
		-- a viewmodel part comes back from hidden at the transparency in this attribute, which the game takes the first
		-- time it hides the part, in paint or not
		if part:GetAttribute("HiddenTransparency") then
			part:SetAttribute("HiddenTransparency", shown)
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

-- whether a part can't be seen: at Transparency 1 without paint having put it there
local function hidden(holder, part)
	local skin = skins[holder]
	return part.Transparency == 1 and not (skin and skin.wrote[part] == 1)
end

-- those of some parts that can be seen
local function showing(holder, parts)
	local seen = {}
	for _, part in parts do
		if not hidden(holder, part) then
			table.insert(seen, part)
		end
	end
	return seen
end

-- a bare copy of a part, to be dressed and put where the part is or was. Welded, it rides on the part; otherwise it
-- stays where it is put
local function copyPart(part, scale, welded)
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
	return copy
end

-- copies of some parts under a Model of their own. The result is the Model and the copies by part
local function copyParts(parts, parent, scale, welded)
	local holder = Instance.new("Model")
	local copies = {}
	for _, part in parts do
		local copy = copyPart(part, scale, welded)
		copy.Parent = holder
		copies[part] = copy
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

-- destroys the copies kept by model for those their row wasn't on for this frame
local function prune(kept, seen)
	for model, set in kept do
		if not seen[model] then
			unlight(set.model)
			set.model:Destroy()
			kept[model] = nil
		end
	end
end

-- invisible chams: a Highlight through walls, solid its fill and glow its outline, on copies riding on the body. It
-- is on copies so that it can leave out what is in plain sight, which the model's own Highlight couldn't
local function shade(model, camera, settings)
	local set = shades[model]
	if not set then
		set = copyParts(showing(model, bodyParts(model)), world, COVER, true)
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
local function shell(model, settings)
	local set = shells[model]
	if not set then
		set = copyParts(showing(model, bodyParts(model)), world, SHELL, true)
		shells[model] = set
	end
	dress(set, settings.OverlayChamsMaterial, settings.OverlayChamsColor, settings.OverlayChamsOpacity)
end

-- the same on the user's gear. The game hides it part by part, a holstered gun or a scoped sniper's viewmodel, and the
-- hub's third person hides the viewmodel: a part gets its copy once it shows, and the copy is hidden whenever it is
local function wrap(holder, parts, name, color, opacity)
	local set = shells[holder]
	if not set then
		set = copyParts({}, world, SHELL, true)
		shells[holder] = set
	end
	for _, part in parts do
		local gone = hidden(holder, part)
		local copy = set.copies[part]
		if not (copy or gone) then
			copy = copyPart(part, SHELL, true)
			copy.Parent = set.model
			set.copies[part] = copy
			-- so that dress does the new copy
			set.name, set.color = nil, nil
		end
		if copy then
			copy.LocalTransparencyModifier = gone and 1 or part.LocalTransparencyModifier
		end
	end
	dress(set, name, color, opacity)
end

-- where the body of a teammate or of the user has been over the backtrack time, as the aim records its targets in
-- esp.past
local function remember(model, now)
	local frames = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			frames[child] = child.CFrame
		end
	end
	local records = walked[model] or {}
	walked[model] = records
	table.insert(records, { at = now, frames = frames })
	while now - records[1].at > BACKTRACK_TIME do
		table.remove(records, 1)
	end
	return records
end

-- backtrack chams: copies standing in the world where a model's parts are on record. The oldest place only, or with
-- per tick one for every game tick on record, in a gradient from oldest to newest if set
local function trail(model, camera, settings, records)
	if not records then
		return
	end
	local state = trails[model]
	if not state then
		state = { picked = {}, drawn = {}, spare = {}, folder = Instance.new("Folder") }
		trails[model] = state
	end
	local picked, drawn, spare = state.picked, state.drawn, state.spare

	-- a record is taken to draw once a game tick and kept until it has been dropped, and its copy stands where it
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
				set = copyParts(showing(model, parts), state.folder, 1)
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

-- on hit chams: a copy of a model stands in a pose it had, a little bigger than the body it may still be around, and
-- fades. One a model at a time
local function flash(model, frames, settings)
	local old = flashes[model]
	if old then
		unlight(old.model)
		old.model:Destroy()
	end
	local set = copyParts(showing(model, bodyParts(model)), world, SHELL)
	for part, copy in set.copies do
		copy.CFrame = frames[part] or part.CFrame
	end
	set.at = os.clock()
	set.settings = settings
	flashes[model] = set
end

-- main.lua calls this when a shot of the user's has hurt an enemy, with the pose it had when the shot was fired
function esp.flash(model, frames)
	if esp.settings.Enabled and esp.settings.HitChams then
		flash(model, frames, esp.settings)
	end
end

-- main.lua reports no hits on the teammates or the user, so their on hit chams go by a drop in health, whoever caused it
local function watch(model, source)
	local health = esp.health(model, source)
	local before = healths[model]
	healths[model] = health
	if before and health and health < before then
		flash(model, esp.pose(model), source.settings)
	end
end

local function renderFlashes()
	local now = os.clock()
	for model, set in flashes do
		local settings = set.settings
		local left = 1 - (now - set.at) / settings.HitChamsDuration
		if left <= 0 or not (settings.Enabled and settings.HitChams) then
			unlight(set.model)
			set.model:Destroy()
			flashes[model] = nil
		else
			local name, color = settings.HitChamsMaterial, settings.HitChamsColor
			local opacity = settings.HitChamsOpacity * left
			dress(set, name, color, opacity)
			local glow = settings.HitChamsGlow and settings.HitChamsGlowColor
			light(set.model, name == "solid" and color, opacity, glow, settings.HitChamsGlowOpacity * left)
		end
	end
end

-- ragdoll chams: the ragdolls in use, which main.lua lists by the source each is one of, painted as the visible chams
-- paint the living
local function renderRagdolls(painted)
	local lying = {}
	local wanted = false
	for _, source in all do
		wanted = wanted or source.settings.Enabled and source.settings.RagdollChams
	end
	if wanted and esp.ragdolls then
		for model, source in esp.ragdolls() do
			local settings = source.settings
			if settings.Enabled and settings.RagdollChams then
				lying[model] = true
				local name = settings.RagdollChamsMaterial
				if name == "solid" then
					light(model, settings.RagdollChamsColor, settings.RagdollChamsOpacity)
				else
					light(model)
					painted[model] = true
					paint(model, bodyParts(model), name, settings.RagdollChamsColor, settings.RagdollChamsOpacity)
				end
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

-- the user's own page's rows for what isn't the body. esp.gear, set by main.lua, lists the parts of each kind by the
-- model they are in; each kind has a row that paints them and a row that puts an overlay on them
local function renderGear(painted, shelled)
	local settings = esp.own.settings
	if not (settings.Enabled and esp.gear) then
		return
	end
	local gear
	for _, kind in GEAR do
		local row, over = kind .. "Chams", kind .. "OverlayChams"
		if settings[row] or settings[over] then
			gear = gear or esp.gear()
			for holder, parts in gear[kind] do
				if settings[row] then
					painted[holder] = true
					paint(holder, parts, settings[row .. "Material"], settings[row .. "Color"], settings[row .. "Opacity"])
				end
				if settings[over] then
					shelled[holder] = true
					wrap(holder, parts, settings[over .. "Material"], settings[over .. "Color"], settings[over .. "Opacity"])
				end
			end
		end
	end
end

-- undoes every kind of chams, for the hub unloading
local function clearChams()
	for holder in skins do
		strip(holder)
	end
	prune(shades, {})
	prune(shells, {})
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
local function point(set, camera, viewport, center, settings, color)
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
	local settings = source.settings
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
	if source.real then
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
		point(set, camera, viewport, center, settings, own or settings.ArrowsColor)
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

	updateSkeleton(model, camera, settings, own or settings.SkeletonColor)
	updateChams(model, source)

	return true
end

-- a sound's mark fades where it was made: a circle of the radius in pixels, or as a ring one of that many units in the
-- world, growing as it goes
local function renderSounds(camera, viewport)
	local now = os.clock()
	for index = #sounds, 1, -1 do
		local sound = sounds[index]
		local settings = sound.settings
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
	local now = os.clock()
	renderSounds(camera, viewport)

	-- the models with drawings this frame, and those each kind of chams was on for
	local seen = {}
	local painted, shaded, shelled, trailed = {}, {}, {}, {}
	for _, source in all do
		local settings = source.settings
		if settings.Enabled and source.enabled then
			-- solid is the Highlight's fill; every other visible chams material goes on the models' own parts
			local material = settings.VisibleChams and settings.VisibleChamsMaterial ~= "solid" and settings.VisibleChamsMaterial
			for _, model in source.models(true) do
				seen[model] = true
				if source.real then
					if material then
						painted[model] = true
						paint(model, bodyParts(model), material, settings.VisibleChamsColor, settings.VisibleChamsOpacity)
					end
					if settings.InvisibleChams then
						shaded[model] = true
						shade(model, camera, settings)
					end
					if settings.OverlayChams then
						shelled[model] = true
						shell(model, settings)
					end
					if settings.BacktrackChams then
						trailed[model] = true
						-- the aim has the players' records, since they are its targets
						local records = esp.past[model]
						if source ~= players then
							records = remember(model, now)
						end
						trail(model, camera, settings, records)
					end
					-- main.lua reports the hits on the players
					if settings.HitChams and source ~= players then
						watch(model, source)
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
	renderGear(painted, shelled)
	renderFlashes()
	for holder in skins do
		if not painted[holder] then
			strip(holder)
		end
	end
	prune(shades, shaded)
	prune(shells, shelled)
	for model in trails do
		if not trailed[model] then
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
