local hub = ...

local RunService = cloneref(game:GetService("RunService"))

-- seconds between distance checks of what the last scan found
local UPDATE = 0.25

local markers = { groups = {} }
local active = {}
local elapsed = UPDATE

-- instances() returns what to mark at its pivot, label(instance) a heading and the text under it, or nil to skip
function markers.add(color, instances, label)
	local group = {
		enabled = false,
		color = color,
		maxDistance = 500,
		-- seconds between scans; instances() and label() only run then
		interval = 1,
		entries = {},
		instances = instances,
		label = label,
	}
	table.insert(markers.groups, group)
	return group
end

local function scan(group)
	local entries = {}
	for _, instance in group.instances() do
		if instance:IsA("PVInstance") then
			local heading, body = group.label(instance)
			if heading then
				table.insert(entries, {
					instance = instance,
					position = instance:GetPivot().Position,
					heading = heading,
					body = body,
				})
			end
		end
	end
	return entries
end

local function update(origin)
	local now = os.clock()
	local seen = {}

	for _, group in markers.groups do
		if not group.enabled then
			-- forgotten so that switching it back on scans straight away
			if group.scanned then
				group.entries = {}
				group.scanned = nil
			end
		else
			if not group.scanned or now - group.scanned >= group.interval then
				group.scanned = now
				group.entries = scan(group)
			end
			for _, entry in group.entries do
				local distance = (entry.position - origin).Magnitude
				if distance <= group.maxDistance and entry.instance.Parent then
					seen[entry.instance] = true
					local marker = active[entry.instance]
					if not marker then
						marker = { object = Drawing.new("Text") }
						marker.object.Size = 13
						marker.object.Center = true
						marker.object.Outline = true
						active[entry.instance] = marker
					end
					marker.position = entry.position
					marker.object.Color = group.color
					marker.object.Text = entry.heading .. " [" .. math.floor(distance) .. "]" .. entry.body
				end
			end
		end
	end

	-- instances that are gone, out of range or whose group was switched off
	for instance, marker in active do
		if not seen[instance] then
			marker.object:Remove()
			active[instance] = nil
		end
	end
end

local function render(delta)
	local camera = workspace.CurrentCamera
	elapsed += delta
	if elapsed >= UPDATE then
		elapsed = 0
		update(camera.CFrame.Position)
	end

	for _, marker in active do
		local screen = camera:WorldToViewportPoint(marker.position)
		marker.object.Visible = screen.Z > 0
		marker.object.Position = Vector2.new(screen.X, screen.Y)
	end
end

function markers.start()
	hub.cleanup.add(function()
		for _, marker in active do
			marker.object:Remove()
		end
		table.clear(active)
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return markers
