local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local CollectionService = cloneref(game:GetService("CollectionService"))
local HttpService = cloneref(game:GetService("HttpService"))
local UserInputService = cloneref(game:GetService("UserInputService"))

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local RED = Color3.fromRGB(230, 60, 60)
-- a CS2 unit in studs, for starline's max distance
local UNIT = 0.075
local ICON_SIZE = Vector2.new(36, 14)
-- the game's grenade physics runs in steps of this many seconds (GrenadeSimulator.Constants.FIXED_TIMESTEP)
local SIM_STEP = 0.0078125
-- a path is followed for this many steps, 3 s, and a point of it kept every so many
local PATH_STEPS = 384
local PATH_EVERY = 8
-- seconds between a flying grenade's path being worked out again
local PATH_TIME = 0.1
-- the proximity warning is for a grenade that will end up within this many studs of the camera
local WARN_RANGE = 15
local CIRCLE_SIDES = 24
-- how fine the ground under a fire or a smoke is cut up to find the outline of what it covers, in studs
local CELL = 0.5
-- the fade inside such an outline: how far in from the line it reaches in studs, in how many steps, and how solid it is
-- at the line
local EDGE_REACH, EDGE_STEPS, EDGE_OPACITY = 2, 4, 0.4
-- an outline is made round: points this many studs apart along it, no more than this many, each then moved towards the
-- two beside it this many times over
local ROUND_SPACING, ROUND_POINTS, ROUND_PASSES = 0.75, 48, 6
-- nothing nearer the camera than this many studs is drawn: a place that close lands far off the screen, and one behind
-- the camera on the wrong side of it
local NEAR = 0.3
-- the game destroys a smoke's folder this long after the smoke itself has gone (VFXLibary.CreateVoxelSmoke)
local FADE = { Smoke = 6, Fire = 0 }
-- the game's tags for a thrown grenade, a weapon on the ground and the planted bomb
local GRENADE_TAG = "Grenade"
local DROPPED_TAG = "WeaponDropped"
local BOMB_TAG = "Bomb"
-- the grenades by weapon name (Database.Custom.GameStats.Grenades), and whether one burns where it lands
local GRENADES = {
	["HE Grenade"] = false,
	["Smoke Grenade"] = false,
	["Decoy Grenade"] = false,
	Flashbang = false,
	Molotov = true,
	["Incendiary Grenade"] = true,
}

-- main.lua sets entities.files, the folder of the game's weapon files, for the icons, and entities.velocity, a function
-- that returns the velocity the user's character has, for the grenade prediction
local entities = {
	settings = {
		Projectiles = false,
		ProjectileBox = false,
		ProjectileBoxColor = WHITE,
		ProjectileName = false,
		ProjectileNameColor = WHITE,
		ProjectileIcon = false,
		ProjectileIconColor = WHITE,
		ProjectileGlow = false,
		ProjectileGlowColor = WHITE,
		Prediction = false,
		PredictionPin = false,
		Trajectory = false,
		TrajectoryWarning = false,
		Timers = false,
		TimersColor = WHITE,
		Inferno = false,
		InfernoColor = Color3.fromRGB(255, 130, 40),
		Smoke = false,
		SmokeColor = Color3.fromRGB(170, 170, 170),
		Dropped = false,
		DroppedBox = false,
		DroppedBoxColor = WHITE,
		DroppedName = false,
		DroppedNameColor = WHITE,
		DroppedIcon = false,
		DroppedIconColor = WHITE,
		DroppedGlow = false,
		DroppedGlowColor = WHITE,
		DroppedDistance = 1000,
		Bomb = false,
		BombScreen = false,
		BombWorld = false,
		BombShow = { "name", "timer", "distance" },
	},
}

local settings = entities.settings
local container, screen
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = false
rayParams.IgnoreWater = true

local debris = workspace:FindFirstChild("Debris")
if not debris then
	warn("[hub] workspace.Debris not found: no grenade timers or spreads")
	hub.ui.notify("workspace.Debris not found, no grenade timers or spreads", "error")
end

-- the game's own grenade physics, which the paths are worked out with
local shared = ReplicatedStorage:FindFirstChild("Shared")
local simulatorFile = shared and shared:FindFirstChild("GrenadeSimulator")
local simulator = simulatorFile and require(simulatorFile)
if not simulator then
	warn("[hub] ReplicatedStorage.Shared.GrenadeSimulator not found: no grenade prediction or trajectory")
	hub.ui.notify("ReplicatedStorage.Shared.GrenadeSimulator not found, no grenade prediction or trajectory", "error")
end
local assets = ReplicatedStorage:FindFirstChild("Assets")
local weaponModels = assets and assets:FindFirstChild("Weapons")

-- everything here is drawn anew each frame. A drawing asked for is the one that was handed out at the same place in
-- the frame before, and those not asked for this frame are hidden when it ends. The same goes for the image labels
-- the icons are, since a Drawing image can't show a Roblox asset, and the Highlights the glows are
local pools = { Line = {}, Text = {}, Square = {}, Quad = {}, Triangle = {}, Image = {}, Glow = {} }
local used = { Line = 0, Text = 0, Square = 0, Quad = 0, Triangle = 0, Image = 0, Glow = 0 }

local function take(class)
	used[class] += 1
	local index = used[class]
	local object = pools[class][index]
	if not object then
		if class == "Image" then
			object = Instance.new("ImageLabel")
			object.BackgroundTransparency = 1
			object.ScaleType = Enum.ScaleType.Fit
			object.Parent = screen
		elseif class == "Glow" then
			object = Instance.new("Highlight")
			object.FillTransparency = 1
			object.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			object.Parent = container
		else
			object = Drawing.new(class)
			if class == "Text" then
				object.Size = 13
				object.Center = true
				object.Outline = true
			else
				object.Thickness = 1
				-- the quads and triangles are the fades inside the spreads' outlines
				if class == "Quad" or class == "Triangle" then
					object.Filled = true
				end
			end
		end
		pools[class][index] = object
	end
	return object
end

local function finish()
	for class, pool in pools do
		for index = used[class] + 1, #pool do
			local object = pool[index]
			if class == "Glow" then
				object.Enabled = false
				object.Adornee = nil
			else
				object.Visible = false
			end
		end
		used[class] = 0
	end
end

local function line(from, to, color)
	local object = take("Line")
	object.From = from
	object.To = to
	object.Color = color
	object.Visible = true
end

local function text(words, at, color)
	local object = take("Text")
	object.Text = words
	object.Position = at
	object.Color = color
	object.Visible = true
end

-- a line between two places in the world, left out when either is behind the camera
local function worldLine(camera, from, to, color)
	local a, b = camera:WorldToViewportPoint(from), camera:WorldToViewportPoint(to)
	if a.Z > 0 and b.Z > 0 then
		line(Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y), color)
	end
end

-- words at a place in the world
local function worldText(camera, words, at, color)
	local point = camera:WorldToViewportPoint(at)
	if point.Z > 0 then
		text(words, Vector2.new(point.X, point.Y), color)
	end
end

-- a circle lying flat in the world
local function ring(camera, center, radius, color)
	local last
	for side = 0, CIRCLE_SIDES do
		local angle = side / CIRCLE_SIDES * 2 * math.pi
		local point = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		if last then
			worldLine(camera, last, point, color)
		end
		last = point
	end
end

-- how high the surface a fire's plate lies on is, or the floor of a smoke's block, at a place over or under it
local function heightAt(plate, x, z)
	return plate.base.Y - (plate.up.X * (x - plate.base.X) + plate.up.Z * (z - plate.base.Z)) / plate.up.Y
end

local function cellKey(i, j)
	return i * 65536 + j
end

-- a loop of corners along the ground, as x and z, made round: points every so far along it, each then moved towards
-- the two beside it a few times over
local function rounded(corners)
	local length = 0
	for index, corner in corners do
		length += (corners[index % #corners + 1] - corner).Magnitude
	end
	local gap = length / math.clamp(math.round(length / ROUND_SPACING), 8, ROUND_POINTS)
	local points = {}
	-- how far along the side it is on the next point goes
	local along = 0
	for index, corner in corners do
		local after = corners[index % #corners + 1]
		local side = (after - corner).Magnitude
		while along < side do
			table.insert(points, corner:Lerp(after, along / side))
			along += gap
		end
		along -= side
	end
	for _ = 1, ROUND_PASSES do
		local moved = {}
		for index, point in points do
			moved[index] = (points[(index - 2) % #points + 1] + point * 2 + points[index % #points + 1]) / 4
		end
		points = moved
	end
	return points
end

-- the outline of the ground a fire's plates or a smoke's blocks cover. The game lays a fire's plates flat on whatever
-- they landed on, sides along x and z, so the ground is cut into cells, each with the plate over it; the cell sides
-- with nothing beyond them are followed round, the covered ground to the left, and that loop is made round. It comes
-- as loops of points, each with its place on the ground at every step of the fade (world, the line first) and room for
-- how far in front of the camera and where on screen those are (depth, screen)
local function outline(parts)
	local cells = {}
	local lowI, highI, lowJ, highJ = math.huge, -math.huge, math.huge, -math.huge
	for _, part in parts do
		local cframe, half = part.CFrame, part.Size / 2
		local up = cframe.UpVector
		-- a plate on a wall covers no ground
		if up.Y > 0.1 then
			local plate = { base = part.Position - up * half.Y, up = up }
			local right, back = cframe.RightVector, cframe.ZVector
			local reachX = math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(back.X) * half.Z
			local reachZ = math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(back.Z) * half.Z
			local x, z = part.Position.X, part.Position.Z
			-- the cells whose middles are under it
			for i = math.ceil((x - reachX) / CELL - 0.5), math.floor((x + reachX) / CELL - 0.5) do
				for j = math.ceil((z - reachZ) / CELL - 0.5), math.floor((z + reachZ) / CELL - 0.5) do
					local key = cellKey(i, j)
					-- of two over one cell the lower is the ground: a smoke's blocks are stacked
					if not cells[key] or plate.base.Y < cells[key].base.Y then
						cells[key] = plate
					end
					lowI, highI = math.min(lowI, i), math.max(highI, i)
					lowJ, highJ = math.min(lowJ, j), math.max(highJ, j)
				end
			end
		end
	end

	-- how high the ground is at a place. The round outline leaves the covered cells at their corners, and there the
	-- surface of a covered cell close by is carried on
	local function ground(x, z)
		local i, j = math.floor(x / CELL), math.floor(z / CELL)
		for reach = 0, 4 do
			for di = -reach, reach do
				for dj = -reach, reach do
					local plate = cells[cellKey(i + di, j + dj)]
					if plate then
						return heightAt(plate, x, z)
					end
				end
			end
		end
		return nil
	end

	-- the sides, by the corner each starts from
	local sides = {}
	local function side(i, j, toI, toJ)
		local key = cellKey(i, j)
		sides[key] = sides[key] or {}
		table.insert(sides[key], { i = i, j = j, toI = toI, toJ = toJ })
	end
	for i = lowI, highI do
		for j = lowJ, highJ do
			if cells[cellKey(i, j)] then
				if not cells[cellKey(i, j - 1)] then
					side(i, j, i + 1, j)
				end
				if not cells[cellKey(i + 1, j)] then
					side(i + 1, j, i + 1, j + 1)
				end
				if not cells[cellKey(i, j + 1)] then
					side(i + 1, j + 1, i, j + 1)
				end
				if not cells[cellKey(i - 1, j)] then
					side(i, j + 1, i, j)
				end
			end
		end
	end

	local loops = {}
	for _, list in sides do
		for _, first in list do
			if not first.used then
				-- round from one side to the next that starts where it ends, until none is left there
				local corners = {}
				local at = first
				while at do
					at.used = true
					table.insert(corners, Vector2.new(at.i, at.j) * CELL)
					local following = sides[cellKey(at.toI, at.toJ)]
					at = nil
					for _, candidate in following do
						if not candidate.used then
							at = candidate
							break
						end
					end
				end

				local points = rounded(corners)
				local loop = {}
				for index, point in points do
					local way = points[index % #points + 1] - points[(index - 2) % #points + 1]
					local y = ground(point.X, point.Y)
					-- a loop too small to have a way round after the rounding is left out
					if way.Magnitude > 0 and y then
						-- the way in is to the left of the way round
						local inward = Vector2.new(-way.Y, way.X).Unit
						local world = { [0] = Vector3.new(point.X, y, point.Y) }
						for step = 1, EDGE_STEPS do
							local inner = point + inward * (step / EDGE_STEPS * EDGE_REACH)
							local under = cells[cellKey(math.floor(inner.X / CELL), math.floor(inner.Y / CELL))]
							-- where the covered ground is narrower than the fade, the fade ends at its far side
							world[step] = under and Vector3.new(inner.X, heightAt(under, inner.X, inner.Y), inner.Y)
								or world[step - 1]
						end
						table.insert(loop, { world = world, depth = {}, screen = {} })
					end
				end
				if #loop > 2 then
					table.insert(loops, loop)
				end
			end
		end
	end
	return loops
end

local function onScreen(camera, place)
	local point = camera:WorldToViewportPoint(place)
	return Vector2.new(point.X, point.Y)
end

-- a filled shape with corners in the world, given with how far in front of the camera each is, cut off where it comes
-- nearer than NEAR
local function cut(camera, places, depths, color, opacity)
	local kept = {}
	for index, place in places do
		local after = index % #places + 1
		local depth, beyond = depths[index], depths[after]
		if depth > NEAR then
			table.insert(kept, onScreen(camera, place))
		end
		if (depth > NEAR) ~= (beyond > NEAR) then
			table.insert(kept, onScreen(camera, place:Lerp(places[after], (NEAR - depth) / (beyond - depth))))
		end
	end
	for index = 2, #kept - 1 do
		local triangle = take("Triangle")
		triangle.PointA, triangle.PointB, triangle.PointC = kept[1], kept[index], kept[index + 1]
		triangle.Color = color
		triangle.Transparency = opacity
		triangle.Visible = true
	end
end

-- an outline's lines, and inside them its colour fading out over the steps
local function spread(camera, loops, color)
	for _, loop in loops do
		for _, corner in loop do
			for step = 0, EDGE_STEPS do
				local point = camera:WorldToViewportPoint(corner.world[step])
				corner.depth[step] = point.Z
				corner.screen[step] = Vector2.new(point.X, point.Y)
			end
		end
		for index, a in loop do
			local b = loop[index % #loop + 1]
			local near, far = a.depth[0], b.depth[0]
			if near > NEAR and far > NEAR then
				line(a.screen[0], b.screen[0], color)
			elseif near > NEAR then
				line(a.screen[0], onScreen(camera, a.world[0]:Lerp(b.world[0], (NEAR - near) / (far - near))), color)
			elseif far > NEAR then
				line(onScreen(camera, a.world[0]:Lerp(b.world[0], (NEAR - near) / (far - near))), b.screen[0], color)
			end

			for step = 1, EDGE_STEPS do
				local before = step - 1
				local opacity = EDGE_OPACITY * (1 - (step - 0.5) / EDGE_STEPS)
				local depths = { a.depth[before], b.depth[before], b.depth[step], a.depth[step] }
				local ahead = 0
				for _, depth in depths do
					if depth > NEAR then
						ahead += 1
					end
				end
				if ahead == 4 then
					local quad = take("Quad")
					quad.PointA, quad.PointB = a.screen[before], b.screen[before]
					quad.PointC, quad.PointD = b.screen[step], a.screen[step]
					quad.Color = color
					quad.Transparency = opacity
					quad.Visible = true
				elseif ahead > 0 then
					cut(camera, { a.world[before], b.world[before], b.world[step], a.world[step] }, depths, color, opacity)
				end
			end
		end
	end
end

-- the corners on screen of the box round a model, or nil when any of it is behind the camera
local function bounds(camera, model)
	local cframe, size = model:GetBoundingBox()
	local low, high = Vector2.one * math.huge, Vector2.one * -math.huge
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local point = camera:WorldToViewportPoint(cframe * (size * Vector3.new(x, y, z) / 2))
				if point.Z <= 0 then
					return nil
				end
				local at = Vector2.new(point.X, point.Y)
				low, high = low:Min(at), high:Max(at)
			end
		end
	end
	return low, high
end

-- the game's file on a weapon, by its name
local function weaponFile(name)
	local file = entities.files and entities.files:FindFirstChild(name)
	return file and require(file)
end

-- the box, name, icon and glow of a grenade or a dropped weapon. rows is Projectile or Dropped, what its rows'
-- settings begin with; warned draws the name in red
local function tag(camera, model, rows, name, warned)
	if settings[rows .. "Glow"] then
		local glow = take("Glow")
		glow.Adornee = model
		glow.OutlineColor = settings[rows .. "GlowColor"]
		glow.Enabled = true
	end
	local low, high = bounds(camera, model)
	if not low then
		return
	end
	if settings[rows .. "Box"] then
		for _, look in { { 3, BLACK }, { 1, settings[rows .. "BoxColor"] } } do
			local box = take("Square")
			box.Thickness = look[1]
			box.Color = look[2]
			box.Position = low
			box.Size = high - low
			box.Visible = true
		end
	end
	local middle = (low.X + high.X) / 2
	if settings[rows .. "Name"] then
		text(name:lower(), Vector2.new(middle, low.Y - 15), warned and RED or settings[rows .. "NameColor"])
	end
	local properties = settings[rows .. "Icon"] and weaponFile(name)
	if properties and properties.Icon then
		local icon = take("Image")
		icon.Image = properties.Icon
		icon.ImageColor3 = settings[rows .. "IconColor"]
		icon.Position = UDim2.fromOffset(middle - ICON_SIZE.X / 2, high.Y + 2)
		icon.Size = UDim2.fromOffset(ICON_SIZE.X, ICON_SIZE.Y)
		icon.Visible = true
	end
end

-- the way a grenade goes from a state of the game's simulator, by that simulator: points along it until it comes to
-- rest, which is also how the simulator marks one that has gone off, or the steps run out
local function path(state, radius, burns)
	local config = simulator.createConfig(radius, 1, false, nil, nil, burns or nil)
	local points = { state.position }
	for step = 1, PATH_STEPS do
		state = simulator.step(state, config, rayParams, SIM_STEP)
		if step % PATH_EVERY == 0 or state.isAtRest then
			table.insert(points, state.position)
		end
		if state.isAtRest then
			break
		end
	end
	return points
end

local function drawPath(camera, points, color)
	for index = 2, #points do
		worldLine(camera, points[index - 1], points[index], color)
	end
	ring(camera, points[#points], 1, color)
end

-- by grenade, where it was last frame and when, its speed, and the path last worked out for it
local flights = setmetatable({}, { __mode = "k" })

-- half the size of the model a grenade is thrown as, which stands in for the radius the server gives the simulator
local function radiusOf(model)
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Y, size.Z) / 2
end

local function projectiles(camera, now, dt)
	local eye = camera.CFrame.Position
	-- what the game's own grenades pass through
	local ignore = { camera }
	table.insert(ignore, debris)
	table.insert(ignore, Players.LocalPlayer.Character)
	rayParams.FilterDescendantsInstances = ignore

	for _, model in CollectionService:GetTagged(GRENADE_TAG) do
		-- one that has gone off or come to rest is marked, and waits hidden to be destroyed
		if model:IsDescendantOf(workspace) and not model:GetAttribute("SimulationFinished") then
			local name = model:GetAttribute("GrenadeName") or model.Name
			local position = model:GetPivot().Position
			local flight = flights[model]
			if not flight then
				flight = { position = position, velocity = Vector3.zero, at = 0 }
				flights[model] = flight
			end
			-- the game only tells the client where a grenade is, so its speed is taken from how it moves
			flight.velocity = flight.velocity:Lerp((position - flight.position) / dt, 0.5)
			flight.position = position

			local warned = false
			if simulator and settings.Trajectory then
				if now - flight.at > PATH_TIME then
					flight.at = now
					flight.path = path({
						simulationTime = 0,
						bounceCount = 0,
						isGrounded = false,
						isAtRest = false,
						hasTouched = false,
						accumulatedTime = 0,
						position = position,
						velocity = flight.velocity,
						angularVelocity = Vector3.zero,
						timestamp = 0,
						isJumpThrow = false,
					}, radiusOf(model), GRENADES[name])
				end
				local landing = flight.path[#flight.path]
				local away = (landing - eye).Magnitude
				warned = settings.TrajectoryWarning and away <= WARN_RANGE
				drawPath(camera, flight.path, warned and RED or WHITE)
				if warned then
					local size = camera.ViewportSize
					text(string.format("%s %.0f studs", name:lower(), away), Vector2.new(size.X / 2, size.Y * 0.7), RED)
				end
			end
			tag(camera, model, "Projectile", name, warned)
		end
	end

	-- the grenade prediction: the path the grenade in the user's hands would take if it were thrown now. A viewmodel
	-- is a Model under the camera named by its weapon; the left button throws far and the right one alone near
	if simulator and settings.Prediction then
		local held
		for _, model in camera:GetChildren() do
			if model:IsA("Model") and GRENADES[model.Name] ~= nil then
				held = model.Name
			end
		end
		local far = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		local near = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local thrown = held and weaponModels and weaponModels:FindFirstChild(held)
		thrown = thrown and thrown:FindFirstChild("Character")
		if root and thrown and (far or near or not settings.PredictionPin) then
			local kind = near and not far and "Near" or "Far"
			local from, way = simulator.calculateThrowParameters(root.Position, camera.CFrame.LookVector, kind, 1)
			local velocity = entities.velocity and entities.velocity() or Vector3.zero
			local state = simulator.createInitialState(from, way, kind, velocity, 1, 0)
			drawPath(camera, path(state, radiusOf(thrown), GRENADES[held]), WHITE)
		end
	end
end

-- by the folder of a smoke or fire volume: its kind, when it was first seen, its middle at ground level, the outline
-- of the ground it covers, and the first and the number of the parts that outline was worked out from
local clouds = {}
-- by kind, how long the last one stayed, which the timers count down from. Until one has been timed they count up
local lasted = {}

local function volumes(camera, now)
	local seen = {}
	for _, folder in debris:GetChildren() do
		local kind = folder.Name:match("^Voxel(%a+)_")
		if FADE[kind] then
			seen[folder] = true
			local cloud = clouds[folder]
			local parts = {}
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(parts, part)
				end
			end
			if not cloud and #parts > 0 then
				cloud = { kind = kind, began = now }
				clouds[folder] = cloud
			end
			-- the game makes a fire's plates anew as it spreads and dies down
			if cloud and (parts[1] ~= cloud.first or #parts ~= cloud.count) then
				cloud.first, cloud.count = parts[1], #parts
				cloud.shape = outline(parts)
				if #parts > 0 then
					local sum, floor = Vector3.zero, math.huge
					for _, part in parts do
						sum += part.Position
						floor = math.min(floor, part.Position.Y - part.Size.Y / 2)
					end
					local middle = sum / #parts
					cloud.center = Vector3.new(middle.X, floor, middle.Z)
				end
			end
			if cloud then
				local color = kind == "Smoke" and settings.SmokeColor or settings.InfernoColor
				if kind == "Smoke" and settings.Smoke or kind == "Fire" and settings.Inferno then
					spread(camera, cloud.shape, color)
				end
				if settings.Timers then
					local age = now - cloud.began
					local left = lasted[kind] and math.max(lasted[kind] - age, 0) or age
					worldText(camera, string.format("%s %.1f", kind:lower(), left), cloud.center + Vector3.yAxis * 3, settings.TimersColor)
				end
			end
		end
	end
	for folder, cloud in clouds do
		if not seen[folder] then
			lasted[cloud.kind] = now - cloud.began - FADE[cloud.kind]
			clouds[folder] = nil
		end
	end
end

local function dropped(camera)
	local eye = camera.CFrame.Position
	for _, model in CollectionService:GetTagged(DROPPED_TAG) do
		if model:IsDescendantOf(workspace)
			and (model:GetPivot().Position - eye).Magnitude <= settings.DroppedDistance * UNIT then
			tag(camera, model, "Dropped", model:GetAttribute("Weapon") or model.Name)
		end
	end
end

-- by bomb, the server's clock at the moment it goes off
local fuses = setmetatable({}, { __mode = "k" })

local function bomb(camera)
	for _, model in CollectionService:GetTagged(BOMB_TAG) do
		if model:IsDescendantOf(workspace) then
			local fuse = fuses[model]
			if not fuse then
				-- the game keeps when it was planted and how long it has as JSON on the bomb, 40 s without
				local data = HttpService:JSONDecode(model:GetAttribute("BombPlanted"))
				fuse = (data.Time or workspace:GetServerTimeNow()) + (data.TimeUntilExplode or 40)
				fuses[model] = fuse
			end
			local left = math.max(fuse - workspace:GetServerTimeNow(), 0)
			local state = model:GetAttribute("Defused") and "defused"
				or model:GetAttribute("Exploded") and "exploded"
				or string.format("%.1f s", left)
			local position = model:GetPivot().Position
			if settings.BombScreen then
				local size = camera.ViewportSize
				text("bomb " .. state, Vector2.new(size.X / 2, size.Y * 0.18), left < 10 and RED or WHITE)
			end
			if settings.BombWorld then
				local words = {}
				if table.find(settings.BombShow, "name") then
					table.insert(words, "bomb")
				end
				if table.find(settings.BombShow, "timer") then
					table.insert(words, state)
				end
				if table.find(settings.BombShow, "distance") then
					table.insert(words, string.format("%.0f studs", (position - camera.CFrame.Position).Magnitude))
				end
				worldText(camera, table.concat(words, " | "), position, WHITE)
			end
		end
	end
end

local function render(dt)
	local camera = workspace.CurrentCamera
	local now = os.clock()
	if settings.Projectiles then
		projectiles(camera, now, dt)
		if debris and (settings.Timers or settings.Inferno or settings.Smoke) then
			volumes(camera, now)
		end
	end
	if settings.Dropped then
		dropped(camera)
	end
	if settings.Bomb then
		bomb(camera)
	end
	finish()
end

function entities.start()
	container = hub.cleanup.add(Instance.new("Folder"))
	container.Parent = gethui()
	screen = hub.cleanup.add(Instance.new("ScreenGui"))
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = -1
	screen.Parent = gethui()

	hub.cleanup.add(function()
		for _, class in { "Line", "Text", "Square", "Quad", "Triangle" } do
			for _, object in pools[class] do
				object:Remove()
			end
		end
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return entities
