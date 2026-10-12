local hub = ...

local RunService = cloneref(game:GetService("RunService"))

local esp = hub.require("games/bloxstrike/esp.lua")

local movement = {
	settings = {
		bunnyhop = false,
		edgeJump = false,
		longJump = false,
		nullBinds = false,
		nullGround = false,
		autoStrafe = false,
		quickStop = false,
		blockBot = false,
	},
	-- the velocity the last command ran on
	velocity = Vector3.zero,
	-- when each feature last changed a command, by the tag the hud's indicators show it under
	acted = {},
	-- the last time in the air that ended: how fast along the ground it ended, how far it went, both in studs, and
	-- whether it was a long jump. A new table each time
	landing = nil,
}
local settings, acted = movement.settings, movement.acted

-- the game's command buttons (MovementV2.Buttons)
local JUMP, DUCK = 1, 2
local TICK = 1 / 60
-- a Hammer unit in studs (MovementV2.SpeedProfile), which the game's movement figures are given in
local UNIT = 0.075
-- the game's ground accelerate: a move input adds this many times the wish speed a second
local ACCELERATE = 5.5

-- the game sends the jump button for as long as the key is held and its simulation only jumps on a fresh press,
-- so bunnyhop drops the button from every command but the first one on the ground
local function hop(input, state)
	if bit32.band(input.Buttons, JUMP) == 0 then
		return
	end
	-- on the ground with the button already down the jump was refused, so it is released to be pressed again
	if not state.OnGround or bit32.band(state.PreviousButtons, JUMP) ~= 0 then
		input.Buttons -= JUMP
	else
		acted.aj = os.clock()
	end
end

-- a world direction along the ground as a move input for a yaw, the game's ProvenMath.moveVectorToWorld the other way
-- round
local function toMove(x, z, yaw)
	local sin, cos = math.sin(yaw), math.cos(yaw)
	return Vector2.new(cos * x - sin * z, sin * x + cos * z)
end

-- Roblox's own keyboard controller, where the game's movement keys write what they hold: leftValue is -1 with the
-- left strafe key down, rightValue 1 with the right
local keys
for _, object in getgc(true) do
	if type(object) == "table"
		and type(rawget(object, "leftValue")) == "number"
		and type(rawget(object, "rightValue")) == "number" then
		keys = object
		break
	end
end
if not keys then
	warn("[hub] the keyboard controller (leftValue, rightValue) not found: null binds unavailable")
	hub.ui.notify("keyboard controller (leftValue, rightValue) not found, no null binds", "error")
end

-- which strafe keys were down on the last command, and the one pressed last
local wasLeft, wasRight, lastSide = false, false, 0

-- null binds: with both strafe keys down the game moves neither way; the one pressed last wins
local function nullBinds(input, state)
	local left, right = keys.leftValue ~= 0, keys.rightValue ~= 0
	if left and not wasLeft then
		lastSide = -1
	elseif right and not wasRight then
		lastSide = 1
	end
	wasLeft, wasRight = left, right
	if left and right and (settings.nullGround or not state.OnGround) then
		input.Move = Vector2.new(lastSide, input.Move.Y)
		acted.nb = os.clock()
	end
end

-- which way the last strafe went while the view was along the flight
local side = 1

-- a move input is Roblox's: x to the right and y backwards, so the forward key alone is this
local FORWARD = Vector2.new(0, -1)

-- auto strafe: in the air the game adds speed along the move input up to AirSpeedCap, 30 units, whatever the speed
-- already is across it. So the input is turned square to the velocity, towards the side the keys point to, which adds
-- that much every command and bends the flight that way: forward of the view with W or no key, back with S, to a side
-- with A or D
local function strafe(input, state)
	local velocity = state.Velocity
	local speed = math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
	-- under this there is no flight to speak of, and the keys do better
	if speed < 2 then
		return
	end
	local held = input.Move == Vector2.zero and FORWARD or input.Move
	local sin, cos = math.sin(input.LookYaw), math.cos(input.LookYaw)
	-- where the keys point in the world, by the game's ProvenMath.moveVectorToWorld
	local wishX, wishZ = cos * held.X + sin * held.Y, -sin * held.X + cos * held.Y
	local x, z = -velocity.Z / speed, velocity.X / speed
	local toward = x * wishX + z * wishZ
	if math.abs(toward) < 0.02 then
		side = -side
		toward = side
	end
	if toward < 0 then
		x, z = -x, -z
	end
	input.Move = toMove(x, z, input.LookYaw)
	acted.as = os.clock()
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.RespectCanCollide = true
-- the game's hull is 32 units a side
local HULL = Vector3.new(32, 1, 32) * UNIT
-- the game's step height: ground this far under the hull is still walked onto
local STEP = 18 * UNIT

-- whether the last command was an edge jump's, and whether the flight since is one
local leapt, leaping = false, false

-- edge jump: jumps on the last command that has ground under the hull. The ground is looked for with a box as wide as
-- the hull, here and where the command will take it; how far under the state's position the ground is isn't known, so
-- it is measured here first
local function edge(input, state)
	if bit32.band(input.Buttons, JUMP) ~= 0 or bit32.band(state.PreviousButtons, JUMP) ~= 0 then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local flat = Vector3.new(state.Velocity.X, 0, state.Velocity.Z)
	if not map or flat.Magnitude < 1 then
		return
	end
	params.FilterDescendantsInstances = { map }
	local from = state.Position + Vector3.yAxis
	local here = workspace:Blockcast(CFrame.new(from), HULL, Vector3.new(0, -8, 0), params)
	if not here then
		return
	end
	local reach = Vector3.new(0, -(here.Distance + STEP), 0)
	if not workspace:Blockcast(CFrame.new(from + flat * TICK), HULL, reach, params) then
		input.Buttons += JUMP
		leapt = true
		acted.ej = os.clock()
	end
end

-- quick stop: on the ground with no move key down, the move input goes against the way the character is going, at the
-- size that takes off just the speed there is
local function quickStop(input, state)
	local velocity = state.Velocity
	local speed = math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
	-- the game's friction ends what is left under this
	if speed < 0.5 then
		return
	end
	local size = math.min(speed / (ACCELERATE * TICK * state.WeaponMoveSpeed), 1)
	input.Move = toMove(-velocity.X / speed, -velocity.Z / speed, input.LookYaw) * size
	acted.qs = os.clock()
end

-- where the hull was at the last command, and where block bot wants it, which a Heartbeat of the hub's own works out
local position, blockAt = nil, nil
-- starline's figures, in units: a teammate within the first is blocked from the second in front of them
local BLOCK_RANGE, BLOCK_AHEAD = 250 * UNIT, 34 * UNIT

-- block bot: walks to the place in front of the nearest teammate and stays there
local function block(input, state)
	local x, z = blockAt.X - state.Position.X, blockAt.Z - state.Position.Z
	local distance = math.sqrt(x ^ 2 + z ^ 2)
	if distance < 0.2 then
		input.Move = Vector2.zero
	else
		-- slower over the last two studs, so as not to run past
		input.Move = toMove(x / distance, z / distance, input.LookYaw) * math.min(distance / 2, 1)
	end
	acted.bb = os.clock()
end

-- where the flight that is on began and when, or nothing on the ground
local takeoff, takeoffAt

-- what the hub does to a movement command before the game builds and sends it. It runs inside the game's own function
function movement.command(input, state)
	movement.velocity = state.Velocity
	position = state.Position

	-- a ladder is left to the game
	if state.MovementMode ~= "Walking" then
		takeoff, leapt, leaping = nil, false, false
		return
	end

	local now = os.clock()
	if state.OnGround then
		-- a walk off a kerb is no jump
		if takeoff and now - takeoffAt > 0.2 then
			local across = state.Position - takeoff
			movement.landing = {
				speed = math.sqrt(state.Velocity.X ^ 2 + state.Velocity.Z ^ 2),
				length = math.sqrt(across.X ^ 2 + across.Z ^ 2),
				long = leaping and settings.longJump,
			}
		end
		takeoff = nil
	elseif not takeoff then
		takeoff, takeoffAt = state.Position, now
	end

	if settings.nullBinds and keys then
		nullBinds(input, state)
	end
	if blockAt then
		block(input, state)
	end
	if settings.autoStrafe and not state.OnGround then
		strafe(input, state)
	end

	-- a long jump is ducked from the command after its edge jump until it lands
	leaping = not state.OnGround and (leapt or leaping)
	leapt = false
	if leaping and settings.longJump then
		input.Buttons = bit32.bor(input.Buttons, DUCK)
		acted.lj = now
	end
	if settings.bunnyhop then
		hop(input, state)
	end
	if settings.edgeJump and state.OnGround then
		edge(input, state)
	end
	if settings.quickStop and state.OnGround and input.Move == Vector2.zero and bit32.band(input.Buttons, JUMP) == 0 then
		quickStop(input, state)
	end
end

function movement.start()
	hub.cleanup.add(RunService.Heartbeat:Connect(function()
		blockAt = nil
		if not (settings.blockBot and position) then
			return
		end
		local nearest, best
		for _, model in esp.teammates.models() do
			local root = model:FindFirstChild("HumanoidRootPart")
			local distance = root and (root.Position - position).Magnitude
			if distance and distance < (best or BLOCK_RANGE) then
				nearest, best = root, distance
			end
		end
		if nearest then
			local look = nearest.CFrame.LookVector
			blockAt = nearest.Position + Vector3.new(look.X, 0, look.Z).Unit * BLOCK_AHEAD
		end
	end))
end

return movement
