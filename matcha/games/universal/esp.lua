local hub = ...

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(230, 60, 60)

local MAX_DISTANCE = 10000
local ARROW_SHADOW = 2
-- the camera is in first person when it is this close to the user's root
local FIRST_PERSON = 4
-- how far a ray is moved on past a part it looks through
local STEP_PAST = 0.05

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

-- Matcha documents no Color3:Lerp
local function lerp(from, to, fraction)
	return Color3.new(from.R + (to.R - from.R) * fraction, from.G + (to.G - from.G) * fraction, from.B + (to.B - from.B) * fraction)
end

-- every page of the players tab has its own copy of these. Matcha can't make a Highlight, so there are no chams, and
-- it has no way to draw an image from a Roblox asset, so no avatars
local function defaults()
	return {
		Enabled = false,
		OnlyVisible = false,
		Box = true,
		BoxColor = WHITE,
		Skeleton = false,
		SkeletonColor = WHITE,
		HealthBar = true,
		-- the bar's colour at full health; it runs to red as health drops
		HealthBarColor = GREEN,
		Name = true,
		NameColor = WHITE,
		WeaponName = false,
		WeaponNameColor = WHITE,
		Arrows = false,
		ArrowsColor = WHITE,
		ArrowsShadow = false,
		ArrowsShadowColor = BLACK,
		ArrowsSize = 12,
		ArrowsOffset = 24,
	}
end

local function teammate(player)
	local team = Players.LocalPlayer.Team
	return team ~= nil and player.Team == team
end

-- Matcha documents no GetPlayerFromCharacter: the owners of the characters last listed are kept here. Everything kept by
-- instance is kept by its Address, since Matcha doesn't say that the same instance is always the same object
local owners = {}

-- the characters of the other players who are, or aren't, on the user's team
local function others(mates)
	local characters = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if player ~= Players.LocalPlayer and teammate(player) == mates and character and character:FindFirstChild("HumanoidRootPart") then
			owners[character.Address] = player
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
				owners[character.Address] = Players.LocalPlayer
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
local arrows = {}
local NONE = {}

-- what the list page has set for the player a character belongs to
function esp.override(model)
	local player = owners[model.Address]
	return player and esp.overrides[player.Name] or NONE
end

-- whether the camera has a line to a point on a model. Matcha documents no RaycastParams, so a ray that hits the user's
-- own character, the camera's viewmodels or a part with nothing showing is moved on past it, up to a few in a row
function esp.visible(camera, point, model)
	local character = Players.LocalPlayer.Character
	local origin = camera.CFrame.Position
	for _ = 1, 8 do
		local direction = point - origin
		local hit = workspace:Raycast(origin, direction)
		if not hit then
			return true
		end
		local part = hit.Instance
		if part:IsDescendantOf(model) then
			return true
		end
		if not (part.Transparency >= 1 or part:IsDescendantOf(camera) or character and part:IsDescendantOf(character)) then
			return false
		end
		origin = hit.Position + direction.Unit * STEP_PAST
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

-- Matcha's docs name a text's size both Size and FontSize
local function text()
	return draw("Text", { Size = 13, FontSize = 13, Center = true, Outline = true })
end

local function createSet()
	return {
		boxOutline = draw("Square", { Thickness = 3, Color = BLACK }),
		box = draw("Square", { Thickness = 1 }),
		healthBack = draw("Square", { Filled = true, Color = BLACK }),
		health = draw("Square", { Filled = true }),
		name = text(),
		weapon = text(),
	}
end

local function hide(id)
	for _, object in sets[id] do
		object.Visible = false
	end
	for _, lines in { bones[id] or NONE, arrows[id] or NONE } do
		for _, line in lines do
			line.Visible = false
		end
	end
end

local function destroy(id)
	for _, object in sets[id] do
		object:Remove()
	end
	sets[id] = nil
	for _, kept in { bones, arrows } do
		if kept[id] then
			for _, line in kept[id] do
				line:Remove()
			end
			kept[id] = nil
		end
	end
end

local function updateSkeleton(model, id, settings)
	local lines = bones[id]
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
		bones[id] = lines
	end

	local map = model:FindFirstChild("UpperTorso") and BONES_R15 or BONES_R6
	for index, pair in map do
		local line = lines[index]
		if not line then
			line = draw("Line", { Thickness = 1 })
			lines[index] = line
		end
		local from, to = model:FindFirstChild(pair[1]), model:FindFirstChild(pair[2])
		local a, aOn = from and WorldToScreen(from.Position)
		local b, bOn = to and WorldToScreen(to.Position)
		local visible = a and b and aOn and bOn
		line.Visible = visible
		if visible then
			line.Color = settings.SkeletonColor
			line.From = a
			line.To = b
		end
	end
	for index = #map + 1, #lines do
		lines[index].Visible = false
	end
end

-- an arrow towards a model that is off the screen, its tip the offset in from the screen's edge. Matcha's triangles
-- have no documented fill, so it is three lines, and the shadow three more
local function point(id, camera, viewport, center, settings)
	local lines = arrows[id]
	if not lines then
		lines = {}
		for index = 1, 6 do
			lines[index] = draw("Line", { Thickness = 1 })
		end
		arrows[id] = lines
	end

	local offset = camera.CFrame:PointToObjectSpace(center)
	local dx, dy = offset.X, -offset.Y
	local length = math.sqrt(dx * dx + dy * dy)
	-- straight behind, it points down
	if length > 0.01 then
		dx, dy = dx / length, dy / length
	else
		dx, dy = 0, 1
	end
	local size = settings.ArrowsSize
	local edge = size + settings.ArrowsOffset
	local x = viewport.X / 2 + dx * (viewport.X / 2 - edge)
	local y = viewport.Y / 2 + dy * (viewport.Y / 2 - edge)
	local sx, sy = -dy * size / 2, dx * size / 2
	local corners = {
		{ x + dx * size, y + dy * size },
		{ x - sx, y - sy },
		{ x + sx, y + sy },
	}
	for index = 1, 3 do
		local from, to = corners[index], corners[index % 3 + 1]
		local line, shadow = lines[index], lines[index + 3]
		shadow.Visible = settings.ArrowsShadow
		shadow.Color = settings.ArrowsShadowColor
		shadow.From = Vector2.new(from[1] + ARROW_SHADOW, from[2] + ARROW_SHADOW)
		shadow.To = Vector2.new(to[1] + ARROW_SHADOW, to[2] + ARROW_SHADOW)
		line.Visible = true
		line.Color = settings.ArrowsColor
		line.From = Vector2.new(from[1], from[2])
		line.To = Vector2.new(to[1], to[2])
	end
end

local function update(model, id, settings, camera, viewport)
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

	local top, topOn = WorldToScreen(center + Vector3.new(0, up, 0))
	local bottom, bottomOn = WorldToScreen(center - Vector3.new(0, down, 0))
	local _, centerOn = WorldToScreen(center)
	local pointed = settings.Arrows and not centerOn
	if not pointed and not (topOn and bottomOn) then
		return false
	end

	-- drawings are only made for models that are in range, and on screen or pointed at
	local set = sets[id]
	if not set then
		set = createSet()
		sets[id] = set
	end

	if pointed then
		hide(id)
		point(id, camera, viewport, center, settings)
		return true
	end
	if arrows[id] then
		for _, line in arrows[id] do
			line.Visible = false
		end
	end

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
		set.health.Color = lerp(RED, settings.HealthBarColor, fraction)
		set.health.Position = Vector2.new(x - 6, y + height * (1 - fraction))
		set.health.Size = Vector2.new(2, height * fraction)
	end

	set.name.Visible = settings.Name
	-- a player the list page has as high priority has a red name, whatever colour is set
	set.name.Color = esp.override(model).priority and RED or settings.NameColor
	if settings.Name then
		-- Matcha documents no DisplayName
		set.name.Text = owners[id].Name
		set.name.Position = Vector2.new(x + width / 2, y - 16)
	end

	local tool = settings.WeaponName and model:FindFirstChildOfClass("Tool")
	set.weapon.Visible = tool and true or false
	if tool then
		set.weapon.Color = settings.WeaponNameColor
		set.weapon.Text = tool.Name
		set.weapon.Position = Vector2.new(x + width / 2, y + height + 2)
	end

	updateSkeleton(model, id, settings)

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
				if not esp.override(model).hidden then
					local id = model.Address
					seen[id] = true
					if not update(model, id, settings, camera, viewport) and sets[id] then
						hide(id)
					end
				end
			end
		end
	end

	-- models that despawned or whose page was switched off
	for id in sets do
		if not seen[id] then
			destroy(id)
		end
	end
end

function esp.start()
	hub.cleanup.add(function()
		for id in sets do
			destroy(id)
		end
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
