local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))

-- seconds in the air before a landing counts as a jump for the graph's events
local MIN_AIR = 0.15

local movement = {
	settings = {
		bunnyhop = false,
	},
	-- the velocity of the user's root, for the velocity graph
	velocity = Vector3.zero,
	-- the last time in the air that ended: how fast along the ground it ended and how far it went, both in studs. A new
	-- table each time
	landing = nil,
}
local settings = movement.settings

-- where and when the time in the air began, and the speed along the ground last seen in it
local flight

local function step()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then
		movement.velocity, flight = Vector3.zero, nil
		return
	end

	local velocity = root.AssemblyLinearVelocity
	movement.velocity = velocity
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded then
		if flight and os.clock() - flight.at > MIN_AIR then
			local far = root.Position - flight.from
			movement.landing = { speed = flight.speed, length = Vector3.new(far.X, 0, far.Z).Magnitude }
		end
		flight = nil
	else
		flight = flight or { at = os.clock(), from = root.Position }
		flight.speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end

	-- starline's auto jump: the jump is pressed again on the first frame back on the ground while the key is held
	if settings.bunnyhop and grounded and UserInputService:IsKeyDown(Enum.KeyCode.Space) and not UserInputService:GetFocusedTextBox() then
		humanoid.Jump = true
	end
end

function movement.start()
	hub.cleanup.add(RunService.Heartbeat:Connect(step))
end

return movement
