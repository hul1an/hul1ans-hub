local hub = ...

local RunService = cloneref(game:GetService("RunService"))

local markers = { groups = {} }
local texts = {}

-- instances() returns what to mark at its pivot, text(instance, distance) the label
function markers.add(color, instances, text)
	local group = {
		enabled = false,
		color = color,
		maxDistance = 500,
		instances = instances,
		text = text,
	}
	table.insert(markers.groups, group)
	return group
end

local function render()
	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local seen = {}

	for _, group in markers.groups do
		if group.enabled then
			for _, instance in group.instances() do
				seen[instance] = true
				local position = instance:GetPivot().Position
				local distance = (position - origin).Magnitude
				local screen = camera:WorldToViewportPoint(position)
				local visible = screen.Z > 0 and distance <= group.maxDistance

				local object = texts[instance]
				if visible and not object then
					object = Drawing.new("Text")
					object.Size = 13
					object.Center = true
					object.Outline = true
					texts[instance] = object
				end
				if object then
					object.Visible = visible
					if visible then
						object.Color = group.color
						object.Text = group.text(instance, distance)
						object.Position = Vector2.new(screen.X, screen.Y)
					end
				end
			end
		end
	end

	-- instances that are gone or whose group was switched off
	for instance, object in texts do
		if not seen[instance] then
			object:Remove()
			texts[instance] = nil
		end
	end
end

function markers.start()
	hub.cleanup.add(function()
		for _, object in texts do
			object:Remove()
		end
		table.clear(texts)
	end)
	hub.cleanup.add(RunService.RenderStepped:Connect(render))
end

return markers
