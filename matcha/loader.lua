local REPO = "hul1an/hul1ans-hub"
local HttpService = game:GetService("HttpService")

-- a raw branch URL is cached for 5 minutes, a raw commit URL is always current
local ok, commit = pcall(function()
	return HttpService:JSONDecode(httpget("https://api.github.com/repos/" .. REPO .. "/commits/main")).sha
end)
if not (ok and commit) then
	warn("[hub] commit lookup failed, using main (files may be up to 5 minutes old)")
end
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. (ok and commit or "main") .. "/matcha/"

local previous = _G.Hub
if previous then
	previous.unload()
end

local hub = {}
local modules = {}

-- httpget answers a failed request with an empty body, not a status code
function hub.fetch(url)
	local body = httpget(url)
	assert(body ~= "", url .. " returned nothing")
	return body
end

function hub.read(path)
	return hub.fetch(BASE_URL .. path)
end

-- Matcha's loadstring drops the chunk's return and setfenv can't change a chunk's environment, so each module is
-- wrapped in a vararg function that the chunk leaves in a global, taken out again at once
function hub.load(path)
	loadstring("_G.HubModule = (function(...)\n" .. hub.read(path) .. "\nend)", "=" .. path)()
	local module = _G.HubModule
	_G.HubModule = nil
	return assert(module, path .. " did not compile")(hub)
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
	_G.Hub = nil
end

hub.ui = hub.require("core/ui.lua")
_G.Hub = hub

local registry = hub.require("games/registry.lua")
local gamePath = registry[game.GameId]
if not gamePath then
	warn("[hub] no script for this game (GameId " .. game.GameId .. "), using the universal one")
	gamePath = "games/universal/main.lua"
end

local ok, err = pcall(hub.load, gamePath)
if not ok then
	warn("[hub] " .. gamePath .. " failed: " .. tostring(err))
	hub.ui.notify(gamePath .. " failed: " .. tostring(err), "error")
end
