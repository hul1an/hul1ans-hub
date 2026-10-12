local hub = ...

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local SoundService = cloneref(game:GetService("SoundService"))
local Debris = cloneref(game:GetService("Debris"))

-- the hitsound's choices: sounds of the game's own, by their folders under ReplicatedStorage.Sounds
local SOUNDS = {
	bell = { "Bullet", "Bell1" },
	headshot = { "Bullet", "Headshot" },
	ping = { "Other", "Ping" },
	click = { "Interface", "UI Click" },
	success = { "Interface", "Notification Success" },
}

local misc = {
	settings = {
		hitsound = false,
		hitsoundName = "bell",
		hitsoundVolume = 100,
		radar = false,
		killfeed = false,
		pistol = false,
		output = { "console", "screen" },
		bombCode = false,
		bombText = "",
	},
	sounds = { "bell", "headshot", "ping", "click", "success" },
}
local settings = misc.settings

-- set by main.lua: the gun that is out, as the game's weapon object
misc.weapon = function()
	return nil
end

local warned = {}

-- one notice a missing thing, however often it is looked for
local function missing(path, feature)
	if not warned[path] then
		warned[path] = true
		warn("[hub] " .. path .. " not found: " .. feature .. " unavailable")
		hub.ui.notify(path .. " not found, no " .. feature, "error")
	end
end

-- for a shot of the user's that hurt an enemy
function misc.hit()
	if not settings.hitsound then
		return
	end
	local place = SOUNDS[settings.hitsoundName]
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	local folder = sounds and sounds:FindFirstChild(place[1])
	local sound = folder and folder:FindFirstChild(place[2])
	sound = sound and sound:FindFirstChildWhichIsA("Sound")
	if not sound then
		missing("ReplicatedStorage.Sounds." .. place[1] .. "." .. place[2], "hitsound")
		return
	end
	local copy = sound:Clone()
	copy.Volume = settings.hitsoundVolume / 100
	copy.Parent = SoundService
	copy:Play()
	Debris:AddItem(copy, 5)
end

-- the game's radar class and its chat screen, both only reachable through the garbage collector
local radar, chat
for _, object in getgc(true) do
	if type(object) == "table" then
		if type(rawget(object, "UpdatePlayerIcons")) == "function" and type(rawget(object, "CreatePlayerIcon")) == "function" then
			radar = object
		elseif type(rawget(object, "ProcessSystemMessage")) == "function" and type(rawget(object, "ProcessChatData")) == "function" then
			chat = object
		end
	end
end

-- a log line goes to whichever of the three are chosen: the game's chat as one of its system messages, the console,
-- where Potassium's read_console gets at it, and the menu's own lines on screen
function misc.log(text)
	if table.find(settings.output, "chat") then
		if chat then
			task.spawn(chat.ProcessSystemMessage, text)
		else
			missing("the game's chat screen (ProcessSystemMessage)", "logs in chat")
		end
	end
	if table.find(settings.output, "console") then
		print("[hub] " .. text)
	end
	if table.find(settings.output, "screen") then
		hub.ui.log(text)
	end
end

-- engine radar: the game only draws an enemy on the radar while a teammate has a line to them, and keeps what it
-- found for each in a cache it reads first. While this is the cache's metatable every enemy reads as seen
local SEEN = {
	__index = function()
		return { Visible = true, UpdatedAt = math.huge }
	end,
}

-- the caches it is on, to take it off again; the game makes a new radar every spawn
local revealed = setmetatable({}, { __mode = "k" })

local function reveal(self)
	local cache = rawget(self, "EnemyVisibilityCache")
	if settings.radar then
		if getmetatable(cache) ~= SEEN then
			-- an answer the game has kept is read before the metatable is asked
			table.clear(cache)
			setmetatable(cache, SEEN)
			revealed[cache] = true
		end
	elseif getmetatable(cache) == SEEN then
		setmetatable(cache, nil)
	end
end

-- the kill feed rows the hub has put in place of the game's, which fade and go after 5 s
local kept = {}

local function clearKept()
	for copy in kept do
		copy:Destroy()
	end
	table.clear(kept)
end

-- preserve killfeed: the game outlines a row in red when the user is in it. One that isn't the user's death is swapped
-- for a copy the game doesn't know of, which stays until the round is over
local function preserve(row)
	if not settings.killfeed or kept[row] then
		return
	end
	local stroke = row:FindFirstChildWhichIsA("UIStroke")
	local contents = row:FindFirstChild("Contents")
	local victim = contents and contents:FindFirstChild("Enemy")
	local weapon = contents and contents:FindFirstChild("Weapon")
	-- a row with no weapon on it is a deathmatch streak's
	if not (stroke and victim and weapon and weapon.Visible) or stroke.Color ~= Color3.new(1, 0, 0) then
		return
	end
	local player = Players.LocalPlayer
	if victim.Text == player.DisplayName or victim.Text == player.Name then
		return
	end
	local copy = row:Clone()
	kept[copy] = true
	copy.Parent = row.Parent
	row.Visible = false
end

-- what the hub last wrote on the bomb's screen
local shown

-- custom bomb code: the bomb in the user's hands shows its code on a label, a character a key. Whatever the game
-- writes there is written again with as many characters of the user's text
local function retype()
	local model = workspace.CurrentCamera:FindFirstChild("C4")
	if not model then
		return
	end
	local label = model:FindFirstChild("TextLabel", true)
	if not label then
		missing("TextLabel in the C4 viewmodel", "custom bomb code")
		return
	end
	local text = label.Text
	if text ~= shown then
		local typed = #(text:gsub("%*", ""))
		shown = settings.bombText:sub(1, typed) .. string.rep("*", #text - typed)
		label.Text = shown
	end
end

function misc.start()
	if radar then
		local radarWarned = false
		local original
		original = hookfunction(radar.UpdatePlayerIcons, function(self, ...)
			-- an error here would otherwise stop the game's radar
			local ok, err = pcall(reveal, self)
			if not ok and not radarWarned then
				radarWarned = true
				warn("[hub] radar hook failed: " .. tostring(err))
			end
			return original(self, ...)
		end)
		hub.cleanup.add(function()
			hookfunction(radar.UpdatePlayerIcons, original)
			for cache in revealed do
				setmetatable(cache, nil)
			end
		end)
	else
		missing("the game's radar class (UpdatePlayerIcons)", "engine radar")
	end

	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local main = gui and gui:FindFirstChild("MainGui")
	local feed = main and main:FindFirstChild("KillFeed", true)
	if feed then
		hub.cleanup.add(feed.ChildAdded:Connect(preserve))
		hub.cleanup.add(workspace:GetAttributeChangedSignal("CurrentRound"):Connect(clearKept))
		hub.cleanup.add(clearKept)
	else
		missing("PlayerGui.MainGui.Gameplay.Middle.KillFeed", "preserve killfeed")
	end

	hub.cleanup.add(RunService.Heartbeat:Connect(function()
		if settings.bombCode then
			retype()
		end

		-- automatic pistol: the game's fire key shoots a pistol once a press, so while it is held the hub shoots again
		-- as soon as the gun can
		local weapon = settings.pistol and misc.weapon()
		if weapon and weapon.IsFireHeld == true and not weapon.IsShooting and not weapon.IsReloading then
			local properties = weapon.Properties
			if properties.Type == "Pistol"
				and not properties.Automatic
				and properties.ShootingOptions ~= "Revolver"
				and weapon.AlternativeShootingOption ~= "Burst"
				and weapon.Rounds > 0 then
				-- a thread of its own, so that no hub function is under the game's on the stack
				task.spawn(weapon.shoot, weapon)
			end
		end
	end))
end

return misc
