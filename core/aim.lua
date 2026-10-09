local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))

local esp = hub.require("core/esp.lua")

local AIM_BUTTON = Enum.UserInputType.MouseButton2
local STEP_NAME = "HubAim"
local PARTS = { Head = "Head", Torso = "HumanoidRootPart" }
-- seconds between auto fire clicks, and how long each click is held
local FIRE_DELAY = 0.05
local FIRE_HOLD = 0.02

-- aim.target is the part currently aimed at, or nil; game files read it
local aim = {
	settings = {
		Enabled = false,
		TeamCheck = false,
		VisibilityCheck = true,
		MaxDistance = 500,
		Mode = "Crosshair",
		TargetPart = "Head",
		Fov = 120,
		DrawFov = false,
		TargetColor = false,
		AutoFire = false,
	},
}

local settings = aim.settings
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local lastShot = 0

local function isVisible(camera, part, model)
	-- the camera is excluded because first person viewmodels are parented to it
	local ignore = { model, camera, Players.LocalPlayer.Character }
	local origin = camera.CFrame.Position
	-- fully invisible parts (map barriers, clip walls) are looked through, up to a few in a row
	for _ = 1, 8 do
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, part.Position - origin, rayParams)
		if not hit then
			return true
		end
		if hit.Instance.Transparency < 1 then
			return false
		end
		table.insert(ignore, hit.Instance)
	end
	return false
end

local function findTarget(camera)
	local origin = camera.CFrame.Position
	local center = camera.ViewportSize / 2
	local bestModel, bestPart, bestScore

	for _, source in esp.sources do
		if source.aim then
			for _, model in source.models(settings.TeamCheck) do
				local health = esp.health(model, source)
				local part = model:FindFirstChild(PARTS[settings.TargetPart]) or model:FindFirstChild("HumanoidRootPart")
				if part and not (health and health <= 0) then
					local distance = (part.Position - origin).Magnitude
					local screen = camera:WorldToViewportPoint(part.Position)
					local offset = (Vector2.new(screen.X, screen.Y) - center).Magnitude
					if screen.Z > 0 and distance <= settings.MaxDistance and offset <= settings.Fov then
						local score = distance
						if settings.Mode == "Crosshair" then
							score = offset
						elseif settings.Mode == "Health" then
							score = health or math.huge
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

-- a left click at the screen centre; skipped while the menu is open so it can't click the menu
local function fire(camera)
	local now = os.clock()
	if now - lastShot < FIRE_DELAY or hub.bracket.visible() then
		return
	end
	lastShot = now

	local center = camera.ViewportSize / 2
	VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
	task.delay(FIRE_HOLD, function()
		VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
	end)
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
		aim.target = part
		esp.highlight = settings.TargetColor and model or nil

		if part and UserInputService:IsMouseButtonPressed(AIM_BUTTON) then
			camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
		end
		if part and settings.AutoFire then
			fire(camera)
		end
	end)

	hub.cleanup.add(function()
		RunService:UnbindFromRenderStep(STEP_NAME)
		circle:Remove()
		aim.target = nil
		esp.highlight = nil
	end)
end

return aim
