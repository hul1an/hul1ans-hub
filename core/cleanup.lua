local items = {}
local cleanup = {}

function cleanup.add(item)
	table.insert(items, item)
	return item
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
