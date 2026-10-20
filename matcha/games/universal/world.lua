local hub = ...

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local WHITE = Color3.new(1, 1, 1)
-- Matcha documents only three Lighting properties, and no way to make an effect, a particle or a sky, so this is all of
-- the world page it has
local NIGHT = {
	ClockTime = 0,
	Ambient = Color3.fromRGB(60, 60, 70),
	ExposureCompensation = 0.5,
}

local world = {
	settings = {
		ambience = false,
		ambienceColor = WHITE,
		fov = false,
		fovValue = 70,
		aspectRatio = 0,
	},
}
local settings = world.settings

-- the game's own lighting, held while night mode is on so it can be put back
local daylight
-- whether the ambience row is holding Ambient, which night mode then leaves alone, and what it was before
local holding, ambient

local function setNight(enabled)
	if enabled and not daylight then
		daylight = {}
		for property in NIGHT do
			daylight[property] = Lighting[property]
		end
	elseif not enabled and daylight then
		for property, value in daylight do
			if not (holding and property == "Ambient") then
				Lighting[property] = value
			end
		end
		daylight = nil
	end
end

local function lightingStep()
	-- reapplied every frame because a game may set its own lighting
	if daylight then
		for property, value in NIGHT do
			if not (holding and property == "Ambient") then
				Lighting[property] = value
			end
		end
	end
	if settings.ambience then
		if not holding then
			holding = true
			ambient = daylight and daylight.Ambient or Lighting.Ambient
		end
		Lighting.Ambient = settings.ambienceColor
	elseif holding then
		holding = false
		Lighting.Ambient = ambient
	end
end

-- the game's own field of view and what was last written, and whether the camera has been left squeezed
local baseFov, wroteFov
local squeezed = false

-- the camera's position and pitch and yaw alone, with no roll and no squeeze
local function upright(camera)
	local pitch, yaw = camera.CFrame:ToOrientation()
	local position = camera.CFrame.Position
	return CFrame.new(position.X, position.Y, position.Z) * CFrame.fromOrientation(pitch, yaw, 0)
end

-- the field of view and the aspect ratio. Matcha has no ordering of its steps against the game's camera, so each is
-- written from what the game would have, and not from what was written last frame
local function viewStep()
	local camera = workspace.CurrentCamera
	local current = camera.FieldOfView
	-- a field of view that isn't the one written is the game's own
	if not wroteFov or math.abs(current - wroteFov) > 0.01 then
		baseFov = current
	end

	-- the stretched resolution trick: the view is squeezed upright and the field of view narrowed to match, which
	-- leaves the picture as tall as it was and wider
	local size = camera.ViewportSize
	local stretch = settings.aspectRatio > 0 and size.X / size.Y / settings.aspectRatio or 1
	local squeeze = math.abs(stretch - 1) > 0.001
	if squeeze or squeezed then
		local view = upright(camera)
		camera.CFrame = squeeze and view * CFrame.new(0, 0, 0, 1, 0, 0, 0, 1 / stretch, 0, 0, 0, 1) or view
	end
	squeezed = squeeze

	if settings.fov or squeeze then
		local fov = settings.fov and settings.fovValue or baseFov
		if squeeze then
			fov = math.deg(math.atan(math.tan(math.rad(fov) / 2) / stretch) * 2)
		end
		camera.FieldOfView = fov
		wroteFov = fov
	elseif wroteFov then
		camera.FieldOfView = baseFov
		wroteFov = nil
	end
end

function world.start()
	hub.cleanup.add(RunService.RenderStepped:Connect(function()
		lightingStep()
		viewStep()
	end))

	hub.cleanup.add(function()
		settings.ambience, settings.fov, settings.aspectRatio = false, false, 0
		setNight(false)
		lightingStep()
		viewStep()
	end)
end

world.setNight = setNight

return world
