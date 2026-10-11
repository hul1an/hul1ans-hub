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

-- httpget answers a failed request with the error page's body, not a status code, and a body like
-- "404: Not Found" would otherwise surface as a parse error one loadstring later
function hub.fetch(url)
	local body = httpget(url)
	assert(body ~= "" and not body:find("^%d%d%d: "), url .. " returned nothing usable")
	return body
end

function hub.read(path)
	return hub.fetch(BASE_URL .. path)
end

-- Matcha's loadstring drops the chunk's return and its setfenv refuses a loadstring'd function,
-- so the module is wrapped in a call that runs it with hub and leaves the module in a named global
function hub.load(path)
	local key = "__hub_" .. path:gsub("%W", "_")
	local chunk = loadstring(key .. " = (function(...)\n" .. hub.read(path) .. "\nend)(...)", "=" .. path)
	chunk(hub)
	local env = getfenv(chunk)
	local loaded = env[key]
	env[key] = nil
	return assert(loaded, path .. " did not compile")
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
