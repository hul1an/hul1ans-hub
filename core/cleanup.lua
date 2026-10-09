local items = {}
local cleanup = {}

function cleanup.add(item)
	table.insert(items, item)
	return item
end

-- wraps a service so connections made through it are undone by run()
function cleanup.track(service)
	return setmetatable({}, {
		__index = function(_, key)
			local value = service[key]
			if typeof(value) == "RBXScriptSignal" then
				return {
					Connect = function(_, callback)
						return cleanup.add(value:Connect(callback))
					end,
				}
			elseif type(value) == "function" then
				return function(_, ...)
					return value(service, ...)
				end
			end
			return value
		end,
	})
end

function cleanup.run()
	for index = #items, 1, -1 do
		local item = items[index]
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			item:Destroy()
		elseif kind == "function" then
			item()
		elseif kind == "thread" then
			task.cancel(item)
		end
	end
	table.clear(items)
end

return cleanup
