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
-- the visible chams materials that go on a model's own parts, glass see-through even at full opacity. Each takes the
-- part's Color
local MATERIALS = {
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

-- a model's Highlight: the glow is its outline, through walls, and the solid visible chams its fill
local function updateChams(model, source, color)
	local highlight = highlights[model]
	local solid = source == players and settings.VisibleChams and settings.VisibleChamsMaterial == "solid"
	if not (settings.Chams or solid) then
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
	-- a model shows one Highlight and that has one depth mode, so with the glow on a solid fill goes through walls too
	highlight.DepthMode = settings.Chams and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	highlight.FillColor = settings.VisibleChamsColor
	highlight.FillTransparency = solid and 1 - settings.VisibleChamsOpacity or 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = settings.Chams and 1 - settings.ChamsOpacity or 1
	highlight.Enabled = true
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
		skin = { parts = {}, taken = {}, decals = {} }
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
				-- the skin is a SurfaceAppearance, which covers the material while it is on the part; the face is decals
				for _, child in part:GetChildren() do
					if child:IsA("SurfaceAppearance") then
						skin.taken[child] = part
						child.Parent = nil
					elseif child:IsA("Decal") then
						skin.decals[child] = child.Transparency
						child.Transparency = 1
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
	for decal, transparency in skin.decals do
		decal.Transparency = transparency
	end
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
		for model in skins do
			strip(model)
		end
		return
	end

	-- solid is the Highlight's fill; every other visible chams material goes on the players' own parts
	local material = settings.VisibleChams and settings.VisibleChamsMaterial ~= "solid" and settings.VisibleChamsMaterial
	local seen = {}
	for _, source in esp.sources do
		if source.enabled then
			for _, model in source.models(true) do
				seen[model] = true
				if material and source == players then
					paint(model, material, settings.VisibleChamsColor, settings.VisibleChamsOpacity)
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
	for model in skins do
		if not (material and seen[model]) then
			strip(model)
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

	hub.cleanup.add(function()
		for model in sets do
			destroy(model)
		end
		for model in skins do
			strip(model)
		end
		for _, sound in sounds do
			sound.circle:Remove()
		end
		table.clear(sounds)
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
