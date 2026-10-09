local hub = ...

local UserInputService = cloneref(game:GetService("UserInputService"))

local BACKGROUND = Color3.fromRGB(24, 24, 28)
local TITLE_BAR = Color3.fromRGB(34, 34, 40)
local BUTTON = Color3.fromRGB(44, 44, 52)
local BUTTON_HOVER = Color3.fromRGB(58, 58, 68)
local TEXT = Color3.fromRGB(235, 235, 240)
local MUTED = Color3.fromRGB(150, 150, 160)
local TOGGLE_KEY = Enum.KeyCode.RightShift

local ui = {}

local function create(class, properties, parent)
	local object = Instance.new(class)
	for name, value in properties do
		object[name] = value
	end
	object.Parent = parent
	return object
end

local function createButton(text, properties, parent)
	properties.BackgroundColor3 = BUTTON
	properties.BorderSizePixel = 0
	properties.AutoButtonColor = false
	properties.Font = Enum.Font.Gotham
	properties.Text = text
	properties.TextColor3 = TEXT
	properties.TextSize = 13
	local button = create("TextButton", properties, parent)
	create("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = BUTTON_HOVER
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = BUTTON
	end)
	return button
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function ui.createWindow(title)
	local gui = hub.cleanup.add(create("ScreenGui", {
		Name = "Hub",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, gethui()))

	local main = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 380),
		BackgroundColor3 = BACKGROUND,
		BorderSizePixel = 0,
	}, gui)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, main)

	local titleBar = create("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = TITLE_BAR,
		BorderSizePixel = 0,
	}, main)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, titleBar)

	create("TextLabel", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -50, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextColor3 = TEXT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleBar)

	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = MUTED,
		TextSize = 14,
	}, titleBar)
	close.Activated:Connect(function()
		hub.unload()
	end)

	local body = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
	}, main)
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, body)

	local status = create("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Ready",
		TextColor3 = MUTED,
		TextSize = 12,
	}, main)

	local eject = createButton("Eject", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -28),
		Size = UDim2.new(1, -16, 0, 30),
	}, main)
	eject.Activated:Connect(function()
		hub.unload()
	end)

	local dragging, dragStart, startPosition
	titleBar.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			dragStart = input.Position
			startPosition = main.Position
		end
	end)
	hub.cleanup.add(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPosition.X.Scale, startPosition.X.Offset + delta.X,
				startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
			)
		end
	end))
	hub.cleanup.add(UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then
			dragging = false
		end
	end))
	hub.cleanup.add(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			main.Visible = not main.Visible
		end
	end))

	local window = {}
	local order = 0

	local function nextOrder()
		order += 1
		return order
	end

	function window.section(text)
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
		}, body)
	end

	function window.button(text, callback)
		local button = createButton(text, {
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = nextOrder(),
		}, body)
		button.Activated:Connect(callback)
	end

	function window.notify(text)
		status.Text = text
	end

	return window
end

return ui
