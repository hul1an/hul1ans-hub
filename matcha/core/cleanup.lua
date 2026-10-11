local items = {}
local cleanup = {}

function cleanup.add(item)
	table.insert(items, item)
	return item
end

-- connections go in as themselves, everything else as a function that undoes it
function cleanup.run()
	for index = #items, 1, -1 do
		local item = items[index]
		if typeof(item) == "function" then
			item()
		else
			item:Disconnect()
		end
	end
	table.clear(items)
end

return cleanup
