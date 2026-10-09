local hub = ...

local aim = hub.require("core/aim.lua")
aim.settings.TeamCheck = true

local window = hub.bracket.createWindow("BloxStrike")
local tabs = hub.require("universal.lua")(window)

local silent = { enabled = false }

-- rewrites a finished bullet raycast so its last hit is the aim assist's target
local function redirect(result, target)
	local hits = rawget(result, "Hits")
	if type(hits) ~= "table" then
		return
	end

	local last
	for index, hit in hits do
		if type(hit) == "table" and (not last or index > last) then
			last = index
		end
	end
	if not last then
		return
	end

	local position = target.Position
	local final = hits[last]
	final.Instance = target
	final.Position = position
	if final.Exit ~= nil then
		final.Exit = false
	end

	local origin = rawget(result, "Origin") or workspace.CurrentCamera.CFrame.Position
	if typeof(origin) ~= "Vector3" then
		return
	end
	local delta = position - origin
	local length = delta.Magnitude
	if length < 0.001 then
		return
	end
	result.Distance = length
	result.Direction = delta.Unit

	-- earlier hits that lie past the target are pulled back in front of it
	for index, hit in hits do
		if index ~= last and type(hit) == "table" and typeof(hit.Position) == "Vector3" then
			if (hit.Position - origin):Dot(delta.Unit) > length then
				hit.Position = origin + delta.Unit * (length * 0.5)
			end
		end
	end
end

local unloaded = false
hub.cleanup.add(function()
	unloaded = true
end)

-- the game's bullet class is only reachable through the garbage collector, and may not exist until a gun is out
task.spawn(function()
	local bullets
	for _ = 1, 45 do
		if unloaded then
			return
		end
		for _, object in getgc(true) do
			if type(object) == "table"
				and type(rawget(object, "_performRaycast")) == "function"
				and rawget(object, "getTrueSpread") ~= nil then
				bullets = object
				break
			end
		end
		if bullets then
			break
		end
		task.wait(0.5)
	end
	if not bullets then
		warn("[hub] BloxStrike bullet class (_performRaycast) not found, silent aim unavailable")
		return
	end

	local warned = false
	local original
	original = hookfunction(bullets._performRaycast, function(...)
		local returns = table.pack(original(...))
		local result = returns[1]
		local target = aim.target
		if silent.enabled and target and target.Parent and type(result) == "table" then
			-- an error here would otherwise break the game's own shooting
			local ok, err = pcall(redirect, result, target)
			if not ok and not warned then
				warned = true
				warn("[hub] silent aim failed: " .. tostring(err))
			end
		end
		return table.unpack(returns, 1, returns.n)
	end)

	hub.cleanup.add(function()
		hookfunction(bullets._performRaycast, original)
	end)
end)

local section = tabs.combat:CreateSection("Silent Aim", "RightSide")
section:CreateToggle("Enabled", silent.enabled, function(value)
	silent.enabled = value
end)
section:CreateLabel("Uses the aim assist target")

window:CreateTab("Misc"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
