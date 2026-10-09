local hub = ...

local Players = cloneref(game:GetService("Players"))

local esp = hub.require("core/esp.lua")
local aim = hub.require("core/aim.lua")
aim.settings.TeamCheck = true

-- the game moves players it has culled out of workspace.Characters and leaves their last position on them,
-- so only characters still in that folder are real; it has no Humanoids or Roblox teams, only attributes
local players = esp.sources[1]
local warned = false

players.models = function(skipTeammates)
	local characters = {}
	local folder = workspace:FindFirstChild("Characters")
	if not folder then
		if not warned then
			warned = true
			warn("[hub] workspace.Characters not found")
		end
		return characters
	end

	local team = skipTeammates and Players.LocalPlayer:GetAttribute("Team")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if player ~= Players.LocalPlayer
			and character
			and character.Parent == folder
			and not character:GetAttribute("Dead")
			and not (team and player:GetAttribute("Team") == team) then
			table.insert(characters, character)
		end
	end
	return characters
end

players.health = function(character)
	return character:GetAttribute("Health"), character:GetAttribute("MaxHealth")
end

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

-- temporary: everything is written as text so the file shows how the game stores characters and sides
local function names(instance)
	local list = {}
	for _, child in instance:GetChildren() do
		table.insert(list, child.Name .. " (" .. child.ClassName .. ")")
	end
	return list
end

local function attributes(instance)
	local list = {}
	for key, value in instance:GetAttributes() do
		list[key] = tostring(value)
	end
	return list
end

local function dump()
	local camera = workspace.CurrentCamera
	local data = {
		localPlayer = Players.LocalPlayer.Name,
		workspace = names(workspace),
		teams = names(cloneref(game:GetService("Teams"))),
		camera = names(camera),
		players = {},
		humanoids = {},
	}

	for _, player in Players:GetPlayers() do
		local entry = {
			name = player.Name,
			team = tostring(player.Team),
			teamColor = tostring(player.TeamColor),
			neutral = tostring(player.Neutral),
			attributes = attributes(player),
			children = names(player),
		}
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local cframe, size = character:GetBoundingBox()
			entry.character = {
				path = character:GetFullName(),
				attributes = attributes(character),
				children = names(character),
				health = humanoid and tostring(humanoid.Health) .. " / " .. tostring(humanoid.MaxHealth),
				root = root and tostring(root.Position),
				boxCentre = tostring(cframe.Position),
				boxSize = tostring(size),
				distance = root and tostring(math.floor((camera.CFrame.Position - root.Position).Magnitude)),
				inFront = root and tostring(camera:WorldToViewportPoint(root.Position).Z > 0),
			}
		end
		table.insert(data.players, entry)
	end

	-- every humanoid in the world, to spot bodies that are not a player's Character
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Humanoid") and descendant.Parent then
			local owner = Players:GetPlayerFromCharacter(descendant.Parent)
			table.insert(data.humanoids, {
				path = descendant.Parent:GetFullName(),
				player = owner and owner.Name or "none",
				health = tostring(descendant.Health) .. " / " .. tostring(descendant.MaxHealth),
				attributes = attributes(descendant.Parent),
			})
		end
	end

	hub.require("core/config.lua").save("bloxstrike_dump", data)
	print("[hub] wrote hul1ans-hub/bloxstrike_dump.json")
end

local misc = window:CreateTab("Misc")
misc:CreateSection("Debug"):CreateButton("Dump players to file", dump)
misc:CreateSection("Hub"):CreateButton("Eject", hub.unload)
