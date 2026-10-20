local hub = ...

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local esp = hub.require("games/universal/esp.lua")

-- seconds between clicks, and how long each click is held
local FIRE_DELAY = 0.05
local FIRE_HOLD = 0.02
-- Roblox's default field of view, which a dynamic FOV is scaled against
local DEFAULT_FOV = 70
-- the range a dynamic FOV shrinks over, in studs
local FOV_RANGE = 500
-- the trigger only tests targets whose root is this near the view ray: starline's 64 units, about a character's height
local TRIGGER_REACH = 6
-- how far the ground ray is moved on past the user's own legs
local STEP_PAST = 0.05
local AXES = { "X", "Y", "Z" }
-- the hitgroups are the parts of an R15 body, with the R6 parts that stand in for them
local HITGROUPS = {
	head = { "Head" },
	["upper torso"] = { "UpperTorso", "Torso" },
	["lower torso"] = { "LowerTorso" },
	arms = { "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "Left Arm", "Right Arm" },
	hands = { "LeftHand", "RightHand" },
	legs = { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "Left Leg", "Right Leg" },
	feet = { "LeftFoot", "RightFoot" },
}

-- main.lua sets aim.blocked, a function that returns true while the aim and the trigger must stay off. Angles here are
-- pitch and yaw in degrees kept as two numbers, since Matcha documents no Vector2 arithmetic
local aim = {
	settings = {
		Enabled = false,
		DrawFov = false,
		FovColor = Color3.new(1, 1, 1),
		Disablers = {},
		Selection = "fov",
		FovMode = "static",
		Fov = 10,
		Hitgroups = { "head" },
		Multipoint = false,
		MultipointScale = 50,
		Smoothing = false,
		SmoothingValue = 5,
		Humanization = 0,
		Sticky = 0,
		SwitchDelay = 0,
		MouseOverride = 100,
		Trigger = false,
		TriggerHitgroups = { "head", "upper torso", "lower torso", "arms", "hands", "legs", "feet" },
		TriggerDelay = 0,
		TriggerVisibleDelay = 0,
		TriggerBurst = 0,
		TriggerRandomize = false,
		MaxDistance = 10000,
	},
}

local settings = aim.settings
local lastShot = 0
-- true while the trigger's click is held down, until clickUntil
local clicking = false
local clickUntil = 0
-- the view written last frame and the one shown before it; nil while not pulling
local wroteP, wroteY, sawP, sawY
-- sticky smoothing: the part being pulled to, whether the crosshair has reached it, and the 0 to 1 ramp since it did
local lockedPart, onTarget, progress = nil, false, 0
local switchTarget
local switchUntil = 0
-- trigger: when each target was first seen, by its Address, and the delays rolled for the one now under the crosshair
local seenSince = {}
local frame = 0
local acquired, served, reaction, visibleFor, burstUntil

local isVisible = esp.visible

-- Matcha documents no Random; a number between min and max
local function between(min, max)
	return min + math.random() * (max - min)
end

-- nothing under the user's root within reach of its feet, which the esp puts 1.5 root heights down. Matcha documents no
-- RaycastParams, so the ray is moved on past the user's own legs
local function airborne()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local origin, left = root.Position, root.Size.Y * 1.75
	for _ = 1, 8 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -left, 0))
		if not hit then
			return true
		end
		if not hit.Instance:IsDescendantOf(character) then
			return false
		end
		left -= origin.Y - hit.Position.Y + STEP_PAST
		origin = Vector3.new(origin.X, hit.Position.Y - STEP_PAST, origin.Z)
		if left <= 0 then
			return true
		end
	end
	return true
end

-- calls back with every live enemy the aim may target, its root part and its health. A player whitelisted on the list
-- page isn't one
local function eachTarget(callback)
	for _, model in esp.enemies.models() do
		local health = esp.health(model)
		if not (health and health <= 0) and not esp.override(model).whitelist then
			callback(model, model.HumanoidRootPart, health)
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
		table.insert(parts, model.HumanoidRootPart)
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
	local near = FOV_RANGE * 0.3
	if distance <= near then
		return fov * (1.5 - 0.5 * distance / near)
	end
	return fov * (1 - 0.7 * math.clamp((distance - near) / (FOV_RANGE - near), 0, 1))
end

-- starline's "closest" hitbox selection: of a model's chosen parts, the point in plain sight nearest the crosshair
local function evaluate(camera, model, forward, fov)
	local eye = camera.CFrame.Position
	local bestPart, bestPoint, bestAngle

	local function consider(part, point)
		local angle = math.deg(forward:Angle(point - eye))
		if angle <= fov and not (bestAngle and angle >= bestAngle) and isVisible(camera, point, model) then
			bestPart, bestPoint, bestAngle = part, point, angle
		end
	end

	for _, part in hitParts(model, settings.Hitgroups) do
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

-- starline's target selection: the target with the best key that has a point inside its FOV, one the list page has as
-- high priority before any that isn't. The last value is the FOV to draw, which in dynamic mode follows the enemy
-- nearest the crosshair
local function findTarget(camera)
	local eye = camera.CFrame.Position
	local forward = camera.CFrame.LookVector
	local dynamic = settings.FovMode == "dynamic"
	-- a dynamic FOV keeps its size on screen when the view zooms
	local zoom = dynamic and camera.FieldOfView / DEFAULT_FOV or 1
	local base = settings.Fov * zoom
	local drawn, nearest = base, base * 1.5
	local bestModel, bestPart, bestPoint, bestScore, bestFirst

	eachTarget(function(model, root, health)
		local offset = root.Position - eye
		local distance = offset.Magnitude
		if distance > settings.MaxDistance then
			return
		end

		local override = esp.override(model)
		local angle = math.deg(forward:Angle(offset))
		local fov = base
		if dynamic then
			fov = scaleFov(base, distance)
			if angle < nearest then
				nearest, drawn = angle, fov
			end
		end
		-- the list page's fov amount is that player's own max fov
		if override.fov then
			fov = override.fov * zoom
			if dynamic then
				fov = scaleFov(fov, distance)
			end
		end

		local score = distance
		if settings.Selection == "fov" then
			score = angle
		elseif settings.Selection == "health" then
			score = health or math.huge
		end
		local first = override.priority or false
		if not bestScore or first and not bestFirst or first == bestFirst and score < bestScore then
			local part, point = evaluate(camera, model, forward, fov)
			if part then
				bestModel, bestPart, bestPoint, bestScore, bestFirst = model, part, point, score, first
			end
		end
	end)

	return bestModel, bestPart, bestPoint, drawn
end

local function wrap(angle)
	return (angle + 180) % 360 - 180
end

-- a CFrame's pitch and yaw in degrees
local function angles(cframe)
	local pitch, yaw = cframe:ToOrientation()
	return math.deg(pitch), math.deg(yaw)
end

local function facing(pitch, yaw)
	return CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), 0)
end

-- pitch and yaw of the direction from one point to another, in degrees. Matcha documents no CFrame.lookAt
local function aimAt(eye, point)
	local direction = (point - eye).Unit
	return math.deg(math.asin(math.clamp(direction.Y, -1, 1))), math.deg(math.atan2(-direction.X, -direction.Z))
end

-- starline's smoothing and humanization: how much of the turn that is left to make this frame
local function smooth(dx, dy, weight, dt)
	local distance = math.sqrt(dx * dx + dy * dy)
	if distance < 0.01 then
		return 0, 0
	end
	local rest = 1 - weight
	local human = math.clamp(rest * settings.Humanization, 0, 100) / 100

	-- the divisor runs from 1 to the smoothing value, and back to 1 as the sticky weight grows
	local divisor = rest * (math.max(settings.SmoothingValue, 1) - 1) + 1
	if human > 0 then
		divisor = math.max(between(divisor * (1 - human / 2), divisor * (1 + human / 2)), 1)
		-- slows down inside 10 degrees: 0.75 of the divisor far out, 1.25 on the target
		local close = distance < 10 and 1 - distance / 10 or 0
		divisor *= 0.5 * close * close * (3 - 2 * close) + 0.75
	end
	local share = 1
	if divisor > 1 then
		-- what 1 / divisor a tick comes to at 128 ticks a second, so the speed doesn't follow the frame rate
		share = 1 - (1 - 1 / divisor) ^ math.clamp(dt * 128, 0.01, 16)
	end
	local sx, sy = dx * share, dy * share

	-- a curved path: the straight step blended with a bezier whose middle is pushed 0.15 of the turn sideways
	local curve = math.min(0.6, human * 0.8)
	if curve > 0 then
		local mx, my = dx * 0.5 - dy * 0.15, dy * 0.5 + dx * 0.15
		local bx = dx * share * share + mx * 2 * share * (1 - share)
		local by = dy * share * share + my * 2 * share * (1 - share)
		sx, sy = sx * (1 - curve) + bx * curve, sy * (1 - curve) + by * curve
	end
	-- sideways jitter above 40% humanization
	if human > 0.4 and math.sqrt(sx * sx + sy * sy) >= 0.001 then
		local jitter = between(-(human - 0.4) * 0.6, (human - 0.4) * 0.6) * 0.1
		sx, sy = sx - sy * jitter, sy + sx * jitter
	end
	-- a tremor of up to 0.06 degrees
	local tremor = human * 0.06
	if tremor > 0 then
		sx += between(-tremor, tremor)
		sy += between(-tremor, tremor)
	end
	-- above 70%, one frame in five overshoots a little when it is nearly there
	local length = math.sqrt(sx * sx + sy * sy)
	if distance > 0.2 and distance < 0.5 and human > 0.7 and math.random() < 0.2 and length > 0.01 then
		local more = between(0.2, 0.5) / length
		sx, sy = sx + sx * more, sy + sy * more
	end
	return sx, sy
end

-- starline's mouse side: turns the view towards the point, keeping what the settings leave of the user's own movement
local function pull(camera, part, point, dt)
	local eye = camera.CFrame.Position
	local nowP, nowY = angles(camera.CFrame)
	local viewP, viewY, userP, userY = nowP, nowY, 0, 0
	if wroteP then
		-- a game that keeps its own view angles shows the view it had, not the one written last frame,
		-- so the user's movement is measured from whichever of the two the new view is nearer
		local fromWrote = math.sqrt(wrap(nowP - wroteP) ^ 2 + wrap(nowY - wroteY) ^ 2)
		local fromSaw = math.sqrt(wrap(nowP - sawP) ^ 2 + wrap(nowY - sawY) ^ 2)
		local baseP, baseY = wroteP, wroteY
		if fromSaw < fromWrote then
			baseP, baseY = sawP, sawY
		end
		viewP, viewY = wroteP, wroteY
		userP, userY = wrap(nowP - baseP), wrap(nowY - baseY)
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
		onTarget = crosses(part, eye, facing(viewP, viewY).LookVector) ~= nil
	end
	local weight = sticky * progress * progress * (3 - 2 * progress)

	local targetP, targetY = aimAt(eye, point)
	local stepP, stepY = wrap(targetP - viewP), wrap(targetY - viewY)
	if settings.Smoothing and weight < 1 then
		stepP, stepY = smooth(stepP, stepY, weight, dt)
	end

	-- the override, and the sticky weight on top of it, is the share of the user's own movement that is dropped
	local override = settings.MouseOverride / 100
	local keep = 1 - (weight * (1 - override) + override)
	local finalP, finalY = viewP + stepP + userP * keep, viewY + stepY + userY * keep
	camera.CFrame = CFrame.new(eye.X, eye.Y, eye.Z) * facing(finalP, finalY)
	wroteP, wroteY, sawP, sawY = finalP, finalY, nowP, nowY

	if sticky > 0 and not onTarget then
		onTarget = crosses(part, eye, facing(finalP, finalY).LookVector) ~= nil
	end
end

-- the trigger's click, released from the render loop because Matcha's task.delay never runs its callback. Matcha
-- doesn't say whether its menu is open, so a click can land on it
local function fire(now)
	if clicking or now - lastShot < FIRE_DELAY then
		return false
	end
	lastShot = now
	clickUntil = now + FIRE_HOLD
	mouse1press()
	clicking = true
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
			if distance and distance <= settings.MaxDistance and (not best or distance < best) and isVisible(camera, eye + forward * distance, model) then
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
			seen[model.Address] = seenSince[model.Address] or now
		end
	end)
	seenSince = seen
end

-- a trigger time in seconds; randomize rolls it between half and one and a half times its setting
local function roll(milliseconds)
	local seconds = milliseconds / 1000
	return settings.TriggerRandomize and between(seconds * 0.5, seconds * 1.5) or seconds
end

-- starline's triggerbot: clicks while a target is under the crosshair, once its delays have run
local function trigger(camera, now)
	-- the user is firing themselves
	if ismouse1pressed() and not clicking then
		return
	end
	-- sampled every third frame, as starline does every third command. Whatever the setting, since the list page can
	-- give one player a visible delay
	frame += 1
	if frame % 3 == 0 then
		updateSeen(camera, now)
	end

	-- after a shot it keeps firing for the burst time, target or not
	if burstUntil then
		if now < burstUntil then
			fire(now)
			return
		end
		burstUntil = nil
	end

	local model = underCrosshair(camera)
	if not model then
		acquired, served, reaction = nil, false, nil
		return
	end
	-- rolled once each time a target comes under the crosshair. The list page's trigger reaction is that player's own
	-- visible delay
	if not reaction then
		reaction = roll(settings.TriggerDelay)
		visibleFor = roll(esp.override(model).reaction or settings.TriggerVisibleDelay)
	end
	if visibleFor > 0 and now - (seenSince[model.Address] or now) < visibleFor then
		return
	end
	if not served then
		acquired = acquired or now
		if now - acquired < reaction then
			return
		end
		served = true
	end

	if fire(now) then
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

	-- RenderStepped is Matcha's only frame callback, so the aim doesn't run just after the camera update
	hub.cleanup.add(RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local now = tick()
		local blocked = aim.blocked() or table.find(settings.Disablers, "jump") ~= nil and airborne()

		if clicking and now >= clickUntil then
			mouse1release()
			clicking = false
		end

		local model, part, point
		local fov = settings.Fov
		if settings.Enabled and not blocked then
			model, part, point, fov = findTarget(camera)
		end

		-- the FOV is an angle, so its radius on screen follows the camera's field of view
		local viewport = camera.ViewportSize
		circle.Visible = settings.Enabled and settings.DrawFov
		circle.Color = settings.FovColor
		circle.Position = Vector2.new(viewport.X / 2, viewport.Y / 2)
		circle.Radius = math.tan(math.rad(fov)) / math.tan(math.rad(camera.FieldOfView / 2)) * viewport.Y / 2

		-- starline's switch delay: a new target isn't pulled to until it has run
		if model and settings.SwitchDelay > 0 and model ~= switchTarget then
			switchTarget, switchUntil = model, now + settings.SwitchDelay / 1000
		end
		if point and now >= switchUntil then
			pull(camera, part, point, dt)
		else
			wroteP, onTarget, progress = nil, false, 0
		end

		if settings.Trigger and not blocked then
			trigger(camera, now)
		end
	end))

	hub.cleanup.add(function()
		circle:Remove()
		if clicking then
			mouse1release()
			clicking = false
		end
	end)
end

return aim
