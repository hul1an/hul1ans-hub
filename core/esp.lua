local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(230, 60, 60)

local esp = {
	settings = {
		Enabled = false,
		MaxDistance = 1000,
		Box = true,
		Tracers = false,
		HealthBar = true,
		Name = true,
		Distance = true,
	},
	sources = {},
}

local settings = esp.settings
local sets = {}

-- models() returns the models to draw, label(model) their name text
function esp.addSource(name, color, models, label)
	table.insert(esp.sources, { name = name, enabled = true, color = color, models = models, label = label })
end

esp.addSource("Players", WHITE, function()
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player.Character then
			table.insert(characters, player.Character)
		end
	end
	return characters
end, function(character)
	return Players:GetPlayerFromCharacter(character).DisplayName
end)

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

local function hide(set)
	for _, object in set do
		object.Visible = false
	end
end

local function destroy(set)
	for _, object in set do
		object:Remove()
	end
end

local function update(model, source, camera, viewport)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end

	local cframe, size = model:GetBoundingBox()
	local distance = (camera.CFrame.Position - cframe.Position).Magnitude
	if distance > settings.MaxDistance then
		return false
	end

	local top = camera:WorldToViewportPoint(cframe.Position + Vector3.new(0, size.Y / 2, 0))
	local bottom = camera:WorldToViewportPoint(cframe.Position - Vector3.new(0, size.Y / 2, 0))
	if top.Z <= 0 or bottom.Z <= 0 then
		return false
	end

	-- drawings are only made for models that are in range and in front of the camera
	local set = sets[model]
	if not set then
		set = createSet()
		sets[model] = set
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
	set.box.Color = source.color
	set.box.Position = Vector2.new(x, y)
	set.box.Size = Vector2.new(width, height)

	set.tracer.Visible = settings.Tracers
	set.tracer.Color = source.color
	set.tracer.From = Vector2.new(viewport.X / 2, viewport.Y)
	set.tracer.To = Vector2.new(x + width / 2, y + height)

	local showHealth = humanoid ~= nil and settings.HealthBar
	set.healthBack.Visible = showHealth
	set.health.Visible = showHealth
	if showHealth then
		local fraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		set.healthBack.Position = Vector2.new(x - 7, y - 1)
		set.healthBack.Size = Vector2.new(4, height + 2)
		set.health.Color = RED:Lerp(GREEN, fraction)
		set.health.Position = Vector2.new(x - 6, y + height * (1 - fraction))
		set.health.Size = Vector2.new(2, height * fraction)
	end

	set.name.Visible = settings.Name
	set.name.Color = source.color
	if settings.Name then
		set.name.Text = source.label(model)
		set.name.Position = Vector2.new(x + width / 2, y - 16)
	end

	set.distance.Visible = settings.Distance
	set.distance.Color = source.color
	set.distance.Text = math.floor(distance) .. " studs"
	set.distance.Position = Vector2.new(x + width / 2, y + height + 2)

	return true
end

local function render()
	if not settings.Enabled then
		for _, set in sets do
			hide(set)
		end
		return
	end

	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local seen = {}
	for _, source in esp.sources do
		if source.enabled then
			for _, model in source.models() do
				seen[model] = true
				if not update(model, source, camera, viewport) and sets[model] then
					hide(sets[model])
				end
			end
		end
	end

	-- models that despawned or whose source was switched off
	for model, set in sets do
		if not seen[model] then
			destroy(set)
			sets[model] = nil
		end
	end
end

function esp.start()
	hub.cleanup.add(function()
		for _, set in sets do
			destroy(set)
		end
		table.clear(sets)
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return esp
