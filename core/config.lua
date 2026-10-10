local HttpService = cloneref(game:GetService("HttpService"))

local FOLDER = "hul1ans-hub"

local config = {}

function config.load(name)
	local path = FOLDER .. "/" .. name .. ".json"
	if isfile(path) then
		return HttpService:JSONDecode(readfile(path))
	end
	return nil
end

function config.save(name, data)
	if not isfolder(FOLDER) then
		makefolder(FOLDER)
	end
	writefile(FOLDER .. "/" .. name .. ".json", HttpService:JSONEncode(data))
end

-- the saved names that start with prefix, with it taken off
function config.list(prefix)
	local names = {}
	if isfolder(FOLDER) then
		for _, path in listfiles(FOLDER) do
			-- executors differ on whether listfiles gives / or \
			local name = path:match("([^/\\]+)%.json$")
			if name and name:sub(1, #prefix) == prefix then
				table.insert(names, name:sub(#prefix + 1))
			end
		end
	end
	table.sort(names)
	return names
end

function config.delete(name)
	delfile(FOLDER .. "/" .. name .. ".json")
end

return config
