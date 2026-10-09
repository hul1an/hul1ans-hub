local hub = ...

local window = hub.bracket.createWindow("BloxStrike")

hub.require("universal.lua")(window)

window:CreateTab("Misc"):CreateSection("Hub"):CreateButton("Eject", hub.unload)
