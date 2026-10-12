local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local movement = hub.require("games/bloxstrike/movement.lua")

local hud = {
	settings = {
		watermark = false,
		watermarkShow = { "username", "ping", "fps" },
		keybinds = false,
		spectators = false,
		indicators = false,
		graph = false,
		graphColor = Color3.fromRGB(160, 183, 255),
		graphOpacity = 1,
		graphEvents = {},
		graphWidth = 320,
		graphHeight = 100,
		graphBack = 0.5,
	},
}
local settings = hud.settings

-- the menu's accent, as rich text takes a colour
local ACCENT = "#a0b7ff"
-- a Hammer unit in studs: speeds and lengths are shown in units, as starline's are
local UNIT = 0.075
-- seconds between the text widgets' updates, and how long an indicator stays lit after its feature did something
local REFRESH, LIT = 0.1, 0.25
-- the movement features in the order their indicators stand, each the setting it is on with and its tag
local INDICATORS = {
	{ "bunnyhop", "aj" },
	{ "edgeJump", "ej" },
	{ "longJump", "lj" },
	{ "nullBinds", "nb" },
	{ "autoStrafe", "as" },
	{ "quickStop", "qs" },
	{ "blockBot", "bb" },
}

local function tinted(text)
	return '<font color="' .. ACCENT .. '">' .. text .. "</font>"
end

-- the watermark's line: the brand, then the chosen parts in starline's order. fps is the frame rate over the last
-- update
local function watermark(fps)
	local player = Players.LocalPlayer
	local kills = player:GetAttribute("Kills") or 0
	local parts = {
		username = player.DisplayName,
		time = os.date("%H:%M"),
		ping = string.format("%.0f ms", player:GetAttribute("Ping") or 0),
		["k/d"] = string.format("%.2f k/d", kills / math.max(player:GetAttribute("Deaths") or 0, 1)),
		fps = string.format("%.0f fps", fps),
		["hs%"] = string.format("%.0f%% hs", (player:GetAttribute("Headshots") or 0) / math.max(kills, 1) * 100),
	}
	local line = tinted("bloxline")
	for _, part in { "username", "time", "ping", "k/d", "fps", "hs%" } do
		if table.find(settings.watermarkShow, part) then
			line ..= "  |  " .. parts[part]
		end
	end
	return line
end

-- everyone watching whoever the user is: the user alive, the one they watch dead
local function spectators()
	local player = Players.LocalPlayer
	local watched = player:GetAttribute("IsSpectating") and player:GetAttribute("SpectatingUserId") or player.UserId
	local lines = {}
	for _, other in Players:GetPlayers() do
		if other ~= player
			and other:GetAttribute("IsSpectating")
			and tostring(other:GetAttribute("SpectatingUserId")) == tostring(watched) then
			table.insert(lines, other.DisplayName)
		end
	end
	return lines
end

local function keybinds()
	local lines = {}
	for _, bind in hub.ui.binds() do
		table.insert(lines, { bind.name, "[" .. bind.key .. "]" })
	end
	return lines
end

-- the tags of the movement features that are on, lit while one is doing something
local function indicators()
	local now = os.clock()
	local tags = {}
	for _, feature in INDICATORS do
		if movement.settings[feature[1]] then
			local tag = feature[2]
			table.insert(tags, now - (movement.acted[tag] or 0) < LIT and tinted(tag) or tag)
		end
	end
	return table.concat(tags, "  ")
end

-- the velocity graph: the speed along the ground, a sample every SAMPLE seconds and SPACING pixels, over a dark back,
-- with the speed now under it and the chosen events over it for EVENT_TIME seconds
local SAMPLE, SPACING, EVENT_TIME = 1 / 30, 4, 3
-- the least speed the graph's height stands for, in units: a run with a knife out
local TOP = 300

local samples, events = {}, {}
local lines, texts = {}, {}
local back, readout
local sampled, seenLanding = 0, nil

local function text()
	local object = Drawing.new("Text")
	object.Size = 13
	object.Center = true
	object.Outline = true
	return object
end

local function event(words)
	table.insert(events, 1, { words = words, at = os.clock() })
	events[5] = nil
end

local function graph(dt)
	local shown = settings.graph
	back.Visible = shown
	readout.Visible = shown
	if not shown then
		for _, line in lines do
			line.Visible = false
		end
		for _, object in texts do
			object.Visible = false
		end
		-- a jump from before the graph was switched on is no event
		seenLanding = movement.landing
		return
	end

	local landing = movement.landing
	if landing ~= seenLanding then
		seenLanding = landing
		if table.find(settings.graphEvents, "landing speed") then
			event(string.format("landing %.0f", landing.speed / UNIT))
		end
		if landing.long and table.find(settings.graphEvents, "long jump") then
			event(string.format("long jump %.1f", landing.length / UNIT))
		elseif table.find(settings.graphEvents, "jump length") then
			event(string.format("jump %.1f", landing.length / UNIT))
		end
	end

	local velocity = movement.velocity
	local speed = math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2) / UNIT
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

	local now = os.clock()
	for index = 1, 4 do
		local shownEvent = events[index]
		local object = texts[index]
		local age = shownEvent and now - shownEvent.at
		if age and age < EVENT_TIME then
			object.Text = shownEvent.words
			object.Position = Vector2.new(view.X / 2, bottom - height - 4 - 15 * index)
			-- fades over its last second
			object.Transparency = math.min(EVENT_TIME - age, 1)
			object.Visible = true
		else
			object.Visible = false
		end
	end
end

function hud.start()
	local ui = hub.ui
	local mark = ui.createWidget(UDim2.new(1, -12, 0, 12))
	local binds = ui.createWidget(UDim2.new(0, 14, 0.4, 0), "keybinds", 150)
	local watchers = ui.createWidget(UDim2.new(1, -12, 0.4, 0), "spectators", 180)
	local tags = ui.createWidget(UDim2.new(0.5, 0, 0.75, 0))

	back = Drawing.new("Square")
	back.Filled = true
	back.Color = Color3.new()
	readout = text()
	readout.Color = Color3.new(1, 1, 1)
	for index = 1, 4 do
		texts[index] = text()
		texts[index].Color = Color3.new(1, 1, 1)
	end

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

		mark:Show(settings.watermark)
		if settings.watermark then
			mark:SetLines({ watermark(fps) })
		end

		-- an empty list is only there to be dragged, while the menu is showing
		local held = settings.keybinds and keybinds()
		binds:Show(held and (#held > 0 or ui.visible()))
		if held then
			binds:SetLines(held)
		end
		local watching = settings.spectators and spectators()
		watchers:Show(watching and (#watching > 0 or ui.visible()))
		if watching then
			watchers:SetLines(watching)
		end

		local line = settings.indicators and indicators()
		tags:Show(line and line ~= "")
		if line then
			tags:SetLines({ line })
		end
	end))

	hub.cleanup.add(function()
		back:Remove()
		readout:Remove()
		for _, list in { lines, texts } do
			for _, object in list do
				object:Remove()
			end
		end
	end)
end

return hud
