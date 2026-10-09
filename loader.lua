local BASE_URL = "https://raw.githubusercontent.com/hul1an/hul1ans-hub/main/"

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

function hub.load(path)
	return assert(loadstring(hub.fetch(BASE_URL .. path .. "?t=" .. os.time()), "=" .. path))(hub)
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
hub.bracket = hub.require("core/bracket.lua")
getgenv().Hub = hub

local registry = hub.require("games/registry.lua")
local gamePath = registry[game.GameId]
if not gamePath then
	warn("[hub] unsupported game " .. game.GameId)
	return
end

local ok, err = pcall(hub.load, gamePath)
if not ok then
	warn("[hub] " .. gamePath .. " failed: " .. tostring(err))
end
