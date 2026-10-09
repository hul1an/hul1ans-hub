local hub = ...

local UserInputService = cloneref(game:GetService("UserInputService"))

-- archived upstream with no license, so it's fetched at a fixed commit instead of copied here
local SOURCE_URL = "https://raw.githubusercontent.com/AlexR32/Bracket/2c348f3cb48c59722a9ef7faf238f8ebd794e4e3/BracketV3.lua"
local TOGGLE_KEY = Enum.KeyCode.RightShift
local ACCENT = Color3.fromRGB(90, 140, 255)

-- the library never disconnects its RunService / UserInputService connections
local source = "local hub = ... " .. hub.fetch(SOURCE_URL)
source = source:gsub('local RunService = game:GetService%("RunService"%)', 'local RunService = hub.cleanup.track(game:GetService("RunService"))')
source = source:gsub('local UserInputService = game:GetService%("UserInputService"%)', 'local UserInputService = hub.cleanup.track(game:GetService("UserInputService"))')
local library = assert(loadstring(source, "=BracketV3"))(hub)

local bracket = {}

function bracket.createWindow(title)
	local parent = gethui()
	local before = {}
	for _, child in parent:GetChildren() do
		before[child] = true
	end

	local window = library:CreateWindow({ WindowName = title, Color = ACCENT }, parent)

	for _, child in parent:GetChildren() do
		if not before[child] and child:FindFirstChild("Main") and child:FindFirstChild("ToolTip") then
			hub.cleanup.add(child)
		end
	end

	hub.cleanup.add(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			window:Toggle(not library.Toggle)
		end
	end))

	return window
end

return bracket
