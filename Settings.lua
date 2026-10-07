local addonName, ns = ...

-- The options page, in the game's Options under AddOns. Built the first time it's shown.

local Utils, L, P, S = ns.Utils, ns.L, ns.Profiler, ns.SpikeWatch
local C = Utils.COLORS
local Options = {}
ns.Settings = Options

local format, floor, max, min = string.format, math.floor, math.max, math.min

local PAD = 16
local LABEL_W = 230
local ROW_GAP = 6

local panel, scroll, content, bar, category
local widgets, notes = {}, {}
local cursor = 0

local function DB()
	return ns.db
end

local function Window()
	if ns.Window then
		ns.Window.Refresh()
	end
end

-- --- builders -----------------------------------------------------------------------------------

local function Place(widget, height, indent)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + (indent or 0) * 24, -cursor)
	cursor = cursor + height + ROW_GAP
end

local function Gap(height)
	cursor = cursor + (height or 8)
end

local function Header(text)
	Gap(10)
	local label = Utils.FontString(content, "Normal")
	label:SetText(text)
	Place(label, Utils.FontHeight("Normal"))
	local rule = Utils.Pixel(content, "BORDER", C.line)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	rule:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
	Gap(4)
end

local function Note(text, indent)
	local note = Utils.FontString(content, "Disable")
	note:SetJustifyH("LEFT")
	note:SetWordWrap(true)
	note:SetText(text)
	note.indent = indent or 0
	note:SetWidth(max(200, content:GetWidth() - PAD * 2 - note.indent * 24))
	notes[#notes + 1] = note
	Place(note, note:GetStringHeight(), indent)
	return note
end

-- `options`: indent, requires (a getter that enables the widget), tip.
local function Dimmed(widget, options)
	if options and options.requires then
		local on = options.requires() and true or false
		widget:SetAlpha(on and 1 or 0.4)
		if widget:IsObjectType("Button") then
			widget:EnableMouse(on)
		end
		return on
	end
	return true
end

local function Check(text, getter, setter, options)
	options = options or {}
	local box = Utils.Checkbox(content, text, getter, function(value)
		setter(value)
		Options.Refresh()
	end)
	local refresh = box.Refresh
	function box:Refresh()
		refresh(self)
		Dimmed(self, options)
	end
	if options.tip then
		box:SetScript("OnEnter", function(self)
			Utils.Tooltip(self, "ANCHOR_RIGHT", text, options.tip)
		end)
		box:SetScript("OnLeave", GameTooltip_Hide)
	end
	widgets[#widgets + 1] = box
	Place(box, 20, options.indent)
	return box
end

-- A labelled choice: a button showing the current option, opening a menu of all of them.
-- `choices`: { { value, text }, ... }.
local function Choice(text, choices, getter, setter, options)
	options = options or {}
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(LABEL_W + 200, 24)
	local label = Utils.FontString(row, "HighlightSmall")
	label:SetPoint("LEFT")
	label:SetWidth(LABEL_W - 10)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	local button = Utils.Button(row, "", 170, 22)
	button:SetPoint("LEFT", row, "LEFT", LABEL_W - (options.indent or 0) * 24, 0)
	function row:Refresh()
		local current = getter()
		for _, choice in ipairs(choices) do
			if choice[1] == current then
				button:SetText(choice[2])
			end
		end
		button:FitWidth(170)
		Dimmed(self, options)
		button:EnableMouse(not options.requires or options.requires())
	end
	local function Pick(value)
		setter(value)
		Options.Refresh()
	end
	button:SetScript("OnClick", function(self)
		local opened = Utils.Menu(self, function(root)
			for _, choice in ipairs(choices) do
				root:CreateRadio(choice[2], function()
					return getter() == choice[1]
				end, function()
					Pick(choice[1])
				end)
			end
		end)
		if not opened then
			local current, nextIndex = getter(), 1
			for index, choice in ipairs(choices) do
				if choice[1] == current then
					nextIndex = index % #choices + 1
				end
			end
			Pick(choices[nextIndex][1])
		end
	end)
	if options.tip then
		button:SetScript("OnEnter", function(self)
			Utils.Tooltip(self, "ANCHOR_RIGHT", text, options.tip)
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
	end
	widgets[#widgets + 1] = row
	Place(row, 24, options.indent)
	return row
end

-- A labelled slider from `low` to `high` in steps of `step`; `show(value)` is its text.
local SLIDER_W = 200

local function Slide(text, low, high, step, getter, setter, show, options)
	options = options or {}
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(LABEL_W + SLIDER_W + 80, 24)
	local label = Utils.FontString(row, "HighlightSmall")
	label:SetPoint("LEFT")
	label:SetWidth(LABEL_W - 10)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	local slider = CreateFrame("Slider", nil, row)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(SLIDER_W, 18)
	slider:SetPoint("LEFT", row, "LEFT", LABEL_W - (options.indent or 0) * 24, 0)
	slider:SetMinMaxValues(low, high)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(false)
	local track = Utils.Pixel(slider, "BACKGROUND", C.cell)
	track:SetHeight(4)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
	thumb:SetVertexColor(C.text[1], C.text[2], C.text[3])
	thumb:SetSize(8, 16)
	slider:SetThumbTexture(thumb)
	local value = Utils.FontString(row, "HighlightSmall")
	value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	local quiet = false
	local function Snap(raw)
		return floor((raw - low) / step + 0.5) * step + low
	end
	slider:SetScript("OnValueChanged", function(_, raw)
		local current = Snap(raw)
		value:SetText(show(current))
		if not quiet and math.abs(current - getter()) > step / 2 then
			setter(current)
		end
	end)
	slider:SetScript("OnMouseUp", function()
		Options.Refresh()
	end)
	function row:Refresh()
		quiet = true
		slider:SetValue(getter())
		quiet = false
		value:SetText(show(getter()))
		Dimmed(self, options)
		slider:EnableMouse(not options.requires or options.requires())
	end
	widgets[#widgets + 1] = row
	Place(row, 24, options.indent)
	return row
end

-- For what can't be undone: the first click asks, a second within a few seconds does it.
local function Confirming(button, text, action)
	local armed = 0
	button:SetScript("OnClick", function(self)
		if GetTime() - armed < 4 then
			armed = 0
			self:SetText(text)
			self:FitWidth(110)
			action()
		else
			armed = GetTime()
			self:SetText(L["Click again to confirm"])
			self:FitWidth(110)
			C_Timer.After(4, function()
				if armed > 0 and GetTime() - armed >= 4 then
					armed = 0
					self:SetText(text)
					self:FitWidth(110)
				end
			end)
		end
	end)
end

-- A row of buttons: { text, onClick, confirm = true }.
local function Buttons(specs, options)
	options = options or {}
	local row = CreateFrame("Frame", nil, content)
	row:SetHeight(22)
	row.buttons = {}
	local x = 0
	for _, spec in ipairs(specs) do
		local button = Utils.Button(row, spec[1], 110, 22)
		row.buttons[#row.buttons + 1] = button
		button:FitWidth(110)
		button:SetPoint("LEFT", row, "LEFT", x, 0)
		if spec.confirm then
			Confirming(button, spec[1], spec[2])
		else
			button:SetScript("OnClick", spec[2])
		end
		x = x + button:GetWidth() + 8
	end
	row:SetWidth(max(1, x))
	if options.requires then
		function row:Refresh()
			local on = Dimmed(self, options)
			for _, button in ipairs(self.buttons) do
				button:EnableMouse(on)
			end
		end
		widgets[#widgets + 1] = row
	end
	Place(row, 22, options.indent)
	return row
end

-- --- the page -----------------------------------------------------------------------------------

local function Seconds(values)
	local list = {}
	for _, value in ipairs(values) do
		list[#list + 1] = { value, format(L["%s s"], tostring(value)) }
	end
	return list
end

local function OverlayOn()
	return DB().overlay.enabled
end

local function ApplyOverlay()
	ns.Overlay.Apply()
end

local function BuildContent()
	cursor = PAD

	local title = Utils.FontString(content, "HighlightLarge")
	title:SetText(Utils.TITLE)
	Place(title, Utils.FontHeight("HighlightLarge"))
	Note(L["Finds the addons behind lag and stutter: live CPU per frame, slow frames and who caused them, and memory growth."])

	Header(L["Measuring"])
	Choice(L["Refresh the window every"], Seconds({ 0.5, 1, 2, 5 }), function()
		return DB().refreshRate
	end, function(value)
		DB().refreshRate = value
		Window()
	end)
	Choice(L["Scan memory every"], {
		{ 5, format(L["%s s"], 5) }, { 10, format(L["%s s"], 10) }, { 15, format(L["%s s"], 15) },
		{ 30, format(L["%s s"], 30) }, { 60, format(L["%s s"], 60) }, { 0, L["Only when I ask"] },
	}, function()
		return DB().memoryInterval
	end, function(value)
		DB().memoryInterval = value
		Window()
	end, { tip = L["Memory is scanned only while the window is open, and never in combat. The game pauses for a moment while it counts, longer with many addons, so a slow scan makes the next one wait longer."] })
	Choice(L["A slow frame is one over"], {
		{ 10, "10 ms" }, { 50, "50 ms" }, { 100, "100 ms" }, { 500, "500 ms" },
	}, function()
		return DB().spikeMs
	end, function(value)
		DB().spikeMs = value
		P.SetThreshold(value)
		S.OnThresholdChanged()
		Window()
	end, { tip = L["What counts as a slow frame for the table, the log and the on-screen stats: a frame where addon code ran longer than this. 50 ms is a noticeable hitch; 10 ms catches smaller stutters at high frame rates."] })
	Slide(L["An addon is busy from"], 0.1, 5, 0.1, function()
		return DB().cpuWarn
	end, function(value)
		DB().cpuWarn = value
	end, function(value)
		return format(L["%.1f ms a frame"], value)
	end)
	Slide(L["Memory grows fast from"], 50, 2000, 50, function()
		return DB().growthWarn
	end, function(value)
		DB().growthWarn = value
	end, function(value)
		return Utils.Rate(value)
	end)
	Check(L["Tint numbers over these thresholds"], function()
		return DB().warnColor
	end, function(value)
		DB().warnColor = value
		Window()
	end, { tip = L["The only colour the addon uses: a number over one of your thresholds."] })

	Header(L["Slow frame log"])
	Check(L["Watch for slow frames in the background"], function()
		return DB().spikeWatch
	end, function(value)
		DB().spikeWatch = value
		S.Apply()
		Window()
	end, { tip = L["Logs each slow frame with the addon that caused it, when and where, even with nothing open. It costs one profiler read every two seconds."] })
	Check(L["Skip loading screens"], function()
		return DB().spikeSkipLoading
	end, function(value)
		DB().spikeSkipLoading = value
	end, { indent = 1, requires = function()
		return DB().spikeWatch
	end, tip = L["Addons do their setup during loading screens, so long frames there are expected."] })
	Check(L["Say so in chat when one happens"], function()
		return DB().spikeChat
	end, function(value)
		DB().spikeChat = value
	end, { indent = 1, requires = function()
		return DB().spikeWatch
	end })
	Choice(L["Keep the last"], {
		{ 50, "50" }, { 100, "100" }, { 200, "200" }, { 500, "500" },
	}, function()
		return DB().spikeKeep
	end, function(value)
		DB().spikeKeep = value
		local log = DB().spikeLog
		while #log > value do
			table.remove(log, 1)
		end
	end)
	Buttons({
		{ L["Open the log"], function()
			ns.Window.Show("log")
		end },
		{ L["Clear the log"], function()
			S.Clear()
		end, confirm = true },
	})

	Header(L["Report at login"])
	Choice(L["After logging in or reloading"], {
		{ "off", L["Say nothing"] },
		{ "problems", L["Report only problems"] },
		{ "always", L["Always report"] },
	}, function()
		return DB().loginReport
	end, function(value)
		DB().loginReport = value
	end, { tip = L["A short report in chat about 25 seconds after the loading screen, from steady play: addons whose CPU stayed over your threshold, and those that made slow frames once start-up was over. With \"Report only problems\" it says nothing when all is well."] })

	Header(L["On-screen stats"])
	Check(L["Show live stats on screen"], OverlayOn, function(value)
		DB().overlay.enabled = value
		ApplyOverlay()
	end)
	local needsOverlay = { indent = 1, requires = OverlayOn }
	Buttons({
		{ L["Move"], function()
			ns.Overlay.Move()
		end },
		{ L["Reset position"], function()
			ns.Overlay.ResetPosition()
			ApplyOverlay()
		end },
	}, { indent = 1 })
	Check(L["Locked (clicks go through)"], function()
		return DB().overlay.lock
	end, function(value)
		DB().overlay.lock = value
		ApplyOverlay()
	end, { indent = 1, requires = OverlayOn, tip = L["Unlocked, the stats can be dragged anywhere. Right-click them to lock them again."] })
	Check(L["Dark background"], function()
		return DB().overlay.background
	end, function(value)
		DB().overlay.background = value
		ApplyOverlay()
	end, needsOverlay)
	Choice(L["Layout"], {
		{ "stacked", L["One per line"] }, { "line", L["All on one line"] },
	}, function()
		return DB().overlay.layout
	end, function(value)
		DB().overlay.layout = value
		ApplyOverlay()
	end, needsOverlay)
	Choice(L["Anchor"], ns.Overlay.ANCHORS, function()
		return DB().overlay.point
	end, function(value)
		ns.Overlay.SetAnchor(value)
		ApplyOverlay()
	end, { indent = 1, requires = OverlayOn, tip = L["Where the stats hang from. From a top anchor they grow down, from a bottom one they grow up. Picking one here moves them to that edge of the screen; dragging them sets the anchor from where they're dropped."] })
	Slide(L["Size"], 0.6, 2, 0.05, function()
		return DB().overlay.scale
	end, function(value)
		DB().overlay.scale = value
		ApplyOverlay()
	end, function(value)
		return format("%d%%", floor(value * 100 + 0.5))
	end, needsOverlay)
	Choice(L["Update every"], Seconds({ 0.5, 1, 2 }), function()
		return DB().overlay.rate
	end, function(value)
		DB().overlay.rate = value
		ApplyOverlay()
	end, needsOverlay)
	for _, item in ipairs(ns.Overlay.ITEMS) do
		local key = item.key
		Check(item.label, function()
			return DB().overlay.items[key]
		end, function(value)
			DB().overlay.items[key] = value
			ApplyOverlay()
		end, needsOverlay)
	end

	Header(L["Minimap and data bars"])
	Check(L["Show the minimap button"], function()
		return DB().minimap.show
	end, function(value)
		DB().minimap.show = value
		ns.Popup.Apply()
	end)
	Check(L["Lock its position"], function()
		return DB().minimap.lock
	end, function(value)
		DB().minimap.lock = value
	end, { indent = 1, requires = function()
		return DB().minimap.show
	end })
	Check(L["List in the addon compartment"], function()
		return DB().compartment
	end, function(value)
		DB().compartment = value
		ns.Popup.ApplyCompartment()
	end, { tip = L["Blizzard's addon menu by the minimap."] })
	Check(L["Feed data bars (LibDataBroker)"], function()
		return DB().broker
	end, function(value)
		DB().broker = value
		ns.Popup.ApplyBroker()
	end, { tip = L["Frame rate and addon CPU for data bar addons such as ElvUI, Titan Panel or ChocolateBar, when one of them has loaded LibDataBroker. Turning it off stops the updates; the bar drops it at the next reload."] })
	Buttons({ { L["Reset button position"], function()
		ns.Popup.ResetPosition()
	end } })

	Header(L["Window"])
	Slide(L["Text size"], -3, 5, 1, function()
		return DB().fontSize
	end, function(value)
		DB().fontSize = value
		Utils.ApplyFontSize()
		Window()
	end, function(value)
		return value > 0 and "+" .. value or tostring(value)
	end)
	Buttons({ { L["Reset size and position"], function()
		ns.Window.ResetGeometry()
	end } })

	Header(L["Tools"])
	Buttons({
		{ L["Open the window"], function()
			ns.Window.Show("addons")
		end },
		{ L["Report in chat"], function()
			ns.Report()
		end },
		{ L["Scan memory now"], function()
			if not ns.Memory.Scan() then
				Utils.Print(L["Memory can't be scanned in combat."])
			end
		end },
		{ L["This addon's cost"], function()
			ns.PrintPerformance()
		end },
	})
	Check(L["Debug mode: print errors the addon catches"], function()
		return DB().debug
	end, function(value)
		DB().debug = value
	end)
	Buttons({ { L["Reset all settings"], function()
		ns.ResetSettings()
	end, confirm = true } })
	Note(L["Resetting keeps the slow frame log."])

	Header(L["About"])
	Note(format(L["Version %s by %s."], Utils.Metadata(addonName, "Version") or "?", Utils.Metadata(addonName, "Author") or "powercover"))
	Note(L["/lad opens the window. /lad help lists every command."])
	Note(L["CPU figures come from the game's own addon profiler, the same numbers the AddOns list shows. It measures only addon code, never Blizzard's own interface, and starts over on every reload."])

	content:SetHeight(cursor + PAD)
end

-- --- scrolling, sizing, opening -----------------------------------------------------------------

local function UpdateScroll()
	local range = max(0, content:GetHeight() - scroll:GetHeight())
	bar:SetMinMaxValues(0, range)
	bar:SetShown(range > 0)
	if bar:GetValue() > range then
		bar:SetValue(range)
	end
end

local function Fit()
	local width = panel:GetWidth() - 14
	content:SetWidth(max(300, width))
	for _, note in ipairs(notes) do
		note:SetWidth(max(200, width - PAD * 2 - note.indent * 24))
	end
	UpdateScroll()
end

local function Build()
	panel = CreateFrame("Frame", "LaggyAddonDetectorSettings", UIParent)
	panel:Hide()
	scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -14, 4)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, 100)
	scroll:SetScrollChild(content)

	bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetPoint("TOPRIGHT", -4, -4)
	bar:SetPoint("BOTTOMRIGHT", -4, 4)
	bar:SetWidth(6)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	local track = Utils.Pixel(bar, "BACKGROUND", C.cell)
	track:SetAllPoints()
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
	thumb:SetVertexColor(C.line[1], C.line[2], C.line[3])
	thumb:SetSize(6, 40)
	bar:SetThumbTexture(thumb)
	bar:SetScript("OnValueChanged", function(_, value)
		scroll:SetVerticalScroll(value)
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		local low, high = bar:GetMinMaxValues()
		bar:SetValue(max(low, min(high, bar:GetValue() - delta * 40)))
	end)

	panel:SetScript("OnShow", function(self)
		if not self.built then
			self.built = true
			content:SetWidth(max(300, self:GetWidth() - 14))
			BuildContent()
		end
		Fit()
		Options.Refresh()
	end)
	panel:SetScript("OnSizeChanged", function(self)
		if self.built then
			Fit()
		end
	end)
	return panel
end

function Options.Register()
	if category or not (Settings and type(Settings.RegisterCanvasLayoutCategory) == "function") then
		return
	end
	category = Settings.RegisterCanvasLayoutCategory(Build(), Utils.TITLE)
	Settings.RegisterAddOnCategory(category)
end

function Options.Refresh()
	for _, widget in ipairs(widgets) do
		if widget.Refresh then
			widget:Refresh()
		end
	end
end

function Options.Open()
	Options.Register()
	if not category then
		return
	end
	if SettingsPanel and SettingsPanel:IsShown() and panel and panel:IsVisible() then
		HideUIPanel(SettingsPanel)
		return
	end
	Settings.OpenToCategory(category:GetID())
end
