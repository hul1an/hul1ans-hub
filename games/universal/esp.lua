local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(230, 60, 60)

local MAX_DISTANCE = 10000
local AVATAR_SIZE = 14
local ARROW_SHADOW = Vector2.new(2, 2)
-- the camera is in first person when it is this close to the user's root
local FIRST_PERSON = 4

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

-- every page of the players tab has its own copy of these. The chams rows are the enemies' page only: Roblox draws 31
-- Highlights, and a model shows one
local function defaults()
	return {
		Enabled = false,
		OnlyVisible = false,
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
		HealthBar = true,
		-- the bar's colour at full health; it runs to red as health drops
		HealthBarColor = GREEN,
		Name = true,
		NameColor = WHITE,
		Avatar = false,
		WeaponName = false,
		WeaponNameColor = WHITE,
		Arrows = false,
		ArrowsColor = WHITE,
		ArrowsShadow = false,
		ArrowsShadowColor = BLACK,
		ArrowsOutline = false,
		ArrowsOutlineColor = BLACK,
		ArrowsSize = 12,
		ArrowsOffset = 24,
	}
end

local function teammate(player)
	local team = Players.LocalPlayer.Team
	return team ~= nil and player.Team == team
end

-- the characters of the other players who are, or aren't, on the user's team
local function others(mates)
	local characters = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if player ~= Players.LocalPlayer and teammate(player) == mates and character and character:FindFirstChild("HumanoidRootPart") then
			table.insert(characters, character)
		end
	end
	return characters
end

local esp = {
	enemies = {
		settings = defaults(),
		models = function()
			return others(false)
		end,
	},
	teammates = {
		settings = defaults(),
		models = function()
			return others(true)
		end,
	},
	-- the user's own character, drawn while the camera is out of it
	own = {
		settings = defaults(),
		models = function()
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (workspace.CurrentCamera.CFrame.Position - root.Position).Magnitude > FIRST_PERSON then
				return { character }
			end
			return {}
		end,
	},
	-- by a player's name, what the players › list page has set for them: whitelist, priority, fov (degrees), reaction
	-- (milliseconds) and hidden
	overrides = {},
}

esp.teammate = teammate

local sets = {}
local bones = {}
local highlights = {}
-- by model, its avatar: an ImageLabel, since a Drawing image can't show a Roblox asset
local images = {}
local container, screen
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local NONE = {}

-- what the list page has set for the player a character belongs to
function esp.override(model)
	local player = Players:GetPlayerFromCharacter(model)
	return player and esp.overrides[player.Name] or NONE
end

-- whether the camera has a line to a point on a model
function esp.visible(camera, point, model)
	-- the camera is excluded because first person viewmodels are parented to it
	local ignore = { model, camera, Players.LocalPlayer.Character }
	local origin = camera.CFrame.Position
	-- fully invisible parts (clip walls) are looked through, up to a few in a row
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

-- health and max health of a model, or nil without a Humanoid
function esp.health(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health, humanoid.MaxHealth
	end
	return nil
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
		weapon = draw("Text", { Size = 13, Center = true, Outline = true }),
		arrowShadow = draw("Triangle", { Filled = true }),
		arrow = draw("Triangle", { Filled = true }),
		arrowOutline = draw("Triangle", { Thickness = 1 }),
	}
end

-- a model's avatar, shown at a place on screen; without an image it is hidden
local function picture(model, image, position)
	local label = images[model]
	if not image then
		if label then
			label.Visible = false
		end
		return
	end
	if not label then
		label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
		label.Parent = screen
		images[model] = label
	end
	label.Image = image
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Visible = true
end

-- bones, highlights and images only exist for models that have a set
local function hide(model)
	for _, object in sets[model] do
		object.Visible = false
	end
	if images[model] then
		images[model].Visible = false
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
		images[model]:Destroy()
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

local function updateSkeleton(model, camera, settings)
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
			line.Color = settings.SkeletonColor
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

-- invisible chams show through walls and so win over visible ones, which a Highlight can't have both of
local function updateChams(model, settings)
	if settings.InvisibleChams then
		local color, opacity = settings.InvisibleChamsColor, settings.InvisibleChamsOpacity
		if settings.InvisibleChamsMaterial == "solid" then
			light(model, color, opacity, nil, nil, true)
		else
			light(model, nil, nil, color, opacity)
		end
	elseif settings.VisibleChams then
		light(model, settings.VisibleChamsColor, settings.VisibleChamsOpacity)
	else
		light(model)
	end
end

-- an arrow towards a model that is off the screen, its tip the offset in from the screen's edge
local function point(set, camera, viewport, center, settings)
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
	fill.Color = settings.ArrowsColor
	fill.PointA, fill.PointB, fill.PointC = a, b, c
	outline.Visible = settings.ArrowsOutline
	outline.Color = settings.ArrowsOutlineColor
	outline.PointA, outline.PointB, outline.PointC = a, b, c
end

local function update(model, settings, camera, viewport)
	local health, maxHealth = esp.health(model)
	if health and health <= 0 then
		return false
	end

	-- head top and feet as multiples of the root's height, so scaled characters still fit
	local root = model.HumanoidRootPart
	local center, up, down = root.Position, root.Size.Y * 1.25, root.Size.Y * 1.5
	if (camera.CFrame.Position - center).Magnitude > MAX_DISTANCE then
		return false
	end

	if settings.OnlyVisible then
		local head = model:FindFirstChild("Head")
		if not esp.visible(camera, head and head.Position or center, model) then
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

	if pointed then
		hide(model)
		point(set, camera, viewport, center, settings)
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
	set.box.Color = settings.BoxColor
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

	local owner = Players:GetPlayerFromCharacter(model)
	set.name.Visible = settings.Name
	-- a player the list page has as high priority has a red name, whatever colour is set
	set.name.Color = esp.override(model).priority and RED or settings.NameColor
	if settings.Name then
		set.name.Text = owner and owner.DisplayName or model.Name
		set.name.Position = Vector2.new(x + width / 2, y - 16)
	end

	-- the avatar goes left of the name, or in its place
	local left = settings.Name and set.name.TextBounds.X / 2 + 2 + AVATAR_SIZE or AVATAR_SIZE / 2
	local avatar = settings.Avatar and owner and "rbxthumb://type=AvatarHeadShot&id=" .. owner.UserId .. "&w=48&h=48"
	picture(model, avatar, Vector2.new(x + width / 2 - left, y - 16))

	local tool = settings.WeaponName and model:FindFirstChildOfClass("Tool")
	set.weapon.Visible = tool and true or false
	if tool then
		set.weapon.Color = settings.WeaponNameColor
		set.weapon.Text = tool.Name
		set.weapon.Position = Vector2.new(x + width / 2, y + height + 2)
	end

	updateSkeleton(model, camera, settings)
	updateChams(model, settings)

	return true
end

local function render()
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize

	-- the models with drawings this frame
	local seen = {}
	for _, source in { esp.enemies, esp.teammates, esp.own } do
		local settings = source.settings
		if settings.Enabled then
			for _, model in source.models() do
				-- the list page's disable visuals: nothing is drawn of that player
				if esp.override(model).hidden then
					continue
				end
				seen[model] = true
				if not update(model, settings, camera, viewport) and sets[model] then
					hide(model)
				end
			end
		end
	end

	-- models that despawned or whose page was switched off
	for model in sets do
		if not seen[model] then
			destroy(model)
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
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
