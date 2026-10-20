local hub = ...

local cleanup = hub.require("core/cleanup.lua")

local BRAND = "bloxline"

local ui = {}

-- ids are the window / tab / section / control path, plus the option for one of several
local function key(...)
	return table.concat({ ... }, "/")
end

-- one control's Matcha calls. The defaults re-passed every frame are the stored values,
-- so what the callback wrote last is what the next frame shows
local function emit(control, sec)
	local kind = control.kind
	if kind == "toggle" then
		sec:Toggle(control.key, control.name, control.value, function(value)
			control.value = value
			control.callback(value)
		end)
		if control.keybind then
			sec:Keybind(control.key .. "/bind", control.keybind.key, control.keybind.mode)
		end
		if control.swatch then
			local swatch = control.swatch
			sec:ColorPicker(control.key .. "/color", swatch.color.R, swatch.color.G, swatch.color.B, swatch.alpha, function(color, alpha)
				swatch.color, swatch.alpha = color, alpha
				swatch.callback(color, alpha)
			end)
		end
	elseif kind == "slider" then
		local callback = function(value)
			control.value = value
			control.callback(value)
		end
		-- a format function is for the bloxline menu; Matcha only takes a pattern
		local format = type(control.format) == "string" and control.format
		if control.precise or format then
			sec:SliderFloat(control.key, control.name, control.min, control.max, control.value, format or "%.0f", callback)
		else
			sec:SliderInt(control.key, control.name, control.min, control.max, control.value, callback)
		end
	elseif kind == "dropdown" then
		-- the player list's options follow who is in the game
		if control.refresh then
			control.refresh()
		end
		local index = table.find(control.options, control.value)
		sec:Combo(control.key, control.name, control.options, index and index - 1 or 0, function(_, option)
			control.value = option
			control.callback(option)
		end)
	elseif kind == "multi" then
		-- Matcha has no multi select: one toggle per option
		for _, option in control.options do
			sec:Toggle(control.key .. "/" .. option, option, table.find(control.values, option) ~= nil, function(on)
				local at = table.find(control.values, option)
				if on and not at then
					table.insert(control.values, option)
				elseif not on and at then
					table.remove(control.values, at)
				end
				control.callback(control.values)
			end)
		end
	elseif kind == "colorpicker" then
		-- Matcha puts a picker on the row of the toggle before it, which every layout here has
		sec:ColorPicker(control.key, control.color.R, control.color.G, control.color.B, 1, function(color)
			control.color = color
			control.callback(color)
		end)
	elseif kind == "textbox" then
		sec:InputText(control.key, control.name, control.value, function(text)
			control.value = text
			control.callback(text)
		end)
	elseif kind == "button" then
		sec:Button(control.name, control.callback)
	elseif kind == "label" then
		sec:Text(control.text)
	elseif kind == "group" then
		-- no foldable groups: the group's toggle, then its controls with the group name on them
		emit(control.header, sec)
		for _, child in control.controls do
			emit(child, sec)
		end
	end
end

-- what a toggle's creator gives back: a key, a swatch on its row, and a way to set it
local function toggleHandle(control)
	return {
		-- "NONE" or a KeyCode name; Matcha takes an unbound 0, a virtual-key code or an Enum. The mode is hold or toggle
		CreateKeybind = function(_, bind, mode)
			control.keybind = { key = bind == "NONE" and 0 or Enum.KeyCode[bind], mode = mode == "hold" and "hold" or "toggle" }
		end,
		-- the callback gets the colour and its opacity, as in the bloxline menu. Matcha puts one picker on a row and
		-- none on a row with a key
		CreateColorpicker = function(_, callback, alpha)
			local swatch = { callback = callback, color = Color3.new(1, 1, 1), alpha = 1 }
			control.swatch = swatch
			return {
				UpdateColor = function(_, color, opacity)
					swatch.color, swatch.alpha = color, opacity or 1
				end,
			}
		end,
		Set = function(_, to)
			control.value = to
			UI.SetValue(control.key, to)
		end,
	}
end

-- the Create methods of a section or group, recording controls for the per frame render
local function builders(list, keyFor, prefix)
	local handle = {}

	local function name(label)
		return prefix and prefix .. " " .. label or label
	end

	function handle:CreateToggle(label, value, callback)
		local control = { kind = "toggle", key = keyFor(label), name = name(label), value = value, callback = callback }
		table.insert(list, control)
		return toggleHandle(control)
	end

	function handle:CreateSlider(label, min, max, value, precise, callback, format)
		local control = { kind = "slider", key = keyFor(label), name = name(label), min = min, max = max, value = value, precise = precise, callback = callback, format = format }
		table.insert(list, control)
		return {
			Set = function(_, to)
				control.value = to
				UI.SetValue(control.key, to)
			end,
		}
	end

	function handle:CreateDropdown(label, options, callback, value)
		local control = { kind = "dropdown", key = keyFor(label), name = name(label), options = options, callback = callback, value = value or options[1] }
		table.insert(list, control)
		return {
			AddOption = function(_, option)
				table.insert(control.options, option)
			end,
			-- a function run each frame before the dropdown is drawn
			OnRefresh = function(_, refresh)
				control.refresh = refresh
			end,
			ClearOptions = function()
				table.clear(control.options)
			end,
		}
	end

	function handle:CreateMultiDropdown(label, options, callback, values)
		table.insert(list, { kind = "multi", key = keyFor(label), name = name(label), options = options, callback = callback, values = values or {} })
		return {}
	end

	function handle:CreateColorpicker(label, callback)
		local control = { kind = "colorpicker", key = keyFor(label), name = name(label), callback = callback, color = Color3.new(1, 1, 1) }
		table.insert(list, control)
		return {
			UpdateColor = function(_, color)
				control.color = color
			end,
		}
	end

	function handle:CreateTextBox(label, placeholder, numbersOnly, callback)
		-- Matcha has no placeholder or numbers-only text box
		table.insert(list, { kind = "textbox", key = keyFor(label), name = name(label), value = "", callback = callback })
		return {}
	end

	function handle:CreateButton(label, callback)
		table.insert(list, { kind = "button", name = name(label), callback = callback })
		return {}
	end

	function handle:CreateLabel(text)
		table.insert(list, { kind = "label", text = text })
	end

	function handle:CreateGroup(label, value, callback)
		local header = { kind = "toggle", key = keyFor(label), name = label, value = value, callback = callback }
		local group = { kind = "group", header = header, controls = {} }
		table.insert(list, group)
		local inner = builders(group.controls, function(child)
			return keyFor(label .. "/" .. child)
		end, label)
		-- the group's toggle, which a key or a swatch goes on
		inner.header = toggleHandle(header)
		return inner
	end

	return handle
end

function ui.createWindow(title)
	local window = {}

	function window:CreateTab(tabName, icon)
		-- the icon is a bloxline sheet name; Matcha draws its own
		local tab = { sections = {} }

		function tab:CreateSection(sectionName, side)
			local section = { name = sectionName, side = side == "RightSide" and "Right" or "Left", controls = {} }
			table.insert(tab.sections, section)
			return builders(section.controls, function(controlName)
				return key(title, tabName, sectionName, controlName)
			end)
		end

		-- Matcha has no sub-tabs: a sub-tab's sections go in the tab with its name in front of theirs
		function tab:CreateSubTab(subName)
			local sub = {}

			function sub:CreateSection(sectionName, side)
				return tab:CreateSection(subName .. " " .. sectionName, side)
			end

			-- starline's player list as a dropdown of everyone over a card of rows about the one picked. groups() gives
			-- the groups, each a name and its players; chosen(player, group) is called when one is picked, and for the
			-- first of the list when the one picked has left
			function sub:CreatePlayerList(groups, chosen)
				local picker = sub:CreateSection("list", "LeftSide")
				local card = sub:CreateSection("player", "RightSide")
				-- the players by the text the dropdown shows them as, and the one picked
				local shown, current, pending = {}, nil, nil
				local dropdown
				dropdown = picker:CreateDropdown("player", {}, function(text)
					current = text
					pending = shown[text]
				end)
				dropdown:OnRefresh(function()
					dropdown:ClearOptions()
					table.clear(shown)
					local first
					for _, group in groups() do
						for _, player in group.players do
							local text = player.name .. (player.you and " (you)" or "")
							shown[text] = { player = player, group = group.name }
							dropdown:AddOption(text)
							first = first or text
						end
					end
					if not shown[current] then
						current = first
						pending = first and shown[first]
					end
				end)
				-- called from a frame callback of its own: the rows set widgets, which the tab's callback shouldn't
				cleanup.add(game:GetService("RunService").RenderStepped:Connect(function()
					if pending then
						local entry = pending
						pending = nil
						chosen(entry.player, entry.group)
					end
				end))
				return card
			end

			return sub
		end

		cleanup.add(function()
			UI.RemoveTab(tabName)
		end)
		UI.AddTab(tabName, function(matchaTab)
			for _, section in tab.sections do
				local sec = matchaTab:Section(section.name, section.side)
				for _, control in section.controls do
					emit(control, sec)
				end
			end
		end)
		return tab
	end

	return window
end

function ui.notify(text, kind)
	-- Matcha has one toast style, so the kind is dropped
	notify(text, BRAND, 5)
end

-- Matcha doesn't say whether its menu is open, so nothing can hold off for it
function ui.visible()
	return false
end

return ui
