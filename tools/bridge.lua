local HttpService = cloneref(game:GetService("HttpService"))

local FOLDER = "claude-bridge"
local REQUEST = FOLDER .. "/request.json"
local RESPONSE = FOLDER .. "/response.txt"
local SESSION = FOLDER .. "/session"
-- a listing stops here so one request can't write a file too big to read
local MAX_LINES = 1000
-- seconds between looks for a request
local POLL = 0.25

-- a path is a list from game down: a child's name, or its index in GetChildren when the name isn't unique
local function resolve(path)
	local instance = game
	for _, segment in path do
		local child
		if type(segment) == "number" then
			child = instance:GetChildren()[segment]
		else
			child = instance:FindFirstChild(segment)
		end
		assert(child, tostring(segment) .. " not found in " .. instance:GetFullName())
		instance = child
	end
	return instance
end

local function pathOf(instance)
	local path = {}
	while instance ~= game do
		local parent = instance.Parent
		if parent:FindFirstChild(instance.Name) == instance then
			table.insert(path, 1, instance.Name)
		else
			table.insert(path, 1, table.find(parent:GetChildren(), instance))
		end
		instance = parent
	end
	return HttpService:JSONEncode(path)
end

local function show(value)
	local kind = typeof(value)
	if kind == "Instance" then
		return value:GetFullName() .. " (" .. value.ClassName .. ")"
	elseif kind == "string" then
		-- getproperties includes binary blobs
		if not utf8.len(value) then
			return "binary, " .. #value .. " bytes"
		elseif #value > 200 then
			return '"' .. value:sub(1, 200) .. '"... (' .. #value .. " bytes)"
		end
		return '"' .. value .. '"'
	end
	return tostring(value) .. " (" .. kind .. ")"
end

local function section(lines, title, values)
	local names = {}
	for name in values do
		table.insert(names, name)
	end
	table.sort(names)
	table.insert(lines, title .. ":")
	for _, name in names do
		table.insert(lines, "\t" .. name .. " = " .. show(values[name]))
	end
end

local function list(lines, instance, depth, indent)
	local children = instance:GetChildren()
	local count = {}
	for _, child in children do
		count[child.Name] = (count[child.Name] or 0) + 1
	end
	for index, child in children do
		if #lines >= MAX_LINES then
			return
		end
		local name = child.Name
		if count[name] > 1 then
			name = "#" .. index .. " " .. name
		end
		table.insert(lines, indent .. name .. "  " .. child.ClassName .. "  " .. #child:GetChildren())
		if depth > 1 then
			list(lines, child, depth - 1, indent .. "\t")
		end
	end
end

local function join(lines)
	if #lines >= MAX_LINES then
		table.insert(lines, "stopped at " .. MAX_LINES .. " lines")
	end
	return table.concat(lines, "\n")
end

local ops = {}

function ops.ping()
	return "GameId " .. game.GameId .. ", PlaceId " .. game.PlaceId
end

-- each line is name, class, child count
function ops.children(request)
	local lines = {}
	list(lines, resolve(request.path), request.depth or 1, "")
	return join(lines)
end

function ops.inspect(request)
	local instance = resolve(request.path)
	local lines = { instance:GetFullName(), "Class: " .. instance.ClassName }
	section(lines, "Properties", getproperties(instance))
	section(lines, "Attributes", instance:GetAttributes())
	table.insert(lines, "Tags: " .. table.concat(instance:GetTags(), ", "))
	return table.concat(lines, "\n")
end

-- descendants whose name contains request.name and that are a request.class, either may be left out;
-- request.show names a property to print beside each
function ops.find(request)
	local lines = {}
	local name = request.name and request.name:lower()
	for _, instance in resolve(request.path):GetDescendants() do
		if #lines >= MAX_LINES then
			break
		end
		if
			(not name or instance.Name:lower():find(name, 1, true))
			and (not request.class or instance:IsA(request.class))
		then
			local line = pathOf(instance) .. "  " .. instance.ClassName
			if request.show then
				line ..= "  " .. show(instance[request.show])
			end
			table.insert(lines, line)
		end
	end
	return join(lines)
end

-- what is added under a path over request.seconds (only a request.class, if given): when, class, name, a Sound's
-- id, and where it or its parent is.
-- with request.near (a path) and request.nearName, also the nearest part of that name under it and how far
function ops.watch(request)
	local lines = {}
	local started = os.clock()
	local near = request.near and resolve(request.near)
	local connection = resolve(request.path).DescendantAdded:Connect(function(instance)
		if #lines >= MAX_LINES or request.class and not instance:IsA(request.class) then
			return
		end
		local line = string.format("%.2f  %s  %s", os.clock() - started, instance.ClassName, instance.Name)
		if instance:IsA("Sound") then
			line ..= "  " .. instance.SoundId
		end
		local part = instance:IsA("BasePart") and instance or instance.Parent
		if part and part:IsA("BasePart") then
			line ..= "  at " .. tostring(part.Position)
			if near then
				local nearest, best
				for _, other in near:GetDescendants() do
					if other.Name == request.nearName and other:IsA("BasePart") then
						local distance = (other.Position - part.Position).Magnitude
						if not best or distance < best then
							nearest, best = other, distance
						end
					end
				end
				if nearest then
					line ..= string.format("  nearest %s %.1f", nearest.Parent.Name, best)
				end
			end
		end
		table.insert(lines, line)
	end)
	task.wait(request.seconds or 5)
	connection:Disconnect()
	return join(lines)
end

function ops.decompile(request)
	return decompile(resolve(request.path))
end

if not isfolder(FOLDER) then
	makefolder(FOLDER)
end
-- running the bridge again takes the session over, which ends the older loop
local session = HttpService:GenerateGUID(false)
writefile(SESSION, session)
print("[bridge] listening")

while isfile(SESSION) and readfile(SESSION) == session do
	if isfile(REQUEST) then
		local ok, result = pcall(function()
			local request = HttpService:JSONDecode(readfile(REQUEST))
			return ops[request.op](request)
		end)
		writefile(RESPONSE, ok and result or "error: " .. tostring(result))
		-- the request going away is what tells the sender the response is complete
		delfile(REQUEST)
	end
	task.wait(POLL)
end
print("[bridge] stopped")
