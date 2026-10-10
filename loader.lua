local REPO = "hul1an/hul1ans-hub"
local HttpService = cloneref(game:GetService("HttpService"))

-- a raw branch URL is cached for 5 minutes, a raw commit URL is always current
local ok, commit = pcall(function()
	local response = request({ Url = "https://api.github.com/repos/" .. REPO .. "/commits/main", Method = "GET" })
	return HttpService:JSONDecode(response.Body).sha
end)
if not (ok and commit) then
	warn("[hub] commit lookup failed, using main (files may be up to 5 minutes old)")
end
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. (ok and commit or "main") .. "/"

local previous = getgenv().Hub
if previous then
	previous.unload()
end

local hub = {}
local modules = {}

function hub.fetch(url)
	local response = request({ Url = url, Method = "GET" })
	assert(response.StatusCode == 200, url .. " returned " .. response.StatusCode)
	return response.Body
end

function hub.read(path)
	return hub.fetch(BASE_URL .. path)
end

function hub.load(path)
	return assert(loadstring(hub.read(path), "=" .. path))(hub)
end

function hub.require(path)
	if modules[path] == nil then
		modules[path] = hub.load(path)
	end
	return modules[path]
end

hub.cleanup = hub.require("core/cleanup.lua")

function hub.unload()
	hub.cleanup.run()
	getgenv().Hub = nil
end

hub.ui = hub.require("core/ui.lua")
getgenv().Hub = hub

local registry = hub.require("games/registry.lua")
local gamePath = registry[game.GameId]
if not gamePath then
	local window = hub.ui.createWindow("Universal")
	hub.require("universal.lua")(window)
	window:CreateTab("Misc", "settings"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
	return
end

local ok, err = pcall(hub.load, gamePath)
if not ok then
	warn("[hub] " .. gamePath .. " failed: " .. tostring(err))
	hub.ui.notify(gamePath .. " failed: " .. tostring(err), "error")
end
