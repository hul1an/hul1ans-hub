local hub = ...

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(230, 60, 60)

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

local esp = {
	settings = {
		Enabled = false,
		Box = true,
		BoxColor = WHITE,
		Skeleton = false,
		SkeletonColor = WHITE,
		HealthBar = true,
		-- the bar's colour at full health; it runs to red as health drops
		HealthBarColor = GREEN,
		Name = true,
		NameColor = WHITE,
	},
	sources = {},
}

local settings = esp.settings
local sets = {}
local bones = {}

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
-- a source given a colour is drawn in it throughout; one without, the players, in each element's colour from the settings
function esp.addSource(name, color, models, label)
	local source = {
		name = name,
		enabled = true,
		color = color,
		maxDistance = 10000,
		tracers = false,
		tracerColor = color or WHITE,
		aim = false,
		models = models,
		label = label,
	}
	table.insert(esp.sources, source)
	return source
end

local players = esp.addSource("Players", nil, function(skipTeammates)
	local characters = {}
	local team = skipTeammates and Players.LocalPlayer.Team
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player.Character and not (team and player.Team == team) then
			table.insert(characters, player.Character)
		end
	end
	return characters
end, function(character)
	-- GetPlayerFromCharacter isn't documented, so the owner is found by scanning the player list
	for _, player in Players:GetPlayers() do
		if player.Character == character then
			return player.Name
		end
	end
	return character.Name
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
		tracer = draw("Line", { Thickness = 1 }),
		healthBack = draw("Square", { Filled = true, Color = BLACK }),
		health = draw("Square", { Filled = true }),
		name = draw("Text", { Size = 13, Center = true, Outline = true }),
		distance = draw("Text", { Size = 13, Center = true, Outline = true }),
	}
end

-- bones only exist for models that have a set
local function hide(model)
	for _, object in sets[model] do
		object.Visible = false
	end
	if bones[model] then
		for _, line in bones[model] do
			line.Visible = false
		end
	end
end

local function destroy(model)
	for _, object in sets[model] do
		object:Remove()
	end
	sets[model] = nil
	if bones[model] then
		for _, line in bones[model] do
			line:Remove()
		end
		bones[model] = nil
	end
end

local function updateSkeleton(model, color)
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
		local a, aOn = from and WorldToScreen(from.Position)
		local b, bOn = to and WorldToScreen(to.Position)
		local visible = a and b and aOn and bOn
		line.Visible = visible
		if visible then
			line.Color = color
			line.From = a
			line.To = b
		end
	end
	for index = #map + 1, #lines do
		lines[index].Visible = false
	end
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

	local top, topOn = WorldToScreen(center + Vector3.new(0, up, 0))
	local bottom, bottomOn = WorldToScreen(center - Vector3.new(0, down, 0))
	if not topOn or not bottomOn then
		return false
	end

	-- drawings are only made for models that are in range and on screen
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

	set.tracer.Visible = source.tracers
	set.tracer.Color = source.tracerColor
	set.tracer.From = Vector2.new(viewport.X / 2, viewport.Y)
	set.tracer.To = Vector2.new(x + width / 2, y + height)

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
	set.name.Color = own or settings.NameColor
	if settings.Name then
		set.name.Text = source.label(model)
		set.name.Position = Vector2.new(x + width / 2, y - 16)
	end

	set.distance.Visible = true
	set.distance.Color = own or settings.NameColor
	set.distance.Text = math.floor(distance) .. " studs"
	set.distance.Position = Vector2.new(x + width / 2, y + height + 2)

	updateSkeleton(model, own or settings.SkeletonColor)

	return true
end

local function render()
	if not settings.Enabled then
		for model in sets do
			hide(model)
		end
		return
	end

	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local seen = {}
	for _, source in esp.sources do
		if source.enabled then
			for _, model in source.models(true) do
				seen[model] = true
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
end

function esp.start()
	hub.cleanup.add(function()
		for model in sets do
			destroy(model)
		end
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
