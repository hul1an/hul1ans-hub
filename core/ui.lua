local hub = ...

local GuiService = cloneref(game:GetService("GuiService"))
local HttpService = cloneref(game:GetService("HttpService"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))

local config = hub.require("core/config.lua")

local TOGGLE_KEY = Enum.KeyCode.RightShift
local BRAND = "bloxline"
local ASSETS = "hul1ans-hub/assets"
-- not in the dump, picked by eye: hover and popup fade times, the open / close time, pixels per wheel notch
local HOVER_TIME = 0.12
local FADE_TIME = 0.1
local OPEN_TIME = 0.2
local WHEEL_STEP = 40

local ACCENT = Color3.fromRGB(160, 183, 255)
local ACCENT_DIM = Color3.fromRGB(125, 143, 200)
local ACCENT_DARK = Color3.fromRGB(96, 110, 153)
local BORDER = Color3.fromRGB(40, 40, 40)
local TEXT = Color3.fromRGB(216, 216, 216)
local MUTED = Color3.fromRGB(155, 155, 155)
local INK = Color3.fromRGB(13, 16, 32)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new()
local WINDOW = Color3.fromRGB(21, 21, 21)
local STRIP = Color3.fromRGB(20, 20, 20)
local CARD = Color3.fromRGB(25, 25, 25)
local PANEL = Color3.fromRGB(26, 26, 26)
local LIST = Color3.fromRGB(22, 22, 22)
local IDLE = Color3.fromRGB(35, 35, 35)
local CHIP = Color3.fromRGB(45, 45, 45)
local GUIDE = Color3.fromRGB(100, 115, 180)
local STATUS = { error = Color3.fromRGB(255, 107, 107), success = Color3.fromRGB(107, 255, 184) }

-- the text sizes the menu draws at
local LABEL, ROW, VALUE, TAB, TITLE, SMALL, KEY = 14, 12.73, 12.09, 11.45, 10.82, 10.18, 8.91

-- x, y, width, height on assets/icons.png, which is drawn at twice the size the icons are shown at
local ICONS = {
	crosshairs = { 2, 2, 28, 28 },
	users = { 34, 2, 28, 28 },
	eye = { 66, 2, 28, 28 },
	hanger = { 98, 2, 28, 28 },
	settings = { 130, 2, 28, 28 },
	code = { 162, 2, 28, 28 },
	search = { 194, 2, 28, 28 },
	save = { 2, 34, 28, 28 },
	folder = { 34, 34, 28, 28 },
	layers = { 66, 34, 28, 28 },
	music = { 98, 34, 28, 28 },
	branch = { 130, 34, 16, 24 },
	plus = { 162, 34, 28, 28 },
	revert = { 194, 34, 28, 28 },
	copy = { 2, 66, 28, 28 },
	check = { 34, 66, 24, 24 },
	x = { 66, 66, 16, 16 },
	["plus-small"] = { 98, 66, 24, 24 },
	["arrow-right"] = { 130, 66, 20, 20 },
	["combo-chev"] = { 162, 66, 14, 14 },
	["expand-chev"] = { 194, 66, 10, 14 },
}

for _, folder in { "hul1ans-hub", ASSETS } do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

-- fetched once, after that read from the executor workspace; a changed asset needs a new file name
local function asset(name)
	local path = ASSETS .. "/" .. name
	if not isfile(path) then
		writefile(path, hub.read("assets/" .. name))
	end
	return getcustomasset(path)
end

-- Roblox takes a custom font as a family file that points at the TTF
writefile(ASSETS .. "/GeistMono.json", HttpService:JSONEncode({
	name = "Geist Mono",
	faces = { { name = "Regular", weight = 400, style = "normal", assetId = asset("GeistMono-Medium.ttf") } },
}))
local FONT = Font.new(getcustomasset(ASSETS .. "/GeistMono.json"))
local SHEET = asset("icons.png")

local function make(class, ...)
	local instance = Instance.new(class)
	for _, properties in { ... } do
		for name, value in properties do
			instance[name] = value
		end
	end
	return instance
end

local function frame(properties)
	return make("Frame", { BorderSizePixel = 0 }, properties)
end

local function label(size, properties)
	return make("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextSize = size,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, properties)
end

-- a click target with nothing drawn unless the properties say so
local function button(properties)
	return make("TextButton", { BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, properties)
end

local function icon(name, properties)
	local cell = ICONS[name]
	return make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = SHEET,
		ImageRectOffset = Vector2.new(cell[1], cell[2]),
		ImageRectSize = Vector2.new(cell[3], cell[4]),
		Size = UDim2.fromOffset(cell[3] / 2, cell[4] / 2),
	}, properties)
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- a 1 px border just inside the parent's edge; UIStroke draws outside its frame, so that frame is inset
local function outline(parent, color, radius)
	local inset = frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 5,
		Parent = parent,
	})
	corner(inset, radius - 1)
	return make("UIStroke", { Color = color, Parent = inset })
end

-- a 1 px line that fades in from both ends and peaks in the accent at the middle
local function hairline(parent, y, edge)
	local line = frame({ BackgroundColor3 = WHITE, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), Parent = parent })
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, BORDER),
			ColorSequenceKeypoint.new(edge, BORDER),
			ColorSequenceKeypoint.new(0.5, ACCENT_DIM),
			ColorSequenceKeypoint.new(1 - edge, BORDER),
			ColorSequenceKeypoint.new(1, BORDER),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(edge, 0),
			NumberSequenceKeypoint.new(1 - edge, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = line,
	})
end

local function linear(t)
	return t
end

local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- a CSS cubic-bezier timing curve: solves the x curve for t, then reads the y curve there
local function bezier(x1, y1, x2, y2)
	return function(x)
		local t = x
		for _ = 1, 5 do
			local u = 1 - t
			local slope = 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
			if slope < 1e-4 then
				break
			end
			t -= (3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t - x) / slope
		end
		local u = 1 - t
		return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
	end
end

local EASE = bezier(0.25, 0.1, 0.25, 1)
local EASE_OUT = bezier(0, 0, 0.58, 1)

local running = {}

-- a value that runs to its target over `seconds` along `curve`, restarting from where it is when the target changes
local function tween(seconds, curve, apply, value)
	local state = { seconds = seconds, curve = curve, apply = apply, value = value or 0 }
	state.target = state.value
	apply(state.value)
	return function(target)
		if target ~= state.target then
			state.from, state.target, state.elapsed = state.value, target, 0
			running[state] = true
		end
	end
end

local function hover(target, apply, seconds, curve)
	local set = tween(seconds or HOVER_TIME, curve or linear, apply)
	target.MouseEnter:Connect(function()
		set(1)
	end)
	target.MouseLeave:Connect(function()
		set(0)
	end)
end

local ui = {}
local visible = true
-- the sub-tab on show, the function fed the mouse while the left button is held, and the open popup
local page, dragging, popup, popupClosed

local screen = hub.cleanup.add(make("ScreenGui", {
	Name = HttpService:GenerateGUID(false),
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = gethui(),
}))
local zoom = Instance.new("UIScale")

-- AbsolutePosition and offsets under the ScreenGui leave out the top bar inset, the mouse location doesn't
local function mouse()
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

-- while the left button is held on target, reports where the mouse is across area, 0 to 1 on each axis
local function slide(target, area, moved)
	target.MouseButton1Down:Connect(function()
		dragging = function(position)
			local across = (position - area.AbsolutePosition) / area.AbsoluteSize
			moved(math.clamp(across.X, 0, 1), math.clamp(across.Y, 0, 1))
		end
		dragging(mouse())
	end)
end

hub.cleanup.add(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
		dragging(mouse())
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and page and visible and not popup then
		local at = mouse() - page.view.AbsolutePosition
		local size = page.view.AbsoluteSize
		if at.X >= 0 and at.Y >= 0 and at.X < size.X and at.Y < size.Y then
			page.target -= input.Position.Z * WHEEL_STEP
		end
	end
end))

hub.cleanup.add(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = nil
	end
end))

hub.cleanup.add(RunService.RenderStepped:Connect(function(dt)
	for state in running do
		state.elapsed = math.min(state.elapsed + dt / state.seconds, 1)
		state.value = state.from + (state.target - state.from) * state.curve(state.elapsed)
		state.apply(state.value)
		if state.elapsed == 1 then
			running[state] = nil
		end
	end
	if page then
		page:scroll(dt)
	end
end))

-- a full-screen click target under the popups, so a click anywhere else closes the open one
local catcher = button({ Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = screen })

local function closePopup()
	if popup then
		local closed = popupClosed
		popup.Visible = false
		popup, popupClosed = nil, nil
		catcher.Visible = false
		if closed then
			closed()
		end
	end
end
catcher.MouseButton1Down:Connect(closePopup)

local function panel(color, radius)
	local group = make("CanvasGroup", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ZIndex = 6,
		Parent = screen,
	})
	corner(group, radius)
	outline(group, BORDER, radius)
	return group
end

local function openPopup(group, x, y, closed)
	closePopup()
	popup, popupClosed = group, closed
	local limit = screen.AbsoluteSize - Vector2.new(group.Size.X.Offset, group.Size.Y.Offset)
	group.Position = UDim2.fromOffset(math.clamp(x, 0, limit.X), math.clamp(y, 0, limit.Y))
	group.Visible = true
	catcher.Visible = true
	tween(FADE_TIME, EASE_OUT, function(alpha)
		group.GroupTransparency = 1 - alpha
	end)(1)
end

local function scroller(properties)
	local list = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = MUTED,
		ScrollBarImageTransparency = 0.67,
	}, properties)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	return list
end

-- a text box on the menu's field background
local function field(parent, position, size, placeholder)
	local back = frame({ BackgroundColor3 = WHITE, Position = position, Size = size, Parent = parent })
	corner(back, 2)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(CHIP, IDLE), Parent = back })
	local border = outline(back, BORDER, 2)
	local box = make("TextBox", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextSize = VALUE,
		TextColor3 = TEXT,
		PlaceholderColor3 = MUTED,
		PlaceholderText = placeholder,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Parent = back,
	})
	box.Focused:Connect(function()
		border.Color = ACCENT_DIM
	end)
	box.FocusLost:Connect(function()
		border.Color = BORDER
	end)
	return box
end

local tip = frame({ BackgroundColor3 = WINDOW, AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 8, Parent = screen })
corner(tip, 3)
make("UIStroke", { Color = BORDER, Parent = tip })
make("UIPadding", {
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	Parent = tip,
})
local tipText = label(SMALL, { TextColor3 = MUTED, AutomaticSize = Enum.AutomaticSize.XY, Parent = tip })
local tipTurn = 0

local toasts = frame({
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(260, 0),
	ZIndex = 9,
	Parent = screen,
})
make("UIListLayout", { Padding = UDim.new(0, 6), Parent = toasts })

-- kind is "error", "success" or nothing
function ui.notify(text, kind)
	local toast = frame({
		BackgroundColor3 = WINDOW,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toasts,
	})
	corner(toast, 3)
	make("UIStroke", { Color = BORDER, Parent = toast })
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 21),
		PaddingRight = UDim.new(0, 9),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = toast,
	})
	corner(frame({
		BackgroundColor3 = STATUS[kind] or ACCENT,
		Position = UDim2.fromOffset(-12, 4),
		Size = UDim2.fromOffset(5, 5),
		Parent = toast,
	}), 3)
	label(VALUE, {
		Text = text,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toast,
	})
	task.delay(5, toast.Destroy, toast)
end

-- one colour picker shared by every swatch: hue, saturation and value of the colour being edited
local picker = panel(PANEL, 3)
picker.Size = UDim2.fromOffset(186, 192)
local hue, saturation, brightness, picked = 0, 0, 1, nil

local square = frame({ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(150, 150), Parent = picker })
corner(square, 2)
outline(square, BORDER, 2)
-- white fading out to the right and black fading in downwards, over the pure hue
local whiten = frame({ BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), Parent = square })
corner(whiten, 2)
make("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = whiten })
local darken = frame({ BackgroundColor3 = BLACK, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = square })
corner(darken, 2)
make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = darken })
local cursor = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), ZIndex = 6, Parent = square })
corner(cursor, 4)
make("UIStroke", { Color = WHITE, Parent = cursor })
local ring = frame({
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(10, 10),
	Parent = cursor,
})
corner(ring, 5)
make("UIStroke", { Color = BLACK, Transparency = 0.49, Parent = ring })

local rainbow = frame({ BackgroundColor3 = WHITE, Position = UDim2.fromOffset(166, 8), Size = UDim2.fromOffset(12, 150), Parent = picker })
corner(rainbow, 2)
outline(rainbow, BORDER, 2)
local stops = {}
for index = 0, 6 do
	stops[index + 1] = ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6, 1, 1))
end
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(stops), Parent = rainbow })
local handle = frame({
	BackgroundColor3 = Color3.fromRGB(30, 30, 30),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.new(1, 4, 0, 5),
	ZIndex = 6,
	Parent = rainbow,
})
make("UIStroke", { Color = WHITE, Transparency = 0.72, Parent = handle })

local hex = field(picker, UDim2.fromOffset(8, 166), UDim2.fromOffset(148, 18), "hex")
local copy = button({
	BackgroundColor3 = CHIP,
	BackgroundTransparency = 0,
	Position = UDim2.fromOffset(160, 166),
	Size = UDim2.fromOffset(18, 18),
	Parent = picker,
})
corner(copy, 2)
icon("copy", {
	ImageColor3 = MUTED,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(10, 10),
	Parent = copy,
})

local function showPicked(report)
	local color = Color3.fromHSV(hue, saturation, brightness)
	square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
	cursor.Position = UDim2.fromScale(saturation, 1 - brightness)
	cursor.BackgroundColor3 = color
	handle.Position = UDim2.fromScale(0.5, hue)
	hex.Text = color:ToHex()
	if report then
		picked(color)
	end
end

slide(button({ Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = square }), square, function(x, y)
	saturation, brightness = x, 1 - y
	showPicked(true)
end)
slide(button({ Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = rainbow }), rainbow, function(_, y)
	hue = y
	showPicked(true)
end)
hex.FocusLost:Connect(function()
	local digits = hex.Text:match("^#?(%x%x%x%x%x%x)$")
	if digits then
		hue, saturation, brightness = Color3.fromHex(digits):ToHSV()
	end
	showPicked(digits ~= nil)
end)
copy.MouseButton1Click:Connect(function()
	setclipboard(hex.Text)
end)

local function pickColor(anchor, color, changed)
	hue, saturation, brightness = color:ToHSV()
	picked = changed
	showPicked(false)
	openPopup(picker, anchor.AbsolutePosition.X + 20, anchor.AbsolutePosition.Y)
end

local Control = {}
Control.__index = Control

function Control:AddToolTip(text)
	local turn
	self.row.MouseEnter:Connect(function()
		tipTurn += 1
		turn = tipTurn
		task.delay(0.4, function()
			if turn == tipTurn then
				local at = mouse()
				tipText.Text = text
				tip.Position = UDim2.fromOffset(at.X + 14, at.Y + 18)
				tip.Visible = true
			end
		end)
	end)
	-- another row's enter can arrive before this row's leave
	self.row.MouseLeave:Connect(function()
		if turn == tipTurn then
			tipTurn += 1
			tip.Visible = false
		end
	end)
end

-- sections and groups: a stack of rows
local Container = {}
Container.__index = Container

function Container:row(height)
	self.rows += 1
	if self.column then
		self.column.height += height
	end
	return button({ Size = UDim2.new(1, 0, 0, height), LayoutOrder = self.rows, Parent = self.holder })
end

-- listed for search by name, and for configs when it has a value to get and set
function Container:register(name, row, get, set)
	local entry = { key = self.path .. "/" .. name, name = name:lower(), row = row, page = self.page, get = get, set = set }
	table.insert(self.window.controls, entry)
	return entry
end

-- the faint white a row gets under the mouse; strength is its alpha out of 255
local function wash(row, strength)
	local fill = frame({ BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = row })
	corner(fill, 2)
	hover(row, function(amount)
		fill.BackgroundTransparency = 1 - amount * strength / 255
	end)
end

function Container:CreateLabel(text)
	local row = self:row(22)
	label(VALUE, {
		Text = text,
		TextColor3 = MUTED,
		TextTransparency = 0.35,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	return setmetatable({ row = row }, Control)
end

function Container:CreateButton(name, callback)
	local row = self:row(24)
	local face = frame({ BackgroundColor3 = WHITE, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 20), Parent = row })
	corner(face, 2)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(IDLE, LIST), Parent = face })
	local border = outline(face, BORDER, 2)
	label(ROW, {
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
	hover(row, function(amount)
		border.Color = BORDER:Lerp(ACCENT_DIM, amount)
	end, 0.1, EASE)
	row.MouseButton1Click:Connect(function()
		callback()
	end)

	local controls = self.window.controls
	local entry = self:register(name, row)
	local control = setmetatable({ row = row }, Control)
	function control:Remove()
		table.remove(controls, table.find(controls, entry))
		row:Destroy()
	end
	return control
end

-- the tick's three points inside the 13 px box
local TICK = { Vector2.new(2.96, 6.21), Vector2.new(5.79, 9.04), Vector2.new(10.04, 4.79) }

-- lays a 1.5 px bar from a to b
local function stretch(bar, a, b)
	local across = b - a
	bar.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	bar.Size = UDim2.fromOffset(across.Magnitude, 1.5)
	bar.Rotation = math.deg(math.atan2(across.Y, across.X))
end

function Container:CreateToggle(name, default, callback)
	local row = self:row(22)
	wash(row, 6.375)
	label(LABEL, { Text = name, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -17, 1, 0), Parent = row })
	local box = frame({
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(13, 13),
		Parent = row,
	})
	corner(box, 2)
	local fill = make("UIGradient", { Rotation = 90, Parent = box })
	local border = outline(box, BORDER, 2)
	local down = frame({ BackgroundColor3 = INK, AnchorPoint = Vector2.new(0.5, 0.5), Parent = box })
	local up = frame({ BackgroundColor3 = INK, AnchorPoint = Vector2.new(0.5, 0.5), Parent = box })

	local state = default or false
	local checked, hovered = 0, 0
	local function paint()
		fill.Color = ColorSequence.new(IDLE:Lerp(ACCENT, checked), LIST:Lerp(ACCENT_DARK, checked))
		border.Color = checked > 0.01 and ACCENT_DIM or BORDER:Lerp(ACCENT_DIM, hovered)
		-- the tick is drawn on: its first stroke over the first half, the second over the rest
		stretch(down, TICK[1], TICK[1]:Lerp(TICK[2], math.min(checked * 2, 1)))
		stretch(up, TICK[2], TICK[2]:Lerp(TICK[3], math.max(checked * 2 - 1, 0)))
		down.BackgroundTransparency = 1 - checked
		up.BackgroundTransparency = 1 - checked
	end
	local check = tween(0.1, EASE, function(amount)
		checked = amount
		paint()
	end, state and 1 or 0)
	hover(row, function(amount)
		hovered = amount
		paint()
	end, 0.1, EASE)

	local function set(value)
		state = value
		check(value and 1 or 0)
		callback(value)
	end
	row.MouseButton1Click:Connect(function()
		set(not state)
	end)

	local container = self
	local toggle = setmetatable({ row = row }, Control)

	-- bind is a KeyCode name or "NONE"; pressed, if given, is called with it after the toggle flips
	function toggle:CreateKeybind(bind, pressed)
		local key = bind
		local waiting = false
		local chip = button({
			BackgroundColor3 = CHIP,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -17, 0, 4),
			Size = UDim2.fromOffset(0, 13),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = FONT,
			TextSize = KEY,
			Parent = row,
		})
		corner(chip, 2)
		make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = chip })

		local function show()
			chip.Text = waiting and "..." or key:lower()
			chip.TextColor3 = waiting and ACCENT or MUTED
		end
		show()
		chip.MouseButton1Click:Connect(function()
			waiting = true
			show()
		end)
		hub.cleanup.add(UserInputService.InputBegan:Connect(function(input, processed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if waiting then
				waiting = false
				-- escape and backspace clear the bind
				local clear = input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace
				key = clear and "NONE" or input.KeyCode.Name
				show()
			elseif not processed and input.KeyCode.Name == key then
				set(not state)
				if pressed then
					pressed(key)
				end
			end
		end))

		table.insert(container.window.controls, {
			key = container.path .. "/" .. name .. " bind",
			get = function()
				return key
			end,
			set = function(value)
				key = value
				show()
			end,
		})
	end

	self:register(name, row, function()
		return state
	end, set)
	return toggle
end

-- precise means whole numbers, as it did in Bracket; format is a string.format pattern for the readout
function Container:CreateSlider(name, min, max, default, precise, callback, format)
	format = format or (precise and "%.0f" or "%.2f")
	local row = self:row(30)
	wash(row, 6.375)
	label(LABEL, { Text = name, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 14), Parent = row })
	local readout = label(VALUE, {
		TextColor3 = MUTED,
		TextTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = row,
	})
	local track = frame({
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.92,
		Position = UDim2.fromOffset(0, 21),
		Size = UDim2.new(1, 0, 0, 4),
		Parent = row,
	})
	corner(track, 2)
	-- the fill is the whole track cut off at the value, so its end stays square until the slider is full
	local fill = frame({ BackgroundColor3 = ACCENT, BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Parent = track })
	corner(fill, 2)
	local cut = make("UIGradient", { Parent = fill })

	local value = default
	local function show()
		local amount = (value - min) / (max - min)
		if amount > 0.998 then
			cut.Transparency = NumberSequence.new(0)
		elseif amount < 0.001 then
			cut.Transparency = NumberSequence.new(1)
		else
			cut.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(amount, 0),
				NumberSequenceKeypoint.new(amount + 0.001, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
		readout.Text = string.format(format, value)
	end
	show()

	local function set(number)
		if number ~= value then
			value = number
			show()
			callback(number)
		end
	end
	slide(row, track, function(across)
		local raw = min + (max - min) * across
		set(precise and math.round(raw) or math.round(raw * 100) / 100)
	end)

	self:register(name, row, function()
		return value
	end, set)
	return setmetatable({ row = row }, Control)
end

-- with multi the callback gets the list of chosen names, otherwise the one name
local function dropdown(self, name, options, callback, initial, multi)
	local row = self:row(22)
	wash(row, 4.59)
	label(LABEL, { Text = name, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(0.5, -4, 1, 0), Parent = row })
	local chip = frame({
		BackgroundColor3 = CHIP,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 3),
		Size = UDim2.new(0.5, 0, 0, 16),
		Parent = row,
	})
	corner(chip, 2)
	local shown = label(VALUE, {
		TextColor3 = MUTED,
		TextTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(5, 0),
		Size = UDim2.new(1, -21, 1, 0),
		Parent = chip,
	})
	icon("combo-chev", {
		ImageColor3 = MUTED,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
		Parent = chip,
	})

	local lit, opened = 0, false
	local function paintChip()
		chip.BackgroundTransparency = opened and 0 or 1 - lit
	end
	hover(row, function(amount)
		lit = amount
		paintChip()
	end)

	local list = panel(LIST, 2)
	local holder = scroller({ Position = UDim2.fromOffset(1, 3), Size = UDim2.new(1, -2, 1, -6), Parent = list })
	local empty = label(SMALL, {
		Text = "no options",
		TextColor3 = MUTED,
		TextTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = list,
	})

	local selected = initial
	if multi then
		selected = {}
		for _, option in initial or {} do
			selected[option] = true
		end
	end
	local items = {}

	local function chosen()
		local names = {}
		for _, item in items do
			if selected[item.name] then
				table.insert(names, item.name)
			end
		end
		return names
	end

	local function refresh()
		for _, item in items do
			item.paint()
		end
		if multi then
			local names = chosen()
			shown.Text = #names > 0 and table.concat(names, ", ") or "none"
		else
			shown.Text = selected or "none"
		end
		empty.Visible = #items == 0
	end

	local function set(value)
		if multi then
			selected = {}
			for _, option in value do
				selected[option] = true
			end
			refresh()
			callback(chosen())
		else
			selected = value
			refresh()
			callback(value)
		end
	end

	local function add(option)
		local item = button({ BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 17), LayoutOrder = #items + 1, Parent = holder })
		local mark = frame({ BackgroundColor3 = ACCENT, BackgroundTransparency = 0.875, Size = UDim2.fromScale(1, 1), Parent = item })
		corner(mark, 2)
		outline(mark, ACCENT_DIM, 2).Transparency = 0.67
		local caption = label(ROW, {
			Text = option,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -12, 1, 0),
			Parent = item,
		})
		item.MouseEnter:Connect(function()
			item.BackgroundTransparency = 0.92
		end)
		item.MouseLeave:Connect(function()
			item.BackgroundTransparency = 1
		end)
		item.MouseButton1Click:Connect(function()
			if multi then
				selected[option] = not selected[option] or nil
				refresh()
				callback(chosen())
			else
				closePopup()
				set(option)
			end
		end)
		table.insert(items, {
			name = option,
			button = item,
			paint = function()
				local on = if multi then selected[option] else selected == option
				mark.Visible = on == true
				caption.TextColor3 = on and TEXT or MUTED
			end,
		})
	end

	for _, option in options do
		add(option)
	end
	refresh()

	row.MouseButton1Click:Connect(function()
		list.Size = UDim2.fromOffset(row.AbsoluteSize.X, 6 + 17 * math.clamp(#items, 1, 8))
		opened = true
		paintChip()
		openPopup(list, row.AbsolutePosition.X, row.AbsolutePosition.Y + 23, function()
			opened = false
			paintChip()
		end)
	end)

	local control = setmetatable({ row = row }, Control)
	function control:AddOption(option)
		add(option)
		refresh()
	end
	function control:ClearOptions()
		for _, item in items do
			item.button:Destroy()
		end
		table.clear(items)
		refresh()
	end
	self:register(name, row, function()
		return if multi then chosen() else selected
	end, set)
	return control
end

function Container:CreateDropdown(name, options, callback, initial)
	return dropdown(self, name, options, callback, initial, false)
end

function Container:CreateMultiDropdown(name, options, callback, initial)
	return dropdown(self, name, options, callback, initial, true)
end

function Container:CreateColorpicker(name, callback)
	local row = self:row(22)
	wash(row, 6.375)
	label(LABEL, { Text = name, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -17, 1, 0), Parent = row })
	local swatch = frame({
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(13, 13),
		Parent = row,
	})
	corner(swatch, 2)
	local border = outline(swatch, BORDER, 2)
	hover(row, function(amount)
		border.Color = BORDER:Lerp(ACCENT_DIM, amount)
	end, 0.1, EASE)

	local color = WHITE
	local function set(value)
		color = value
		swatch.BackgroundColor3 = value
		callback(value)
	end
	row.MouseButton1Click:Connect(function()
		pickColor(swatch, color, set)
	end)

	local control = setmetatable({ row = row }, Control)
	function control:UpdateColor(value)
		set(value)
	end
	self:register(name, row, function()
		return color:ToHex()
	end, function(value)
		set(Color3.fromHex(value))
	end)
	return control
end

-- the callback gets the text when the box loses focus
function Container:CreateTextBox(name, placeholder, numbersOnly, callback)
	local row = self:row(36)
	label(LABEL, { Text = name, Size = UDim2.new(1, 0, 0, 14), Parent = row })
	local box = field(row, UDim2.fromOffset(0, 18), UDim2.new(1, 0, 0, 18), placeholder)
	if numbersOnly then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			box.Text = box.Text:gsub("%D+", "")
		end)
	end
	box.FocusLost:Connect(function()
		callback(box.Text)
	end)
	self:register(name, row, function()
		return box.Text
	end, function(value)
		box.Text = value
		callback(value)
	end)
	return setmetatable({ row = row }, Control)
end

-- a row that folds out its own indented rows; with a callback the row is also a toggle
function Container:CreateGroup(name, default, callback)
	local row
	if callback then
		row = self:CreateToggle(name, default, callback).row
	else
		row = self:row(22)
		wash(row, 6.375)
		label(LABEL, { Text = name, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -17, 1, 0), Parent = row })
		self:register(name, row)
	end
	local chip = button({
		BackgroundColor3 = CHIP,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, callback and -17 or 0, 0, 4),
		Size = UDim2.fromOffset(13, 13),
		ZIndex = 2,
		Parent = row,
	})
	corner(chip, 2)
	local chevron = icon("expand-chev", {
		ImageColor3 = MUTED,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = chip,
	})
	hover(chip, function(amount)
		chip.BackgroundTransparency = 1 - amount
	end)

	self.rows += 1
	local body = frame({
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = self.rows,
		Parent = self.holder,
	})
	frame({
		BackgroundColor3 = GUIDE,
		BackgroundTransparency = 0.7,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(0, 1, 1, -3),
		Parent = body,
	})
	local holder = frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 0, 0), Parent = body })
	local layout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })

	local unfolded = 0
	local function resize()
		body.Size = UDim2.new(1, 0, 0, math.round(unfolded * (layout.AbsoluteContentSize.Y / zoom.Scale + 3)))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
	local unfold = tween(1 / 5.5, smooth, function(amount)
		unfolded = amount
		chevron.Rotation = 90 * amount
		resize()
	end)
	local open = false
	local function flip()
		open = not open
		unfold(open and 1 or 0)
	end
	chip.MouseButton1Click:Connect(flip)
	if not callback then
		row.MouseButton1Click:Connect(flip)
	end

	return setmetatable({
		window = self.window,
		page = self.page,
		path = self.path .. "/" .. name,
		holder = holder,
		rows = 0,
	}, Container)
end

local SubTab = {}
SubTab.__index = SubTab

-- side is "LeftSide" or "RightSide"; without it the section goes to the shorter column
function SubTab:CreateSection(name, side)
	local column = side == "LeftSide" and self.left
		or side == "RightSide" and self.right
		or (self.left.height <= self.right.height and self.left or self.right)
	column.cards += 1
	column.height += 27

	local card = frame({
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.04,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = column.cards,
		Parent = column.holder,
	})
	corner(card, 3)
	outline(card, BORDER, 3)
	corner(frame({ BackgroundColor3 = WINDOW, Size = UDim2.new(1, 0, 0, 22), Parent = card }), 3)
	-- squares off the header's bottom corners once the card has rows under it
	local square = frame({
		BackgroundColor3 = WINDOW,
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 3),
		Visible = false,
		Parent = card,
	})
	local rule = frame({
		BackgroundColor3 = BORDER,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 1),
		Visible = false,
		Parent = card,
	})
	label(TITLE, {
		Text = name,
		TextColor3 = MUTED,
		TextTransparency = 0.5,
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -18, 0, 22),
		Parent = card,
	})

	local holder = frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(9, 22), Size = UDim2.new(1, -18, 0, 0), Parent = card })
	local layout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local height = math.round(layout.AbsoluteContentSize.Y / zoom.Scale)
		card.Size = UDim2.new(1, 0, 0, 22 + height)
		square.Visible = height > 0
		rule.Visible = height > 0
	end)

	return setmetatable({
		window = self.window,
		page = self,
		column = column,
		path = self.path .. "/" .. name,
		holder = holder,
		rows = 0,
	}, Container)
end

function SubTab:scroll(dt)
	local height = math.max(self.left.layout.AbsoluteContentSize.Y, self.right.layout.AbsoluteContentSize.Y) + 12
	local limit = math.max(0, height - self.view.AbsoluteSize.Y)
	self.target = math.clamp(self.target, 0, limit)
	-- 0.28 of the distance left per frame at 60 fps
	self.position += (self.target - self.position) * (1 - 0.72 ^ (dt * 60))
	self.content.Position = UDim2.fromOffset(0, -math.round(self.position))
	self.top.BackgroundTransparency = 1 - math.clamp(self.position / 6, 0, 1)
	self.bottom.BackgroundTransparency = 1 - math.clamp((limit - self.position) / 6, 0, 1)
end

local Tab = {}
Tab.__index = Tab

function Tab:show(subtab)
	if self.current then
		self.current.view.Visible = false
		self.current.mark(0)
	end
	self.current = subtab
	subtab.view.Visible = true
	subtab.mark(1)
	if self.window.tab == self then
		page = subtab
	end
end

-- the strip along the bottom only appears once a tab has more than one of these
function Tab:CreateSubTab(name)
	local view = frame({
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = self.pages,
	})
	local content = frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = view })
	local function column(x)
		local holder = frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 6), Size = UDim2.fromOffset(300, 0), Parent = content })
		local layout = make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
		return { holder = holder, layout = layout, cards = 0, height = 0 }
	end

	local cell = button({ BackgroundColor3 = WHITE, LayoutOrder = #self.subtabs + 1, Parent = self.cells })
	local caption = label(ROW, {
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 13),
		Parent = cell,
	})
	local lit, on = 0, 0
	local function paint()
		cell.BackgroundTransparency = 1 - lit * 8 / 255
		caption.TextColor3 = MUTED:Lerp(TEXT, lit):Lerp(ACCENT, on)
		caption.TextTransparency = (1 - on) * (0.65 - 0.4 * lit)
	end
	hover(cell, function(amount)
		lit = amount
		paint()
	end)

	local subtab = setmetatable({
		window = self.window,
		tab = self,
		path = name == "" and self.name or self.name .. "/" .. name,
		view = view,
		content = content,
		left = column(6),
		right = column(312),
		-- the page's own colour over cards scrolled into the top and bottom padding
		top = frame({ BackgroundColor3 = WINDOW, Size = UDim2.new(1, 0, 0, 6), ZIndex = 2, Parent = view }),
		bottom = frame({
			BackgroundColor3 = WINDOW,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 6),
			ZIndex = 2,
			Parent = view,
		}),
		target = 0,
		position = 0,
		cell = cell,
		divider = frame({
			BackgroundColor3 = BORDER,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 1, 1, 0),
			Parent = cell,
		}),
		mark = tween(0.1, EASE, function(amount)
			on = amount
			paint()
		end),
	}, SubTab)
	cell.MouseButton1Click:Connect(function()
		self:show(subtab)
	end)

	table.insert(self.subtabs, subtab)
	for index, other in self.subtabs do
		other.cell.Size = UDim2.fromScale(1 / #self.subtabs, 1)
		other.divider.Visible = index < #self.subtabs
	end
	if not self.current then
		self:show(subtab)
	end
	if self.window.tab == self then
		self.window.arrange()
	end
	return subtab
end

function Tab:CreateSection(name, side)
	self.main = self.main or self:CreateSubTab("")
	return self.main:CreateSection(name, side)
end

-- title names the game's saved configs; the header shows the brand
function ui.createWindow(title)
	local window = { controls = {} }
	local prefix = title:lower():gsub("%W+", "_") .. "_config_"

	local root = make("CanvasGroup", {
		BackgroundColor3 = WINDOW,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(100, 100),
		Size = UDim2.fromOffset(620, 434),
		Parent = screen,
	})
	corner(root, 4)
	outline(root, BORDER, 4)
	zoom.Parent = root

	local grip = button({ Size = UDim2.new(1, 0, 0, 53), ZIndex = 0, Parent = root })
	grip.MouseButton1Down:Connect(function()
		local offset = mouse() - Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
		dragging = function(position)
			root.Position = UDim2.fromOffset(position.X - offset.X, position.Y - offset.Y)
		end
	end)

	label(ROW, { Text = BRAND, TextColor3 = ACCENT, Position = UDim2.fromOffset(13, 0), Size = UDim2.fromOffset(72, 53), Parent = root })
	frame({ BackgroundColor3 = BORDER, Position = UDim2.fromOffset(85, 0), Size = UDim2.fromOffset(1, 53), Parent = root })
	frame({ BackgroundColor3 = BORDER, Position = UDim2.fromOffset(518, 0), Size = UDim2.fromOffset(1, 53), Parent = root })
	hairline(root, 52, 0.15)

	local rail = frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(89, 0), Size = UDim2.fromOffset(429, 53), Parent = root })
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rail,
	})
	local area = frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 53), Size = UDim2.fromOffset(618, 381), Parent = root })
	local strip = frame({
		BackgroundColor3 = STRIP,
		Position = UDim2.fromOffset(0, 404),
		Size = UDim2.new(1, 0, 0, 30),
		Visible = false,
		Parent = root,
	})
	hairline(strip, 0, 0.2)

	function window.arrange()
		local tab = window.tab
		local split = #tab.subtabs > 1
		strip.Visible = split
		tab.cells.Visible = split
		area.Size = UDim2.fromOffset(618, split and 351 or 381)
		page = tab.current
	end

	local function show(tab)
		if window.tab then
			window.tab.pages.Visible = false
			window.tab.cells.Visible = false
			window.tab.mark(0)
		end
		window.tab = tab
		tab.pages.Visible = true
		tab.mark(1)
		window.arrange()
	end

	-- glyph is a name from ICONS
	function window:CreateTab(name, glyph)
		local hit = button({
			Size = UDim2.fromOffset(50, 50),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = #rail:GetChildren(),
			Parent = rail,
		})
		make("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = hit,
		})
		local image = glyph and icon(glyph, { Parent = hit })
		local caption = label(TAB, {
			Text = name,
			Size = UDim2.fromOffset(0, 12),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			Parent = hit,
		})

		local lit, on = 0, 0
		local function paint()
			if image then
				image.ImageColor3 = MUTED:Lerp(ACCENT, on)
				image.ImageTransparency = (1 - on) * (0.55 - 0.3 * lit)
			end
			caption.TextColor3 = MUTED:Lerp(TEXT, lit):Lerp(ACCENT, on)
			caption.TextTransparency = (1 - on) * (0.3 - 0.3 * lit)
		end
		hover(hit, function(amount)
			lit = amount
			paint()
		end)

		local cells = frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = strip })
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Parent = cells })
		local tab = setmetatable({
			window = window,
			name = name,
			subtabs = {},
			pages = frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = area }),
			cells = cells,
			mark = tween(0.1, EASE, function(amount)
				on = amount
				paint()
			end),
		}, Tab)
		hit.MouseButton1Click:Connect(function()
			show(tab)
		end)
		if not window.tab then
			show(tab)
		end
		return tab
	end

	local function headerButton(x, glyph)
		local hit = button({ BackgroundColor3 = CHIP, Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(28, 28), Parent = root })
		corner(hit, 3)
		local glow = frame({ BackgroundColor3 = ACCENT, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = hit })
		corner(glow, 3)
		local image = icon(glyph, { ImageColor3 = MUTED, Position = UDim2.fromOffset(7, 7), Parent = hit })
		hover(hit, function(amount)
			hit.BackgroundTransparency = 1 - amount
		end)
		return hit, function(active)
			glow.BackgroundTransparency = active and 0.93 or 1
			image.ImageColor3 = active and ACCENT or MUTED
		end
	end

	-- search: lists the controls whose name holds the text and steps through them with the arrow keys
	local searchButton, lightSearch = headerButton(527, "search")
	local over = frame({
		BackgroundColor3 = WINDOW,
		Active = true,
		Position = UDim2.fromOffset(86, 0),
		Size = UDim2.fromOffset(432, 52),
		Visible = false,
		ZIndex = 3,
		Parent = root,
	})
	local query = make("TextBox", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextSize = ROW,
		TextColor3 = TEXT,
		PlaceholderColor3 = MUTED,
		PlaceholderText = "search settings...",
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(3, 0),
		Size = UDim2.fromOffset(290, 52),
		Parent = over,
	})
	local count = label(TITLE, {
		Text = "",
		TextColor3 = MUTED,
		TextTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(296, 0),
		Size = UDim2.fromOffset(100, 52),
		Parent = over,
	})
	label(TITLE, {
		Text = "↑↓",
		TextColor3 = MUTED,
		TextTransparency = 0.78,
		Position = UDim2.fromOffset(402, 0),
		Size = UDim2.fromOffset(24, 52),
		Parent = over,
	})
	local matches, match = {}, 0

	local function jump()
		local entry = matches[match]
		show(entry.page.tab)
		entry.page.tab:show(entry.page)
		entry.page.target = (entry.row.AbsolutePosition.Y - entry.page.content.AbsolutePosition.Y) / zoom.Scale - 60
		local band = frame({
			BackgroundColor3 = ACCENT,
			Position = UDim2.fromOffset(-9, 0),
			Size = UDim2.new(1, 18, 1, 0),
			ZIndex = 0,
			Parent = entry.row,
		})
		tween(0.8, linear, function(amount)
			band.BackgroundTransparency = 0.7 + 0.3 * amount
			if amount == 1 then
				band:Destroy()
			end
		end)(1)
	end

	query:GetPropertyChangedSignal("Text"):Connect(function()
		local text = query.Text:lower()
		table.clear(matches)
		if text ~= "" then
			for _, entry in window.controls do
				if entry.name and entry.name:find(text, 1, true) then
					table.insert(matches, entry)
				end
			end
		end
		count.Text = text == "" and "" or string.format("%d result%s", #matches, #matches == 1 and "" or "s")
		match = math.min(1, #matches)
		if match > 0 then
			jump()
		end
	end)
	searchButton.MouseButton1Click:Connect(function()
		over.Visible = not over.Visible
		lightSearch(over.Visible)
		if over.Visible then
			query:CaptureFocus()
		else
			query:ReleaseFocus()
			query.Text = ""
		end
	end)

	-- configs: every control with a value, saved under its tab / section / name path
	local saveButton, lightSave = headerButton(556, "save")
	local shelf = panel(WINDOW, 3)
	label(TITLE, {
		Text = "configs",
		TextColor3 = MUTED,
		TextTransparency = 0.5,
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -18, 0, 22),
		Parent = shelf,
	})
	frame({ BackgroundColor3 = BORDER, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 1), Parent = shelf })
	local saved = scroller({ Position = UDim2.fromOffset(1, 26), Parent = shelf })
	local none = label(SMALL, {
		Text = "no configs",
		TextColor3 = MUTED,
		TextTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = shelf,
	})
	local newName = field(shelf, UDim2.new(0, 8, 1, -26), UDim2.new(1, -38, 0, 18), "config name")
	local plus = button({
		BackgroundColor3 = CHIP,
		BackgroundTransparency = 0,
		Position = UDim2.new(1, -26, 1, -26),
		Size = UDim2.fromOffset(18, 18),
		Parent = shelf,
	})
	corner(plus, 2)
	icon("plus-small", {
		ImageColor3 = MUTED,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		Parent = plus,
	})

	local listConfigs

	local function saveConfig(name)
		local data = {}
		for _, entry in window.controls do
			if entry.get then
				data[entry.key] = entry.get()
			end
		end
		config.save(prefix .. name, data)
		ui.notify("saved config " .. name, "success")
		listConfigs()
	end

	local function loadConfig(name)
		local data = config.load(prefix .. name)
		for _, entry in window.controls do
			if entry.set and data[entry.key] ~= nil then
				entry.set(data[entry.key])
			end
		end
		ui.notify("loaded config " .. name, "success")
	end

	local function chip(parent, text, right, width, action)
		local hit = button({
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 0.94,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -right, 0.5, 0),
			Size = UDim2.fromOffset(width, 13),
			FontFace = FONT,
			TextSize = KEY,
			TextColor3 = ACCENT,
			TextTransparency = 0.45,
			Text = text,
			Parent = parent,
		})
		corner(hit, 2)
		outline(hit, ACCENT_DIM, 2).Transparency = 0.84
		hit.MouseButton1Click:Connect(action)
	end

	function listConfigs()
		for _, child in saved:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local names = config.list(prefix)
		for order, name in names do
			local row = frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, Parent = saved })
			icon("folder", { ImageColor3 = MUTED, Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(10, 10), Parent = row })
			label(TAB, {
				Text = name,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(24, 0),
				Size = UDim2.new(1, -122, 1, 0),
				Parent = row,
			})
			chip(row, "load", 58, 30, function()
				loadConfig(name)
			end)
			chip(row, "save", 24, 30, function()
				saveConfig(name)
			end)
			chip(row, "x", 7, 13, function()
				config.delete(prefix .. name)
				listConfigs()
			end)
		end
		none.Visible = #names == 0
		local height = 22 * math.clamp(#names, 1, 6)
		saved.Size = UDim2.new(1, -2, 0, height)
		shelf.Size = UDim2.fromOffset(240, height + 60)
	end

	plus.MouseButton1Click:Connect(function()
		-- the name becomes part of a file name
		local name = newName.Text:gsub("[^%w%-_ ]", "")
		if name ~= "" then
			newName.Text = ""
			saveConfig(name)
		end
	end)
	saveButton.MouseButton1Click:Connect(function()
		listConfigs()
		lightSave(true)
		openPopup(shelf, saveButton.AbsolutePosition.X - 212, saveButton.AbsolutePosition.Y + 32, function()
			lightSave(false)
		end)
	end)

	-- avatar: the initial shows until the headshot has loaded over it
	local player = Players.LocalPlayer
	local face = frame({ BackgroundColor3 = ACCENT_DARK, Position = UDim2.fromOffset(588, 15), Size = UDim2.fromOffset(22, 22), Parent = root })
	corner(face, 11)
	outline(face, ACCENT_DIM, 11)
	label(TAB, {
		Text = player.Name:sub(1, 1):upper(),
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
	corner(make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=48&h=48",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = face,
	}), 11)

	-- opening eases out, closing eases in, and the frame grows from 0.954 about its corner
	local reveal = tween(OPEN_TIME, linear, function(progress)
		local eased = visible and 1 - (1 - progress) ^ 3 or progress ^ 3
		root.GroupTransparency = 1 - eased * 235 / 255
		zoom.Scale = 0.954 + 0.046 * eased
		root.Visible = progress > 0
	end, 1)

	hub.cleanup.add(UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == TOGGLE_KEY and not processed then
			visible = not visible
			closePopup()
			reveal(visible and 1 or 0)
		elseif over.Visible and #matches > 0 and (input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.Up) then
			match = (match - 1 + (input.KeyCode == Enum.KeyCode.Down and 1 or -1)) % #matches + 1
			jump()
		end
	end))

	return window
end

function ui.visible()
	return visible
end

return ui
