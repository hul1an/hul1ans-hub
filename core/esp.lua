local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(230, 60, 60)
local HIGHLIGHT = Color3.new(1, 0, 0)

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
		TeamCheck = false,
		Box = true,
		Skeleton = false,
		Chams = false,
		HealthBar = true,
		Name = true,
		Distance = true,
	},
	sources = {},
}

local settings = esp.settings
local sets = {}
local bones = {}
local highlights = {}
local container

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

-- models(skipTeammates) returns the models to draw, label(model) their name text
function esp.addSource(name, color, models, label)
	local source = {
		name = name,
		enabled = true,
		color = color,
		maxDistance = 1000,
		tracers = false,
		aim = false,
		models = models,
		label = label,
	}
	table.insert(esp.sources, source)
	return source
end

-- esp.highlight is a model drawn in red instead of its source colour, set by the aim assist
local players = esp.addSource("Players", WHITE, function(skipTeammates)
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
		tracer = draw("Line", { Thickness = 1 }),
		healthBack = draw("Square", { Filled = true, Color = BLACK }),
		health = draw("Square", { Filled = true }),
		name = draw("Text", { Size = 13, Center = true, Outline = true }),
		distance = draw("Text", { Size = 13, Center = true, Outline = true }),
	}
end

-- bones and highlights only exist for models that have a set
local function hide(model)
	for _, object in sets[model] do
		object.Visible = false
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

local function updateChams(model, color)
	local highlight = highlights[model]
	if not settings.Chams then
		if highlight then
			highlight.Enabled = false
		end
		return
	end
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.6
		highlight.Adornee = model
		highlight.Parent = container
		highlights[model] = highlight
	end
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Enabled = true
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

	local top = camera:WorldToViewportPoint(center + Vector3.new(0, up, 0))
	local bottom = camera:WorldToViewportPoint(center - Vector3.new(0, down, 0))
	if top.Z <= 0 or bottom.Z <= 0 then
		return false
	end

	-- drawings are only made for models that are in range and in front of the camera
	local set = sets[model]
	if not set then
		set = createSet()
		sets[model] = set
	end

	local color = model == esp.highlight and HIGHLIGHT or source.color
	local height = math.abs(bottom.Y - top.Y)
	-- characters are about half as wide as they are tall
	local width = height / 2
	local x = top.X - width / 2
	local y = math.min(top.Y, bottom.Y)

	set.boxOutline.Visible = settings.Box
	set.boxOutline.Position = Vector2.new(x, y)
	set.boxOutline.Size = Vector2.new(width, height)
	set.box.Visible = settings.Box
	set.box.Color = color
	set.box.Position = Vector2.new(x, y)
	set.box.Size = Vector2.new(width, height)

	set.tracer.Visible = source.tracers
	set.tracer.Color = color
	set.tracer.From = Vector2.new(viewport.X / 2, viewport.Y)
	set.tracer.To = Vector2.new(x + width / 2, y + height)

	local showHealth = health ~= nil and settings.HealthBar
	set.healthBack.Visible = showHealth
	set.health.Visible = showHealth
	if showHealth then
		local fraction = math.clamp(health / maxHealth, 0, 1)
		set.healthBack.Position = Vector2.new(x - 7, y - 1)
		set.healthBack.Size = Vector2.new(4, height + 2)
		set.health.Color = RED:Lerp(GREEN, fraction)
		set.health.Position = Vector2.new(x - 6, y + height * (1 - fraction))
		set.health.Size = Vector2.new(2, height * fraction)
	end

	set.name.Visible = settings.Name
	set.name.Color = color
	if settings.Name then
		set.name.Text = source.label(model)
		set.name.Position = Vector2.new(x + width / 2, y - 16)
	end

	set.distance.Visible = settings.Distance
	set.distance.Color = color
	set.distance.Text = math.floor(distance) .. " studs"
	set.distance.Position = Vector2.new(x + width / 2, y + height + 2)

	updateSkeleton(model, camera, color)
	updateChams(model, color)

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
			for _, model in source.models(settings.TeamCheck) do
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
	container = hub.cleanup.add(Instance.new("Folder"))
	container.Parent = gethui()

	hub.cleanup.add(function()
		for model in sets do
			destroy(model)
		end
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
