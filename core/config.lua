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

return config
