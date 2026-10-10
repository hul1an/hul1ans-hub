local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))

local esp = hub.require("core/esp.lua")

local AIM_BUTTON = Enum.UserInputType.MouseButton2
local FIRE_BUTTON = Enum.UserInputType.MouseButton1
local STEP_NAME = "HubAim"
-- seconds between clicks, and how long each click is held
local FIRE_DELAY = 0.05
local FIRE_HOLD = 0.02
-- Roblox's default field of view, which a dynamic FOV is scaled against
local DEFAULT_FOV = 70
-- the trigger only tests targets whose root is this near the view ray: starline's 64 units, about a character's height
local TRIGGER_REACH = 6
local AXES = { "X", "Y", "Z" }
-- the part names behind starline's hitgroups, R15 and R6
local HITGROUPS = {
	Head = { "Head" },
	Chest = { "UpperTorso", "Torso" },
	Stomach = { "HumanoidRootPart" },
	Pelvis = { "LowerTorso" },
	Arms = {
		"LeftUpperArm",
		"LeftLowerArm",
		"LeftHand",
		"RightUpperArm",
		"RightLowerArm",
		"RightHand",
		"Left Arm",
		"Right Arm",
	},
	Legs = { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "Left Leg", "Right Leg" },
	Feet = { "LeftFoot", "RightFoot" },
}
-- what force baim aims at in place of the chosen hitgroups
local BODY = { "Chest", "Stomach", "Pelvis" }

-- aim.target is the part currently aimed at, or nil; game files read it
local aim = {
	settings = {
		Enabled = false,
		DrawFov = false,
		FovColor = Color3.new(1, 1, 1),
		Disablers = {},
		Selection = "Crosshair",
		FovMode = "Static",
		Fov = 10,
		Hitgroups = { "Head" },
		Multipoint = false,
		MultipointScale = 50,
		Smoothing = false,
		SmoothingValue = 5,
		Humanization = 0,
		Sticky = 0,
		SwitchDelay = 0,
		MouseOverride = 100,
		ForceBaim = false,
		Trigger = false,
		TriggerHitgroups = { "Head", "Chest", "Stomach", "Pelvis", "Arms", "Legs", "Feet" },
		TriggerDelay = 0,
		TriggerVisibleDelay = 0,
		TriggerBurst = 0,
		TriggerRandomize = false,
		TeamCheck = false,
		VisibilityCheck = true,
		MaxDistance = 500,
		TargetColor = false,
		AutoFire = false,
	},
}

local settings = aim.settings
local random = Random.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local lastShot = 0
-- true while a click of the hub's own is held down
local clicking = false
-- the view written last frame and the one the game showed before it, pitch and yaw in degrees; nil while not pulling
local wrote, saw
-- sticky smoothing: the part being pulled to, whether the crosshair has reached it, and the 0 to 1 ramp since it did
local lockedPart, onTarget, progress = nil, false, 0
local switchTarget
local switchUntil = 0
-- trigger: when each target was first seen, and the delays rolled for the one now under the crosshair
local seenSince = {}
local frame = 0
local acquired, served, reaction, visibleFor, burstUntil

local function isVisible(camera, point, model)
	-- the camera is excluded because first person viewmodels are parented to it
	local ignore = { model, camera, Players.LocalPlayer.Character }
	local origin = camera.CFrame.Position
	-- fully invisible parts (map barriers, clip walls) are looked through, up to a few in a row
	for _ = 1, 8 do
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, point - origin, rayParams)
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

-- nothing under the local character's root within reach of its feet, which the esp puts 1.5 root heights down
local function airborne(camera)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	rayParams.FilterDescendantsInstances = { character, camera }
	return workspace:Raycast(root.Position, Vector3.new(0, -root.Size.Y * 1.75, 0), rayParams) == nil
end

-- calls back with every live model the aim may target, its root part and its health
local function eachTarget(callback)
	for _, source in esp.sources do
		if source.aim then
			for _, model in source.models(settings.TeamCheck) do
				local health = esp.health(model, source)
				local root = model:FindFirstChild("HumanoidRootPart")
				if root and not (health and health <= 0) then
					callback(model, root, health)
				end
			end
		end
	end
end

-- the parts of a model in the given hitgroups; a model with none of them is taken by its root
local function hitParts(model, groups)
	local parts = {}
	for _, group in groups do
		for _, name in HITGROUPS[group] do
			local part = model:FindFirstChild(name)
			if part then
				table.insert(parts, part)
			end
		end
	end
	if #parts == 0 then
		table.insert(parts, model:FindFirstChild("HumanoidRootPart"))
	end
	return parts
end

-- how far a part reaches from its centre along a direction
local function reach(part, direction)
	local half = part.Size / 2
	local along = part.CFrame:VectorToObjectSpace(direction)
	return math.min(half.X / math.abs(along.X), half.Y / math.abs(along.Y), half.Z / math.abs(along.Z))
end

-- how far along a ray it enters a part's box, or nil when it misses; direction is a unit vector
local function crosses(part, origin, direction)
	local half = part.Size / 2
	local from = part.CFrame:PointToObjectSpace(origin)
	local along = part.CFrame:VectorToObjectSpace(direction)
	local near, far = 0, math.huge
	for _, axis in AXES do
		local a = (-half[axis] - from[axis]) / along[axis]
		local b = (half[axis] - from[axis]) / along[axis]
		near = math.max(near, math.min(a, b))
		far = math.min(far, math.max(a, b))
	end
	return near <= far and near or nil
end

-- starline's dynamic FOV: half as wide again point blank, as set at 30% of the range, 30% of it at full range
local function scaleFov(fov, distance)
	local near = settings.MaxDistance * 0.3
	if distance <= near then
		return fov * (1.5 - 0.5 * distance / near)
	end
	return fov * (1 - 0.7 * math.clamp((distance - near) / (settings.MaxDistance - near), 0, 1))
end

-- starline's "closest" hitbox selection: of a model's chosen parts, the visible point nearest the crosshair
local function evaluate(camera, model, forward, fov)
	local eye = camera.CFrame.Position
	local bestPart, bestPoint, bestAngle

	local function consider(part, point)
		local angle = math.deg(forward:Angle(point - eye))
		if angle <= fov
			and (not bestAngle or angle < bestAngle)
			and (not settings.VisibilityCheck or isVisible(camera, point, model)) then
			bestPart, bestPoint, bestAngle = part, point, angle
		end
	end

	for _, part in hitParts(model, settings.ForceBaim and BODY or settings.Hitgroups) do
		local center = part.Position
		consider(part, center)
		if settings.Multipoint then
			-- points out towards the part's edges as the camera sees it, 0.9 of the way there at full scale
			local toward = (center - eye).Unit
			local right = toward:Cross(Vector3.yAxis).Unit
			local scale = settings.MultipointScale / 100 * 0.9
			local side = right * reach(part, right) * scale
			consider(part, center + side)
			consider(part, center - side)
			-- the head gets four, everything else the two to its sides
			if part.Name == "Head" then
				local up = right:Cross(toward)
				local rise = up * reach(part, up) * scale
				consider(part, center + rise)
				consider(part, center - rise)
			end
		end
	end

	return bestPart, bestPoint
end

-- starline's target selection: the target with the best key that has a point inside its FOV.
-- the last value is the FOV to draw, which in dynamic mode follows the enemy nearest the crosshair
local function findTarget(camera)
	local eye = camera.CFrame.Position
	local forward = camera.CFrame.LookVector
	local dynamic = settings.FovMode == "Dynamic"
	-- a dynamic FOV keeps its size on screen when the view zooms
	local base = dynamic and settings.Fov * camera.FieldOfView / DEFAULT_FOV or settings.Fov
	local drawn, nearest = base, base * 1.5
	local bestModel, bestPart, bestPoint, bestScore

	eachTarget(function(model, root, health)
		local offset = root.Position - eye
		local distance = offset.Magnitude
		if distance > settings.MaxDistance then
			return
		end

		local angle = math.deg(forward:Angle(offset))
		local fov = base
		if dynamic then
			fov = scaleFov(base, distance)
			if angle < nearest then
				nearest, drawn = angle, fov
			end
		end

		local score = distance
		if settings.Selection == "Crosshair" then
			score = angle
		elseif settings.Selection == "Health" then
			score = health or math.huge
		end
		if not bestScore or score < bestScore then
			local part, point = evaluate(camera, model, forward, fov)
			if part then
				bestModel, bestPart, bestPoint, bestScore = model, part, point, score
			end
		end
	end)

	return bestModel, bestPart, bestPoint, drawn
end

local function wrap(angle)
	return (angle + 180) % 360 - 180
end

-- a CFrame's pitch and yaw in degrees, as X and Y
local function angles(cframe)
	local pitch, yaw = cframe:ToOrientation()
	return Vector2.new(math.deg(pitch), math.deg(yaw))
end

local function facing(view)
	return CFrame.fromOrientation(math.rad(view.X), math.rad(view.Y), 0)
end

-- the turn from one view to another, each axis the short way round
local function turn(from, to)
	return Vector2.new(wrap(to.X - from.X), wrap(to.Y - from.Y))
end

-- starline's smoothing and humanization: how much of the turn that is left to make this frame
local function smooth(delta, weight, dt)
	local distance = delta.Magnitude
	if distance < 0.01 then
		return Vector2.zero
	end
	local rest = 1 - weight
	local human = math.clamp(rest * settings.Humanization, 0, 100) / 100

	-- the divisor runs from 1 to the smoothing value, and back to 1 as the sticky weight grows
	local divisor = rest * (math.max(settings.SmoothingValue, 1) - 1) + 1
	if human > 0 then
		divisor = math.max(random:NextNumber(divisor * (1 - human / 2), divisor * (1 + human / 2)), 1)
		-- slows down inside 10 degrees: 0.75 of the divisor far out, 1.25 on the target
		local close = distance < 10 and 1 - distance / 10 or 0
		divisor *= 0.5 * close * close * (3 - 2 * close) + 0.75
	end
	local share = 1
	if divisor > 1 then
		-- what 1 / divisor a tick comes to at 128 ticks a second, so the speed doesn't follow the frame rate
		share = 1 - (1 - 1 / divisor) ^ math.clamp(dt * 128, 0.01, 16)
	end
	local step = delta * share

	-- a curved path: the straight step blended with a bezier whose middle is pushed 0.15 of the turn sideways
	local curve = math.min(0.6, human * 0.8)
	if curve > 0 then
		local middle = delta * 0.5 + Vector2.new(-delta.Y, delta.X) * 0.15
		step = step * (1 - curve) + (delta * share * share + middle * 2 * share * (1 - share)) * curve
	end
	-- sideways jitter above 40% humanization
	if human > 0.4 and step.Magnitude >= 0.001 then
		local jitter = (human - 0.4) * 0.6
		step += Vector2.new(-step.Y, step.X) * random:NextNumber(-jitter, jitter) * 0.1
	end
	-- a tremor of up to 0.06 degrees
	local tremor = human * 0.06
	if tremor > 0 then
		step += Vector2.new(random:NextNumber(-tremor, tremor), random:NextNumber(-tremor, tremor))
	end
	-- above 70%, one frame in five overshoots a little when it is nearly there
	if distance > 0.2 and distance < 0.5 and human > 0.7 and random:NextNumber() < 0.2 and step.Magnitude > 0.01 then
		step += step.Unit * random:NextNumber(0.2, 0.5)
	end
	return step
end

-- starline's mouse side: turns the view towards the point, keeping what the settings leave of the user's own movement
local function pull(camera, part, point, dt)
	local eye = camera.CFrame.Position
	local now = angles(camera.CFrame)
	local view, user = now, Vector2.zero
	if wrote then
		-- a game that keeps its own view angles shows the view it had, not the one written last frame,
		-- so the user's movement is measured from whichever of the two the new view is nearer
		local base = turn(wrote, now).Magnitude <= turn(saw, now).Magnitude and wrote or saw
		view, user = wrote, turn(base, now)
	end

	local sticky = settings.Smoothing and settings.Sticky / 100 or 0
	if sticky == 0 or part ~= lockedPart then
		onTarget, progress = false, 0
	end
	lockedPart = part
	-- once the crosshair has reached the part, the smoothing fades out over 0.2 s by the sticky share
	if onTarget then
		progress = math.min(progress + math.min(dt, 0.05) / 0.2, 1)
	elseif sticky > 0 then
		onTarget = crosses(part, eye, facing(view).LookVector) ~= nil
	end
	local weight = sticky * progress * progress * (3 - 2 * progress)

	local step = turn(view, angles(CFrame.lookAt(eye, point)))
	if settings.Smoothing and weight < 1 then
		step = smooth(step, weight, dt)
	end

	-- the override, and the sticky weight on top of it, is the share of the user's own movement that is dropped
	local override = settings.MouseOverride / 100
	local final = view + step + user * (1 - (weight * (1 - override) + override))
	camera.CFrame = CFrame.new(eye) * facing(final)
	wrote, saw = final, now

	if sticky > 0 and not onTarget then
		onTarget = crosses(part, eye, facing(final).LookVector) ~= nil
	end
end

-- a left click at the screen centre, returning whether it was sent; never while the menu is open, which it would click
local function fire(camera)
	local now = os.clock()
	if now - lastShot < FIRE_DELAY or hub.ui.visible() then
		return false
	end
	lastShot = now

	local center = camera.ViewportSize / 2
	clicking = true
	VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
	task.delay(FIRE_HOLD, function()
		VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
		clicking = false
	end)
	return true
end

-- the target whose trigger hitgroups the view ray enters first with nothing in the way
local function underCrosshair(camera)
	local eye = camera.CFrame.Position
	local forward = camera.CFrame.LookVector
	local nearest, best

	eachTarget(function(model, root)
		local offset = root.Position - eye
		local along = offset:Dot(forward)
		if along <= 0 or (offset - forward * along).Magnitude > TRIGGER_REACH then
			return
		end
		for _, part in hitParts(model, settings.TriggerHitgroups) do
			local distance = crosses(part, eye, forward)
			if distance
				and distance <= settings.MaxDistance
				and (not best or distance < best)
				and (not settings.VisibilityCheck or isVisible(camera, eye + forward * distance, model)) then
				nearest, best = model, distance
			end
		end
	end)

	return nearest
end

-- a target that drops out of the list or out of sight starts over
local function updateSeen(camera, now)
	local seen = {}
	eachTarget(function(model, root)
		local head = model:FindFirstChild("Head") or root
		if isVisible(camera, head.Position, model) then
			seen[model] = seenSince[model] or now
		end
	end)
	seenSince = seen
end

-- a trigger time in seconds; randomize rolls it between half and one and a half times its setting
local function roll(milliseconds)
	local seconds = milliseconds / 1000
	return settings.TriggerRandomize and random:NextNumber(seconds * 0.5, seconds * 1.5) or seconds
end

-- starline's triggerbot: clicks while a target is under the crosshair, once its delays have run
local function trigger(camera, now)
	-- the user is firing themselves
	if UserInputService:IsMouseButtonPressed(FIRE_BUTTON) and not clicking then
		return
	end
	-- sampled every third frame, as starline does every third command
	frame += 1
	if settings.TriggerVisibleDelay > 0 and frame % 3 == 0 then
		updateSeen(camera, now)
	end

	-- after a shot it keeps firing for the burst time, target or not
	if burstUntil then
		if now < burstUntil then
			fire(camera)
			return
		end
		burstUntil = nil
	end

	local model = underCrosshair(camera)
	if not model then
		acquired, served, reaction = nil, false, nil
		return
	end
	-- rolled once each time a target comes under the crosshair
	if not reaction then
		reaction, visibleFor = roll(settings.TriggerDelay), roll(settings.TriggerVisibleDelay)
	end
	if visibleFor > 0 and now - (seenSince[model] or now) < visibleFor then
		return
	end
	if not served then
		acquired = acquired or now
		if now - acquired < reaction then
			return
		end
		served = true
	end

	if fire(camera) then
		acquired, served, reaction = nil, false, nil
		if settings.TriggerBurst > 0 then
			burstUntil = now + roll(settings.TriggerBurst)
		end
	end
end

function aim.start()
	local circle = Drawing.new("Circle")
	circle.Thickness = 1
	circle.NumSides = 64

	-- bound after the camera update so the game's camera script doesn't overwrite the aim
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		local now = os.clock()
		local blocked = table.find(settings.Disablers, "Jump") ~= nil and airborne(camera)

		local model, part, point
		local fov = settings.Fov
		if settings.Enabled and not blocked then
			model, part, point, fov = findTarget(camera)
		end
		aim.target = part
		esp.highlight = settings.TargetColor and model or nil

		-- the FOV is an angle, so its radius on screen follows the camera's field of view
		local viewport = camera.ViewportSize
		circle.Visible = settings.Enabled and settings.DrawFov
		circle.Color = settings.FovColor
		circle.Position = viewport / 2
		circle.Radius = math.tan(math.rad(fov)) / math.tan(math.rad(camera.FieldOfView / 2)) * viewport.Y / 2

		-- starline's switch delay: a new target isn't pulled to until it has run
		if model and settings.SwitchDelay > 0 and model ~= switchTarget then
			switchTarget, switchUntil = model, now + settings.SwitchDelay / 1000
		end
		if point and now >= switchUntil and UserInputService:IsMouseButtonPressed(AIM_BUTTON) then
			pull(camera, part, point, dt)
		else
			wrote, onTarget, progress = nil, false, 0
		end

		if part and settings.AutoFire then
			fire(camera)
		end
		if settings.Trigger and not blocked then
			trigger(camera, now)
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
