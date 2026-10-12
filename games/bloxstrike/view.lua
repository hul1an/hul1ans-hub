local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local Lighting = cloneref(game:GetService("Lighting"))

local esp = hub.require("games/bloxstrike/esp.lua")
local aim = hub.require("games/bloxstrike/aim.lua")

local WHITE = Color3.new(1, 1, 1)
local VIEW_STEP = "HubView"
-- the game's own field of view (Database.Custom.Constants.DEFAULT_CAMERA_FOV), which its scopes take 37 and 60 off
local DEFAULT_FOV = 70
local INVISIBLE = NumberSequence.new(1)
-- the game's interface, from the PlayerGui down to the frame its sniper scope is drawn in
local SCOPE_PATH = { "MainGui", "Gameplay", "Middle", "SniperScope" }
-- the screens and the Lighting effect a flashbang whites the view out with
local FLASH_SCREENS = { "FlashbangEffect", "FlashScreenshot" }
local FLASH_EFFECT = "FlashbangColorCorrection"
local AXES = { Vector2.xAxis, -Vector2.xAxis, Vector2.yAxis, -Vector2.yAxis }

-- main.lua sets view.sniper, a function that returns whether the gun out is one with a sniper's scope, and
-- view.scoped, one that returns whether the gun out is zoomed in and whether that is through a sniper's scope
local view = {
	settings = {
		World = false,
		WorldColor = WHITE,
		Sun = false,
		SunColor = WHITE,
		Light = false,
		LightColor = WHITE,
		Molotov = false,
		MolotovColor = WHITE,
		Smoke = false,
		SmokeColor = WHITE,
		Ambience = false,
		AmbienceColor = WHITE,
		Fov = false,
		FovValue = 90,
		Zoom1 = 100,
		Zoom2 = 100,
		AspectRatio = 0,
		-- starline's own figures for these two rows
		ScopedAlpha = false,
		ScopedAlphaValue = 35,
		Scope = "default",
		ScopeColor = Color3.new(0, 0, 0),
		ScopeOpacity = 1,
		ScopeViewmodel = false,
		ScopeLength = 100,
		ScopeDynamic = true,
		ScopeGap = 0,
		Removals = {},
		Crosshair = false,
		CrosshairScoped = false,
		Viewmodel = false,
		ViewmodelX = 0,
		ViewmodelY = 0,
		ViewmodelZ = 0,
		ViewmodelPitch = 0,
		ViewmodelYaw = 0,
		ViewmodelRoll = 0,
	},
	-- the Lighting properties held at a value here, which main.lua's night mode leaves alone meanwhile
	held = {},
}

local settings = view.settings
local held = view.held
local lightingWas = {}
local debris = workspace:FindFirstChild("Debris")
if not debris then
	warn("[hub] workspace.Debris not found: no smoke or molotov colours, no smoke removal")
	hub.ui.notify("workspace.Debris not found, no smoke or molotov colours or smoke removal", "error")
end

-- holds a Lighting property at a value while on, and puts back what it had when that ends
local function hold(property, on, value)
	if on then
		if not held[property] then
			held[property] = true
			lightingWas[property] = Lighting[property]
		end
		Lighting[property] = value
	elseif held[property] then
		held[property] = nil
		Lighting[property] = lightingWas[property]
	end
end

-- for a row that keeps one property of some of the game's instances at a value: the first function sets it on one,
-- remembering what it had, and the second puts them all back
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
local smokeHide, smokeShow = holder("Transparency")
local smokeTint, smokeUntint = holder("Color")
local fireTint, fireUntint = holder("Color")
local postOff, postOn = holder("Enabled")
local flashOff, flashOn = holder("Enabled")
local airClear, airRestore = holder("Density")
local scopeHide, scopeShow = holder("Visible")

-- the lights of the map that is loaded, listed once for each map since it has thousands of other things in it. One
-- the game adds later isn't in the list
local lit, lights

local function mapLights()
	local map = workspace:FindFirstChild("Map")
	if map ~= lit then
		lit, lights = map, {}
		if map then
			for _, light in map:GetDescendants() do
				if light:IsA("Light") then
					table.insert(lights, light)
				end
			end
		end
	end
	return lights
end

-- the particle emitters of the smoke or fire volumes that are out: the game keeps each volume in a folder under
-- workspace.Debris named VoxelSmoke_ or VoxelFire_ and its id
local function emitters(prefix)
	local list = {}
	for _, folder in debris:GetChildren() do
		if folder.Name:sub(1, #prefix) == prefix then
			for _, emitter in folder:GetDescendants() do
				if emitter:IsA("ParticleEmitter") then
					table.insert(list, emitter)
				end
			end
		end
	end
	return list
end

-- the world row of the modulation card: a tint over everything, under the camera where the game doesn't destroy it
local tint = hub.cleanup.add(Instance.new("ColorCorrectionEffect"))
tint.Enabled = false
tint.Parent = workspace.CurrentCamera

local scopeLines, crossLines = {}, {}
for index = 1, 4 do
	scopeLines[index] = Drawing.new("Line")
	scopeLines[index].Thickness = 1
	crossLines[index] = Drawing.new("Line")
	crossLines[index].Thickness = 1
	crossLines[index].Color = WHITE
end

local scopeFrame
local scopeWarned = false

-- the frame the game draws its sniper scope in
local function scopeGui()
	if scopeFrame and scopeFrame.Parent then
		return scopeFrame
	end
	local found = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, name in SCOPE_PATH do
		found = found and found:FindFirstChild(name)
	end
	scopeFrame = found
	if not (found or scopeWarned) then
		scopeWarned = true
		warn("[hub] PlayerGui." .. table.concat(SCOPE_PATH, ".") .. " not found: the game's scope stays under the scope overlay")
		hub.ui.notify("PlayerGui." .. table.concat(SCOPE_PATH, ".") .. " not found, the game's scope stays", "error")
	end
	return found
end

-- how many pixels from the middle of the screen an angle off the view ray is
local function pixels(camera, degrees)
	return math.tan(math.rad(degrees)) / math.tan(math.rad(camera.FieldOfView / 2)) * camera.ViewportSize.Y / 2
end

-- four strokes out from the middle of the screen, each from gap to gap and its length: reach.X for the two across,
-- reach.Y for the two upright
local function strokes(lines, camera, gap, reach, color, opacity)
	local center = camera.ViewportSize / 2
	for index, way in AXES do
		local line = lines[index]
		line.Visible = true
		line.Color = color
		line.Transparency = opacity
		line.From = center + way * gap
		line.To = center + way * (gap + math.abs(way.X) * reach.X + math.abs(way.Y) * reach.Y)
	end
end

-- how long starline draws its scope lines (its draw at 0x3CC860 in the dump): up to half length all four are that
-- share of the way to the nearer edge of the screen, and from there to full each grows to reach its own edge
local function scopeReach(camera)
	local center = camera.ViewportSize / 2
	local share = math.clamp(settings.ScopeLength, 5, 100) / 100
	local least = math.min(center.X, center.Y)
	local even = math.clamp(2 * (1 - share), 0, 1)
	return Vector2.new(center.X + (least - center.X) * even, center.Y + (least - center.Y) * even) * share
end

local function hide(lines)
	for _, line in lines do
		line.Visible = false
	end
end

-- whether the ragdoll removal has ragdolls hidden
local ragdollsHidden = false

local function setRagdolls(modifier)
	for model in esp.ragdolls() do
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = modifier
			end
		end
	end
end

local function step()
	local camera = workspace.CurrentCamera
	local removed = settings.Removals

	hold("ColorShift_Top", settings.Sun, settings.SunColor)
	hold("Ambient", settings.Ambience, settings.AmbienceColor)
	hold("OutdoorAmbient", settings.Ambience, settings.AmbienceColor)
	hold("GlobalShadows", table.find(removed, "shadows") ~= nil, false)
	tint.Enabled = settings.World
	tint.TintColor = settings.WorldColor

	local dark = table.find(removed, "lights")
	if dark or settings.Light then
		for _, light in mapLights() do
			if dark then
				lightsOff(light, false)
			end
			if settings.Light then
				lightsTint(light, settings.LightColor)
			end
		end
	end
	if not dark then
		lightsOn()
	end
	if not settings.Light then
		lightsUntint()
	end

	local clear = table.find(removed, "smoke")
	if debris and (clear or settings.Smoke) then
		local color = ColorSequence.new(settings.SmokeColor)
		for _, emitter in emitters("VoxelSmoke_") do
			if clear then
				smokeHide(emitter, INVISIBLE)
			end
			if settings.Smoke then
				smokeTint(emitter, color)
			end
		end
	end
	if not clear then
		smokeShow()
	end
	if not settings.Smoke then
		smokeUntint()
	end
	if debris and settings.Molotov then
		local color = ColorSequence.new(settings.MolotovColor)
		for _, emitter in emitters("VoxelFire_") do
			fireTint(emitter, color)
		end
	else
		fireUntint()
	end

	-- the blur named Menu is the game's menu's own
	if table.find(removed, "post process") then
		for _, effect in Lighting:GetChildren() do
			if effect:IsA("PostEffect") and effect.Name ~= "Menu" then
				postOff(effect, false)
			end
		end
	else
		postOn()
	end

	if table.find(removed, "flash") then
		local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		for _, name in FLASH_SCREENS do
			local screen = gui and gui:FindFirstChild(name)
			if screen then
				flashOff(screen, false)
			end
		end
		local effect = Lighting:FindFirstChild(FLASH_EFFECT)
		if effect then
			flashOff(effect, false)
		end
	else
		flashOn()
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and table.find(removed, "fog") then
		airClear(atmosphere, 0)
	else
		airRestore()
	end

	-- a ragdoll in use is shown by the game once, so one hidden here stays hidden until it is put back
	if esp.ragdolls then
		if table.find(removed, "ragdoll") then
			ragdollsHidden = true
			setRagdolls(1)
		elseif ragdollsHidden then
			ragdollsHidden = false
			setRagdolls(0)
		end
	end

	-- starline's three: the game's own scope picture, lines in its place, or neither
	local _, scoped = view.scoped()
	local replaced = settings.Scope ~= "default"
	local frame = replaced and scopeGui()
	if replaced and scoped then
		-- the game shows its two scope images again whenever it opens the scope
		for _, name in { "Sharp", "Blur" } do
			local image = frame and frame:FindFirstChild(name)
			if image then
				scopeHide(image, false)
			end
		end
	elseif not replaced then
		scopeShow()
	end
	if settings.Scope == "custom lines" and scoped then
		local gap = math.clamp(settings.ScopeGap, 0, 100)
		-- starline adds the gun's inaccuracy by a rule for CS2's field of view; here it is how far out on the screen
		-- the spread reaches
		local spread = settings.ScopeDynamic and aim.spread and aim.spread()
		if spread then
			gap += math.round(pixels(camera, spread))
		end
		strokes(scopeLines, camera, gap, scopeReach(camera), settings.ScopeColor, settings.ScopeOpacity)
	else
		hide(scopeLines)
	end
	-- the game hides a scoped sniper's viewmodel by its parts' Transparency and keeps what they had in an attribute
	if settings.ScopeViewmodel and scoped then
		for _, model in camera:GetChildren() do
			if model:IsA("Model") then
				for _, part in model:GetDescendants() do
					local kept = part:IsA("BasePart") and part:GetAttribute("HiddenTransparency")
					if kept and part.Transparency == 1 then
						part.Transparency = kept
					end
				end
			end
		end
	end

	-- the game draws no crosshair for a sniper
	if settings.Crosshair and view.sniper and view.sniper() and (settings.CrosshairScoped or not scoped) then
		strokes(crossLines, camera, 3, Vector2.new(6, 6), WHITE, 1)
	else
		hide(crossLines)
	end
end

-- the share of a scope's zoom that is kept, from the scope level the user was last at
local zoom = 1

-- the field of view and the aspect ratio, after the game's camera step, the hub's third person and its screen shake.
-- The game puts the camera back on its own view and field of view at the start of every frame, so neither builds up
local function viewStep()
	local camera = workspace.CurrentCamera
	if settings.Fov then
		local level = Players.LocalPlayer:GetAttribute("ScopeIncrement") or 0
		if level > 0 then
			zoom = (level == 1 and settings.Zoom1 or settings.Zoom2) / 100
		end
		-- the game's field of view as a share of its default: 1 with no scope, less the further it is zoomed in
		local share = camera.FieldOfView / DEFAULT_FOV
		camera.FieldOfView = settings.FovValue * (1 - zoom * (1 - share))
	end

	-- as the game's own stretched resolution setting does it: the view is squeezed upright and the field of view
	-- narrowed to match, which leaves the picture as tall as it was and wider
	local size = camera.ViewportSize
	local stretch = settings.AspectRatio > 0 and size.X / size.Y / settings.AspectRatio or 1
	if math.abs(stretch - 1) > 0.001 then
		local half = math.rad(camera.FieldOfView) / 2
		camera.CFrame *= CFrame.new(0, 0, 0, 1, 0, 0, 0, 1 / stretch, 0, 0, 0, 1)
		camera.FieldOfView = math.deg(math.atan(math.tan(half) / stretch) * 2)
	end
end

-- for main.lua's third person: how far the user's own body is hidden, which scoped transparency raises while scoped
function view.body()
	if settings.ScopedAlpha and view.scoped() then
		return 1 - settings.ScopedAlphaValue / 100
	end
	return 0
end

-- what the hub does to where the viewmodel is put: the game's sway and bob taken out, and the viewmodel changer's
-- offset added. Starline's x is to the right, y forward and z up, in hundredths of a stud as the game's own offsets are
local function place(cframe)
	if table.find(settings.Removals, "viewmodel bob") then
		-- what is left is the turn the game gives a gun that is aimed
		local _, yaw = cframe:ToOrientation()
		cframe = CFrame.Angles(0, yaw, 0)
	end
	if settings.Viewmodel then
		cframe *= CFrame.new(settings.ViewmodelX / 100, settings.ViewmodelZ / 100, -settings.ViewmodelY / 100)
			* CFrame.Angles(math.rad(settings.ViewmodelPitch), math.rad(settings.ViewmodelYaw), math.rad(settings.ViewmodelRoll))
	end
	return cframe
end

function view.start()
	hub.cleanup.add(RunService.RenderStepped:Connect(step))
	RunService:BindToRenderStep(VIEW_STEP, Enum.RenderPriority.Camera.Value + 4, viewStep)

	hub.cleanup.add(function()
		RunService:UnbindFromRenderStep(VIEW_STEP)
		for property in held do
			Lighting[property] = lightingWas[property]
		end
		table.clear(held)
		for _, release in { lightsOn, lightsUntint, smokeShow, smokeUntint, fireUntint, postOn, flashOn, airRestore, scopeShow } do
			release()
		end
		if ragdollsHidden then
			setRagdolls(0)
		end
		for _, lines in { scopeLines, crossLines } do
			for _, line in lines do
				line:Remove()
			end
		end
	end)

	-- the class of the viewmodel's sway, whose getNextCFrame gives where the viewmodel goes in front of the camera each
	-- frame. Like the game's other classes it is only reachable through the garbage collector
	local bobble
	for _, object in getgc(true) do
		if type(object) == "table"
			and type(rawget(object, "getNextCFrame")) == "function"
			and type(rawget(object, "addScopeKick")) == "function" then
			bobble = object
			break
		end
	end
	if not bobble then
		warn("[hub] BloxStrike viewmodel sway class (getNextCFrame) not found: no viewmodel changer or bob removal")
		hub.ui.notify("Viewmodel sway class (getNextCFrame) not found, no viewmodel changer or bob removal", "error")
		return
	end

	local warned = false
	local original
	original = hookfunction(bobble.getNextCFrame, function(self, ...)
		local cframe, shift, kick = original(self, ...)
		-- an error here would otherwise leave the game's viewmodel where it was
		local ok, result = pcall(place, cframe)
		if ok then
			cframe = result
		elseif not warned then
			warned = true
			warn("[hub] viewmodel hook failed: " .. tostring(result))
		end
		return cframe, shift, kick
	end)
	hub.cleanup.add(function()
		hookfunction(bobble.getNextCFrame, original)
	end)
end

return view
