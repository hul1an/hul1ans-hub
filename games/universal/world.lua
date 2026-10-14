local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local Lighting = cloneref(game:GetService("Lighting"))

local esp = hub.require("games/universal/esp.lua")

local WHITE = Color3.new(1, 1, 1)
local VIEW_STEP = "HubView"
local RESET_STEP = "HubViewReset"
local NIGHT = {
	ClockTime = 0,
	Brightness = 2,
	OutdoorAmbient = Color3.fromRGB(70, 70, 90),
	Ambient = Color3.fromRGB(60, 60, 70),
	GlobalShadows = true,
	ExposureCompensation = 0.5,
}
local SKY_FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
-- seconds between looks for the lights in the world
local LIGHT_SCAN = 5
-- the nearest Roblox lets the camera zoom in
local NEAREST_ZOOM = 0.5

-- the precipitation row: an emitter for each type on a plate held over the camera, with the hub's own textures. speed
-- is in studs a second and life in seconds, which together are how far a particle falls; spread and spin are in degrees
local PLATE_HEIGHT = 35
local WEATHER = {
	rain = { texture = "weather-streak.png", speed = 80, life = 1, size = 2, color = Color3.fromRGB(190, 205, 225), fade = 0.5 },
	snow = { texture = "weather-dot.png", speed = 8, life = 8, size = 0.2, color = Color3.new(1, 1, 1), spread = 15 },
	leaves = { texture = "weather-leaf.png", speed = 7, life = 9, size = 0.6, color = Color3.fromRGB(170, 110, 50), spread = 25, spin = 180 },
	ashes = { texture = "weather-dot.png", speed = 4, life = 12, size = 0.12, color = Color3.fromRGB(120, 120, 120), spread = 20 },
	embers = { texture = "weather-dot.png", speed = 5, life = 10, size = 0.1, color = Color3.fromRGB(255, 130, 40), spread = 25, glow = 1 },
}
local BLUR_PER_DEGREE = 0.05
local BLUR_LIMIT = 24

local world = {
	settings = {
		precipitation = false,
		weather = { "rain" },
		outdoors = false,
		particles = 256,
		fog = false,
		fogDensity = 50,
		fogStart = 0,
		fogEnd = 1000,
		tint = false,
		tintColor = WHITE,
		sun = false,
		sunColor = WHITE,
		light = false,
		lightColor = WHITE,
		ambience = false,
		ambienceColor = WHITE,
		bloom = false,
		bloomScale = 40,
		bloomThreshold = 0.1,
		bloomBlur = 43,
		motionBlur = false,
		motionBlurAmount = 0.5,
		fov = false,
		fovValue = 70,
		aspectRatio = 0,
		thirdPerson = false,
		thirdPersonDistance = 12,
		removals = {},
	},
}
local settings = world.settings

-- the Lighting properties held at a value by the modulation rows and the shadows removal, which night mode leaves alone
local held = {}
local lightingWas = {}

-- the game's own lighting, held while night mode is on so it can be put back
local daylight

-- holds a Lighting property at a value while on, and puts back what it had when that ends
local function hold(property, on, value)
	if on then
		if not held[property] then
			held[property] = true
			lightingWas[property] = daylight and daylight[property] or Lighting[property]
		end
		Lighting[property] = value
	elseif held[property] then
		held[property] = nil
		Lighting[property] = lightingWas[property]
	end
end

-- for a row that keeps one property of some instances at a value: the first function sets it on one, remembering what
-- it had, and the second puts them all back
local function holder(property)
	local was = setmetatable({}, { __mode = "k" })
	return function(instance, value)
		if was[instance] == nil then
			was[instance] = instance[property]
		end
		instance[property] = value
	end, function()
		for instance, old in was do
			instance[property] = old
		end
		table.clear(was)
	end
end

local lightsOff, lightsOn = holder("Enabled")
local lightsTint, lightsUntint = holder("Color")
local postOff, postOn = holder("Enabled")
local airClear, airRestore = holder("Density")

-- the lights of the world, looked for again every LIGHT_SCAN seconds while a row needs them
local lights, scanned = {}, 0

local function worldLights()
	local now = os.clock()
	if now - scanned > LIGHT_SCAN then
		scanned = now
		table.clear(lights)
		for _, instance in workspace:GetDescendants() do
			if instance:IsA("Light") then
				table.insert(lights, instance)
			end
		end
	end
	return lights
end

local function setNight(enabled)
	if enabled and not daylight then
		daylight = {}
		for property in NIGHT do
			daylight[property] = Lighting[property]
		end
	elseif not enabled and daylight then
		for property, value in daylight do
			if not held[property] then
				Lighting[property] = value
			end
		end
		daylight = nil
	end
end

-- the world row of the modulation card: a tint over everything, under the camera
local tint = hub.cleanup.add(Instance.new("ColorCorrectionEffect"))
tint.Enabled = false
tint.Parent = workspace.CurrentCamera

-- the bloom row has a bloom of its own, since there may be none in the game
local bloom = hub.cleanup.add(Instance.new("BloomEffect"))
bloom.Enabled = false
bloom.Parent = workspace.CurrentCamera

-- the motion blur row. Roblox has no motion blur, so this is a BlurEffect whose size follows how fast the view is
-- turning: amount times this for each degree a second, up to a limit
local blur = hub.cleanup.add(Instance.new("BlurEffect"))
blur.Enabled = false
blur.Size = 0
blur.Parent = workspace.CurrentCamera
local lastLook

-- the 2d skybox removal: the Lighting's Sky with nothing in it, or one made for the purpose where there is none
local sky, skyWas, skyMade

local function skyStep()
	if table.find(settings.removals, "2d skybox") then
		if sky then
			return
		end
		sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			skyWas = {}
			for _, property in { "CelestialBodiesShown", "StarCount" } do
				skyWas[property] = sky[property]
			end
			for _, face in SKY_FACES do
				skyWas[face] = sky[face]
			end
		else
			sky, skyMade = Instance.new("Sky"), true
			sky.Parent = Lighting
		end
		for _, face in SKY_FACES do
			sky[face] = ""
		end
		sky.CelestialBodiesShown = false
		sky.StarCount = 0
	elseif sky then
		if skyMade then
			sky:Destroy()
		else
			for property, value in skyWas do
				sky[property] = value
			end
		end
		sky, skyWas, skyMade = nil, nil, nil
	end
end

-- the fog row. Starline's fog is none before start, thickest at end, and density the most it hides. Roblox's runs from
-- FogStart to a FogEnd where nothing shows, so FogEnd is put where the fog is as thick as the density at starline's
-- end. An Atmosphere in Lighting switches that fog off, so the game's is held out of it meanwhile
local fogWas, air

local function fogStep()
	if not settings.fog then
		if fogWas then
			Lighting.FogStart, Lighting.FogEnd = fogWas[1], fogWas[2]
			fogWas = nil
			if air then
				air.Parent = Lighting
				air = nil
			end
		end
		return
	end
	fogWas = fogWas or { Lighting.FogStart, Lighting.FogEnd }
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		-- the one held is from one the game has put in since, and out of Lighting the game doesn't see it
		if air then
			air:Destroy()
		end
		air = atmosphere
		atmosphere.Parent = nil
	end
	local start = settings.fogStart
	local reach = math.max(settings.fogEnd - start, 1)
	Lighting.FogStart = start
	Lighting.FogEnd = start + reach / math.max(settings.fogDensity / 100, 0.001)
end

local effects = hub.cleanup.add(Instance.new("Folder"))
effects.Parent = workspace.CurrentCamera
local plate = Instance.new("Part")
plate.Anchored = true
plate.CanCollide = false
plate.CanQuery = false
plate.CanTouch = false
plate.CastShadow = false
plate.Transparency = 1
plate.Size = Vector3.new(100, 1, 100)
plate.Parent = effects
local emitters = {}
for name, kind in WEATHER do
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = hub.ui.asset(kind.texture)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(kind.speed * 0.8, kind.speed)
	emitter.Lifetime = NumberRange.new(kind.life)
	emitter.Size = NumberSequence.new(kind.size)
	emitter.Color = ColorSequence.new(kind.color)
	emitter.Transparency = NumberSequence.new(kind.fade or 0)
	emitter.SpreadAngle = Vector2.one * (kind.spread or 0)
	emitter.Rotation = NumberRange.new(0, kind.spin and 360 or 0)
	emitter.RotSpeed = NumberRange.new(-(kind.spin or 0), kind.spin or 0)
	emitter.LightEmission = kind.glow or 0
	-- lit the same by day and under night mode
	emitter.LightInfluence = 0
	-- the rain's texture is a streak from left to right, which is the side of it this lays along the fall
	if name == "rain" then
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	end
	emitter.Parent = plate
	emitters[name] = emitter
end

local function weatherStep(camera)
	local eye = camera.CFrame.Position
	local falling = settings.precipitation
	if falling then
		plate.CFrame = CFrame.new(eye + Vector3.new(0, PLATE_HEIGHT, 0))
		-- outdoors only: nothing falls while there is something over the camera. Particles don't stop at a roof, so
		-- this is as near as it gets
		if settings.outdoors and not esp.visible(camera, eye + Vector3.new(0, 300, 0), plate) then
			falling = false
		end
	end
	for name, emitter in emitters do
		emitter.Enabled = falling and table.find(settings.weather, name) ~= nil
		-- particles is how many are in the air at once, shared between the types
		emitter.Rate = settings.particles / math.max(#settings.weather, 1) / WEATHER[name].life
	end
end

-- the bloom row's figures: Roblox takes an intensity up to 1, a threshold from 0.8 to 4 and a size up to 56
local function bloomStep()
	bloom.Enabled = settings.bloom
	bloom.Intensity = settings.bloomScale / 100
	bloom.Threshold = 0.8 + settings.bloomThreshold * 1.6
	bloom.Size = settings.bloomBlur / 100 * 56
end

local function blurStep(camera, dt)
	local look = camera.CFrame.LookVector
	local turn = lastLook and math.deg(look:Angle(lastLook)) / dt or 0
	lastLook = look
	blur.Enabled = settings.motionBlur
	-- eased, so that it doesn't flicker with every frame's turn
	local wanted = math.min(turn * settings.motionBlurAmount * BLUR_PER_DEGREE, BLUR_LIMIT)
	blur.Size += (wanted - blur.Size) * math.min(dt * 15, 1)
end

-- third person is the default camera script's own, held at one distance: it keeps the camera out of walls and turns it
-- by the mouse as it always does. What the user's zoom limits and mode were is kept to put back
local zoomWas

local function thirdPersonStep()
	local player = Players.LocalPlayer
	if settings.thirdPerson then
		zoomWas = zoomWas or {
			mode = player.CameraMode,
			min = player.CameraMinZoomDistance,
			max = player.CameraMaxZoomDistance,
		}
		local distance = settings.thirdPersonDistance
		player.CameraMode = Enum.CameraMode.Classic
		if player.CameraMinZoomDistance ~= distance or player.CameraMaxZoomDistance ~= distance then
			-- the minimum may not pass the maximum, so it goes out of the way for the maximum to move
			player.CameraMinZoomDistance = NEAREST_ZOOM
			player.CameraMaxZoomDistance = distance
			player.CameraMinZoomDistance = distance
		end
	elseif zoomWas then
		player.CameraMinZoomDistance = NEAREST_ZOOM
		player.CameraMaxZoomDistance = zoomWas.max
		player.CameraMinZoomDistance = zoomWas.min
		player.CameraMode = zoomWas.mode
		zoomWas = nil
	end
end

local function step(dt)
	local camera = workspace.CurrentCamera
	local removed = settings.removals

	-- reapplied every frame because a game may set its own lighting
	if daylight then
		for property, value in NIGHT do
			-- but for one a row is holding at a value of its own
			if not held[property] then
				Lighting[property] = value
			end
		end
	end
	hold("ColorShift_Top", settings.sun, settings.sunColor)
	hold("Ambient", settings.ambience, settings.ambienceColor)
	hold("OutdoorAmbient", settings.ambience, settings.ambienceColor)
	hold("GlobalShadows", table.find(removed, "shadows") ~= nil, false)
	tint.Enabled = settings.tint
	tint.TintColor = settings.tintColor

	local dark = table.find(removed, "lights")
	if dark or settings.light then
		for _, light in worldLights() do
			if dark then
				lightsOff(light, false)
			end
			if settings.light then
				lightsTint(light, settings.lightColor)
			end
		end
	end
	if not dark then
		lightsOn()
	end
	if not settings.light then
		lightsUntint()
	end

	if table.find(removed, "post process") then
		for _, effect in Lighting:GetChildren() do
			if effect:IsA("PostEffect") then
				postOff(effect, false)
			end
		end
	else
		postOn()
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and table.find(removed, "fog") then
		airClear(atmosphere, 0)
	else
		airRestore()
	end

	skyStep()
	fogStep()
	weatherStep(camera)
	bloomStep()
	blurStep(camera, dt)
	thirdPersonStep()
end

-- what the aspect ratio row changed in the camera, to be undone before the next frame
local squeezed
-- the camera's own field of view while the override has it
local fovWas

-- the field of view and the aspect ratio, after the camera script
local function viewStep()
	local camera = workspace.CurrentCamera
	if settings.fov then
		fovWas = fovWas or camera.FieldOfView
		camera.FieldOfView = settings.fovValue
	elseif fovWas then
		camera.FieldOfView = fovWas
		fovWas = nil
	end

	-- the stretched resolution trick: the view is squeezed upright and the field of view narrowed to match, which
	-- leaves the picture as tall as it was and wider
	local size = camera.ViewportSize
	local stretch = settings.aspectRatio > 0 and size.X / size.Y / settings.aspectRatio or 1
	if math.abs(stretch - 1) > 0.001 then
		local half = math.rad(camera.FieldOfView) / 2
		squeezed = { stretch = stretch, fov = camera.FieldOfView }
		camera.CFrame *= CFrame.new(0, 0, 0, 1, 0, 0, 0, 1 / stretch, 0, 0, 0, 1)
		camera.FieldOfView = math.deg(math.atan(math.tan(half) / stretch) * 2)
	end
end

-- first thing in the frame, so a camera that keeps its own view between frames doesn't build the squeeze up
local function resetStep()
	if squeezed then
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.new(0, 0, 0, 1, 0, 0, 0, squeezed.stretch, 0, 0, 0, 1)
		camera.FieldOfView = squeezed.fov
		squeezed = nil
	end
end

function world.start()
	hub.cleanup.add(RunService.RenderStepped:Connect(step))
	RunService:BindToRenderStep(RESET_STEP, Enum.RenderPriority.First.Value, resetStep)
	RunService:BindToRenderStep(VIEW_STEP, Enum.RenderPriority.Camera.Value + 4, viewStep)

	hub.cleanup.add(function()
		RunService:UnbindFromRenderStep(VIEW_STEP)
		RunService:UnbindFromRenderStep(RESET_STEP)
		resetStep()
		if fovWas then
			workspace.CurrentCamera.FieldOfView = fovWas
		end
		setNight(false)
		for property in held do
			Lighting[property] = lightingWas[property]
		end
		table.clear(held)
		for _, release in { lightsOn, lightsUntint, postOn, airRestore } do
			release()
		end
		settings.fog, settings.thirdPerson, settings.removals = false, false, {}
		skyStep()
		fogStep()
		thirdPersonStep()
	end)
end

world.setNight = setNight

return world
