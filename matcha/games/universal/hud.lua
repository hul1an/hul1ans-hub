local hub = ...

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local hud = {
	settings = {
		watermark = false,
		watermarkShow = { "username", "ping", "fps" },
		graph = false,
		graphColor = Color3.fromRGB(160, 183, 255),
		graphOpacity = 1,
		graphWidth = 320,
		graphHeight = 100,
		graphBack = 0.5,
	},
}
local settings = hud.settings

-- the menu's accent
local ACCENT = Color3.fromRGB(160, 183, 255)
-- seconds between the watermark's updates
local REFRESH = 0.1
-- the velocity graph: the speed along the ground, a sample every SAMPLE seconds and SPACING pixels, over a dark back,
-- with the speed now under it
local SAMPLE, SPACING = 1 / 30, 4
-- the least speed the graph's height stands for, in studs a second: a little over a sprint
local TOP = 50

local samples = {}
local lines = {}
local back, readout, mark
local sampled = 0

local function text()
	local object = Drawing.new("Text")
	object.Size = 13
	object.Outline = true
	return object
end

-- the watermark's line: the brand, then the chosen parts in starline's order. Matcha documents no DisplayName and no
-- os.date, so there is no time. fps is the frame rate over the last update
local function watermark(fps)
	local parts = {
		username = Players.LocalPlayer.Name,
		ping = string.format("%.0f ms", GetPingValue()),
		fps = string.format("%.0f fps", fps),
	}
	local line = "bloxline"
	for _, part in { "username", "ping", "fps" } do
		if table.find(settings.watermarkShow, part) then
			line ..= "  |  " .. parts[part]
		end
	end
	return line
end

local function groundSpeed()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
end

local function graph(dt)
	local shown = settings.graph
	back.Visible = shown
	readout.Visible = shown
	if not shown then
		for _, line in lines do
			line.Visible = false
		end
		return
	end

	local speed = groundSpeed()
	local count = math.floor(settings.graphWidth / SPACING) + 1
	sampled += dt
	if sampled >= SAMPLE then
		sampled = 0
		table.insert(samples, speed)
	end
	while #samples > count do
		table.remove(samples, 1)
	end

	local view = workspace.CurrentCamera.ViewportSize
	local width, height = settings.graphWidth, settings.graphHeight
	local left, bottom = (view.X - width) / 2, view.Y - 140
	back.Position = Vector2.new(left, bottom - height)
	back.Size = Vector2.new(width, height)
	back.Transparency = settings.graphBack

	local top = TOP
	for _, sample in samples do
		top = math.max(top, sample)
	end
	-- the newest sample is at the right edge
	local function point(index)
		return Vector2.new(left + width - (#samples - index) * SPACING, bottom - samples[index] / top * height)
	end
	for index = 1, math.max(#samples - 1, #lines) do
		local line = lines[index]
		if index < #samples then
			if not line then
				line = Drawing.new("Line")
				line.Thickness = 1
				lines[index] = line
			end
			line.From, line.To = point(index), point(index + 1)
			line.Color = settings.graphColor
			line.Transparency = settings.graphOpacity
			line.Visible = true
		else
			line.Visible = false
		end
	end

	readout.Text = string.format("%.0f", speed)
	readout.Position = Vector2.new(view.X / 2, bottom + 4)
end

function hud.start()
	back = Drawing.new("Square")
	back.Filled = true
	back.Color = Color3.new(0, 0, 0)
	readout = text()
	readout.Center = true
	readout.Color = Color3.new(1, 1, 1)
	mark = text()
	mark.Color = ACCENT
	mark.Position = Vector2.new(12, 12)

	local waited, frames = 0, 0
	hub.cleanup.add(RunService.RenderStepped:Connect(function(dt)
		graph(dt)

		waited += dt
		frames += 1
		if waited < REFRESH then
			return
		end
		local fps = frames / waited
		waited, frames = 0, 0

		mark.Visible = settings.watermark
		if settings.watermark then
			mark.Text = watermark(fps)
		end
	end))

	hub.cleanup.add(function()
		back:Remove()
		readout:Remove()
		mark:Remove()
		for _, line in lines do
			line:Remove()
		end
	end)
end

return hud
