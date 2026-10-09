local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))

local esp = hub.require("core/esp.lua")

local AIM_BUTTON = Enum.UserInputType.MouseButton2
local STEP_NAME = "HubAim"
local PARTS = { Head = "Head", Torso = "HumanoidRootPart" }

local aim = {
	settings = {
		Enabled = false,
		VisibilityCheck = true,
		MaxDistance = 500,
		Mode = "Distance",
		TargetPart = "Head",
		Fov = 120,
		DrawFov = false,
		TargetColor = false,
	},
}

local settings = aim.settings
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isVisible(camera, part, model)
	-- the camera is excluded because first person viewmodels are parented to it
	rayParams.FilterDescendantsInstances = { model, camera, Players.LocalPlayer.Character }
	local origin = camera.CFrame.Position
	return workspace:Raycast(origin, part.Position - origin, rayParams) == nil
end

local function findTarget(camera)
	local origin = camera.CFrame.Position
	local center = camera.ViewportSize / 2
	local bestModel, bestPart, bestScore

	for _, source in esp.sources do
		if source.aim then
			for _, model in source.models() do
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local part = model:FindFirstChild(PARTS[settings.TargetPart]) or model:FindFirstChild("HumanoidRootPart")
				if part and not (humanoid and humanoid.Health <= 0) then
					local distance = (part.Position - origin).Magnitude
					local screen = camera:WorldToViewportPoint(part.Position)
					local offset = (Vector2.new(screen.X, screen.Y) - center).Magnitude
					if screen.Z > 0 and distance <= settings.MaxDistance and offset <= settings.Fov then
						local score = distance
						if settings.Mode == "Crosshair" then
							score = offset
						elseif settings.Mode == "Health" then
							score = humanoid and humanoid.Health or math.huge
						end
						if (not bestScore or score < bestScore)
							and (not settings.VisibilityCheck or isVisible(camera, part, model)) then
							bestModel, bestPart, bestScore = model, part, score
						end
					end
				end
			end
		end
	end

	return bestModel, bestPart
end

function aim.start()
	local circle = Drawing.new("Circle")
	circle.Thickness = 1
	circle.NumSides = 64
	circle.Color = Color3.new(1, 1, 1)

	-- bound after the camera update so the game's camera script doesn't overwrite the aim
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		circle.Visible = settings.Enabled and settings.DrawFov
		circle.Position = camera.ViewportSize / 2
		circle.Radius = settings.Fov

		local model, part
		if settings.Enabled then
			model, part = findTarget(camera)
		end
		esp.highlight = settings.TargetColor and model or nil

		if part and UserInputService:IsMouseButtonPressed(AIM_BUTTON) then
			camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
		end
	end)

	hub.cleanup.add(function()
		RunService:UnbindFromRenderStep(STEP_NAME)
		circle:Remove()
		esp.highlight = nil
	end)
end

return aim
