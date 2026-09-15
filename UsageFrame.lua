local addonName, ns = ...

local NUM_ROWS = 16
local ROW_HEIGHT = 22
local FRAME_WIDTH = 760
local FRAME_HEIGHT = 530

local COLUMNS = {
	{ key = "name", label = "Addon", width = 250, align = "LEFT" },
	{ key = "cpu", label = "CPU", width = 110, align = "RIGHT" },
	{ key = "peak", label = "Peak", width = 90, align = "RIGHT" },
	{ key = "memory", label = "Memory", width = 110, align = "RIGHT" },
	{ key = "resources", label = "Load", width = 100, align = "LEFT" },
}

local function CellText(row, key)
	if key == "name" then
		return ns.ColoredName(row.title, row.severity)
	elseif key == "cpu" then
		return ns.FormatCPU(row.cpuRecent)
	elseif key == "peak" then
		if not ns.HasProfiler() or row.peak <= 0 then
			return "—"
		end
		return ns.FormatCPU(row.peak)
	elseif key == "memory" then
		return ns.FormatMemory(row.memory)
	end
	return ns.ColoredName(ns.LoadLabel(row.severity), row.severity)
end

local function HeaderLabel(column)
	local db = ns.db
	if not db or db.sortKey ~= column.key then
		return column.label
	end
	return column.label .. (db.sortAsc and " ^" or " v")
end

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
	row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	if index % 2 == 0 then
		row.bg:SetColorTexture(1, 1, 1, 0.035)
	else
		row.bg:SetColorTexture(0, 0, 0, 0.12)
	end

	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.10)

	row.cells = {}
	local x = 8
	for i, column in ipairs(COLUMNS) do
		local font = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		font:SetWidth(column.width - 8)
		font:SetWordWrap(false)
		font:SetJustifyH(column.align)
		if column.align == "LEFT" then
			font:SetPoint("LEFT", row, "LEFT", x, 0)
		else
			font:SetPoint("RIGHT", row, "LEFT", x + column.width - 8, 0)
		end
		row.cells[column.key] = font
		x = x + column.width
	end

	row:SetScript("OnEnter", function(self)
		if not self.data then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(ns.ColoredName(self.data.title, self.data.severity), 1, 1, 1)
		GameTooltip:AddDoubleLine("Folder", self.data.name, 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Recent CPU", ns.FormatCPU(self.data.cpuRecent), 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Session CPU", ns.FormatCPU(self.data.cpuSession), 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Peak CPU", ns.FormatCPU(self.data.peak), 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Memory", ns.FormatMemory(self.data.memory), 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Load", ns.LoadLabel(self.data.severity), 0.7, 0.7, 0.7, ns.SeverityColor(self.data.severity))
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return row
end

local function RefreshRows(frame)
	local offset = frame.offset or 0
	local rows = ns.rows or {}
	for i = 1, NUM_ROWS do
		local data = rows[offset + i]
		local row = frame.rows[i]
		if data then
			row.data = data
			for _, column in ipairs(COLUMNS) do
				row.cells[column.key]:SetText(CellText(data, column.key))
			end
			row:Show()
		else
			row.data = nil
			row:Hide()
		end
	end

	local maxOffset = math.max(0, #rows - NUM_ROWS)
	frame.slider:SetMinMaxValues(0, maxOffset)
	if offset > maxOffset then
		frame.offset = maxOffset
		frame.slider:SetValue(maxOffset)
	end
	frame.slider:SetShown(maxOffset > 0)

	local red, yellow, green = ns.Counts()
	frame.status:SetText(string.format(
		"|cffff3333%d heavy|r   |cffffd133%d moderate|r   |cff4ce65a%d light|r   |cffaaaaaa%d loaded addons|r",
		red, yellow, green, #rows
	))

	if ns.HasProfiler() then
		frame.hint:SetText("CPU updates while this window is open. Memory refreshes slowly so the detector does not hitch you.")
	else
		frame.hint:SetText("Memory refreshes slowly while this window is open. Enable scriptProfile and reload for CPU timings on this client.")
	end

	for _, header in ipairs(frame.headers) do
		header.label:SetText(HeaderLabel(header.column))
		if ns.db and ns.db.sortKey == header.column.key then
			header.label:SetTextColor(1, 0.82, 0)
		else
			header.label:SetTextColor(1, 1, 1)
		end
	end
end

function ns.RefreshFrame()
	if ns.frame and ns.frame:IsShown() then
		RefreshRows(ns.frame)
	end
end

local function SetSort(key)
	ns.EnsureDB()
	if ns.db.sortKey == key then
		ns.db.sortAsc = not ns.db.sortAsc
	else
		ns.db.sortKey = key
		ns.db.sortAsc = (key == "name")
	end
	ns.Sort()
	ns.RefreshFrame()
end

local function CreateUsageFrame()
	local frame = CreateFrame("Frame", "LaggyAddonDetectorFrame", UIParent, "BackdropTemplate")
	frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.08, 0.96)
	frame:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)
	frame:Hide()
	tinsert(UISpecialFrames, frame:GetName())

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Laggy Addon Detector")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local report = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	report:SetSize(110, 22)
	report:SetPoint("TOPLEFT", 14, -14)
	report:SetText("Chat report")
	report:SetScript("OnClick", function()
		ns.Collect({ memory = true })
		ns.PrintSummary("from the table")
	end)

	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
	subtitle:SetText("Live CPU and memory usage for every loaded addon")
	frame.subtitle = subtitle

	local headerBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	headerBar:SetPoint("TOPLEFT", 16, -52)
	headerBar:SetPoint("TOPRIGHT", -36, -52)
	headerBar:SetHeight(24)
	headerBar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	headerBar:SetBackdropColor(0.12, 0.12, 0.16, 0.9)

	frame.headers = {}
	local headerX = 8
	for _, column in ipairs(COLUMNS) do
		local header = CreateFrame("Button", nil, headerBar)
		header:SetSize(column.width, 24)
		header:SetPoint("LEFT", headerBar, "LEFT", headerX, 0)
		header.column = column
		header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header.label:SetAllPoints()
		header.label:SetJustifyH(column.align)
		header.label:SetText(column.label)
		header:SetScript("OnClick", function()
			SetSort(column.key)
		end)
		header:SetScript("OnEnter", function(self)
			self.label:SetTextColor(1, 0.82, 0)
		end)
		header:SetScript("OnLeave", function(self)
			if ns.db and ns.db.sortKey == column.key then
				self.label:SetTextColor(1, 0.82, 0)
			else
				self.label:SetTextColor(1, 1, 1)
			end
		end)
		frame.headers[#frame.headers + 1] = header
		headerX = headerX + column.width
	end

	local list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2)
	list:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, -2)
	list:SetHeight(NUM_ROWS * ROW_HEIGHT)

	local listBg = list:CreateTexture(nil, "BACKGROUND")
	listBg:SetAllPoints()
	listBg:SetColorTexture(0, 0, 0, 0.25)

	frame.rows = {}
	for i = 1, NUM_ROWS do
		frame.rows[i] = CreateRow(list, i)
	end
	frame.offset = 0

	local slider = CreateFrame("Slider", "LaggyAddonDetectorScrollBar", frame, "UIPanelScrollBarTemplate")
	slider:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, -16)
	slider:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 4, 16)
	slider:SetMinMaxValues(0, 0)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	slider.scrollStep = 1
	slider:SetScript("OnValueChanged", function(_, value)
		frame.offset = math.floor(value + 0.5)
		RefreshRows(frame)
	end)
	frame.slider = slider

	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		local minV, maxV = slider:GetMinMaxValues()
		local value = math.min(maxV, math.max(minV, (frame.offset or 0) - delta))
		slider:SetValue(value)
	end)

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	status:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -14)
	frame.status = status

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -8)
	hint:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
	hint:SetJustifyH("LEFT")
	frame.hint = hint

	local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
	legend:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
	legend:SetJustifyH("LEFT")
	legend:SetText("|cffff3333Red = heavy|r   |cffffd133Yellow = average|r   |cff4ce65aGreen = lightweight|r")

	frame:SetScript("OnShow", function()
		ns.Collect({ memory = true })
		RefreshRows(frame)
		PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 852)
	end)

	ns.RegisterListener(function()
		ns.RefreshFrame()
	end)

	return frame
end

function ns.ToggleFrame()
	if not ns.frame then
		ns.frame = CreateUsageFrame()
	end
	if ns.frame:IsShown() then
		ns.frame:Hide()
	else
		ns.frame:Show()
	end
end
