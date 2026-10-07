local addonName, ns = ...

-- The main window: a summary of the whole UI's cost, the addon table with a detail pane for the
-- selected addon, and the slow frame log. Rows are a fixed pool re-pointed as the list scrolls, and a
-- cell's text is set only when the number it shows has changed.

local Utils, L, P, M, S = ns.Utils, ns.L, ns.Profiler, ns.Memory, ns.SpikeWatch
local C = Utils.COLORS
local W = {}
ns.Window = W

local floor, max, min, format = math.floor, math.max, math.min, string.format
local wipe = table.wipe

local PAD = 10
local TITLE_H, TOOLBAR_H, FOOTER_H = 34, 30, 22
local NAME_MIN = 150
local SCROLL_W = 6
local LOG_TIME_W, LOG_FRAME_W, LOG_STATE_W = 92, 96, 132

local ui = {}
local state = { tab = "addons", offset = 0, logOffset = 0, search = "", selected = nil }
local rows, logRows = {}, {}
local layout = { rowH = 20, visible = 0, logVisible = 0 }

local function DB()
	return ns.db
end

local function Paint(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

-- --- columns ------------------------------------------------------------------------------------

local function MsKey(value)
	return floor(value * 100 + 0.5)
end

local function Tiny(value)
	return value < 0.005
end

local function MsColumn(key, label, width, tip, warn)
	return {
		key = key, field = key, label = label, width = width, tip = tip,
		Key = function(e)
			return MsKey(e[key])
		end,
		Text = function(e)
			return Utils.Ms(e[key])
		end,
		Warn = warn,
		Dim = function(e)
			return Tiny(e[key])
		end,
	}
end

local COLUMNS = {
	{
		key = "name", label = L["Addon"], align = "LEFT",
		tip = L["Hover a row for details, click it for the full breakdown, Shift-click to put it in chat."],
		Key = function(e)
			return e.title
		end,
		Text = function(e)
			return e.title
		end,
	},
	MsColumn("now", L["Now"], 70, L["CPU time a frame, averaged over the last 60 frames."], function(e)
		return e.now >= DB().cpuWarn
	end),
	{
		key = "share", label = L["Share"], width = 84, bar = true,
		tip = L["Share of frame time, worked out the way the game's AddOns list does: this addon's time against the game's time with this addon as the only one running."],
		Key = function(e)
			return floor(P.Share(e) * 10 + 0.5)
		end,
		Text = function(e)
			return Utils.Percent(P.Share(e))
		end,
		Dim = function(e)
			return P.Share(e) < 0.05
		end,
	},
	MsColumn("avg", L["Average"], 72, L["CPU time a frame, averaged since the last reload."]),
	MsColumn("boss", L["Boss fights"], 82, L["CPU time a frame, averaged over boss encounters since the last reload."]),
	MsColumn("last", L["Last frame"], 78, L["CPU time in the most recent frame."]),
	MsColumn("peak", L["Peak"], 68, L["The longest single frame since the last reload. Loading screens count, so start-up work shows here."]),
	{
		key = "slow", width = 66,
		Key = function(e)
			return e.slow
		end,
		Text = function(e)
			return tostring(e.slow)
		end,
		Warn = function(e)
			return e.slow > 0
		end,
		Dim = function(e)
			return e.slow <= 0
		end,
	},
	{
		key = "memory", label = L["Memory"], width = 78,
		tip = L["Memory the addon holds, from the last memory scan. Size alone doesn't cause lag."],
		Key = function(e)
			return e.memoryAt and floor(e.memory / 10) or -1
		end,
		Text = function(e)
			return e.memoryAt and Utils.Memory(e.memory) or "-"
		end,
		Dim = function(e)
			return not e.memoryAt
		end,
	},
	{
		key = "growth", label = L["Growth"], width = 86,
		tip = L["How fast the addon's memory grew between the last two memory scans (an interval where the garbage collector ran is skipped). Fast growth makes the collector run more often, and that can stutter."],
		Key = function(e)
			return e.growthKnown and floor(e.growth + 0.5) or -1
		end,
		Text = function(e)
			return e.growthKnown and Utils.Rate(e.growth) or "-"
		end,
		Warn = function(e)
			return e.growthKnown and e.growth >= DB().growthWarn
		end,
		Dim = function(e)
			return not e.growthKnown or e.growth < 0.5
		end,
	},
}
local COLUMN_BY_KEY = {}
for index, column in ipairs(COLUMNS) do
	column.index = index
	COLUMN_BY_KEY[column.key] = column
end

local function SlowLabel()
	return format(">%d ms", P.spikeMs)
end

local function SlowTip()
	return format(L["Frames this addon alone took longer than %d ms, %s. Change the threshold in the settings."], P.spikeMs, P.PeriodText())
end

local function ColumnLabel(column)
	if column.key == "slow" then
		return SlowLabel()
	end
	return column.label
end

local function ColumnShown(column)
	return column.key == "name" or DB().columns[column.key] == true
end

-- The fields a tick reads: the sort column's for every addon, the shown columns' for rows on screen.
local sortFields, rowFields = {}, {}

local function RebuildFields()
	wipe(sortFields)
	wipe(rowFields)
	local key = DB().sortKey
	if P.FIELD_METRIC[key] and key ~= "now" then
		sortFields[1] = key
	end
	for _, column in ipairs(COLUMNS) do
		local field = column.field
		if field and field ~= "now" and field ~= key and ColumnShown(column) then
			rowFields[#rowFields + 1] = field
		end
	end
end

-- --- small pieces -------------------------------------------------------------------------------

local function Tone(fontString, tone)
	if fontString.tone == tone then
		return
	end
	fontString.tone = tone
	if tone == 2 then
		Paint(fontString, C.warn)
	elseif tone == 1 then
		Paint(fontString, C.faint)
	else
		Paint(fontString, C.text)
	end
end

local function SetCell(cell, key, text)
	if cell.k ~= key then
		cell.k = key
		cell:SetText(text)
	end
end

-- A chevron of two rotated lines, pointing down (descending) or up.
local function Chevron(parent)
	local chevron = CreateFrame("Frame", nil, parent)
	chevron:SetSize(8, 5)
	chevron.left = Utils.Pixel(chevron, "ARTWORK", C.text)
	chevron.right = Utils.Pixel(chevron, "ARTWORK", C.text)
	for _, line in ipairs({ chevron.left, chevron.right }) do
		line:SetSize(5, 1.2)
	end
	function chevron:Point(down)
		self.left:ClearAllPoints()
		self.right:ClearAllPoints()
		self.left:SetPoint("CENTER", self, "CENTER", -1.6, 0)
		self.right:SetPoint("CENTER", self, "CENTER", 1.6, 0)
		self.left:SetRotation(math.rad(down and -40 or 40))
		self.right:SetRotation(math.rad(down and 40 or -40))
	end
	chevron:Point(true)
	return chevron
end

-- A flat scroll bar: a track and a thumb that can be dragged. `onScroll(offset)`.
local function ScrollBar(parent, onScroll)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetWidth(SCROLL_W)
	local track = Utils.Pixel(bar, "BACKGROUND", C.cell)
	track:SetAllPoints()
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(SCROLL_W)
	thumb.fill = Utils.Pixel(thumb, "ARTWORK", C.line)
	thumb.fill:SetAllPoints()
	thumb:SetScript("OnEnter", function(self)
		self.fill:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 1)
	end)
	thumb:SetScript("OnLeave", function(self)
		self.fill:SetVertexColor(C.line[1], C.line[2], C.line[3], 1)
	end)
	bar.total, bar.visible, bar.offset = 0, 0, 0
	function bar:Set(total, visible, offset)
		self.total, self.visible, self.offset = total, visible, offset
		local range = total - visible
		if range <= 0 then
			self:Hide()
			return
		end
		self:Show()
		local height = self.height or self:GetHeight()
		local thumbH = max(18, height * visible / total)
		thumb:SetHeight(thumbH)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", self, "TOP", 0, -(height - thumbH) * offset / range)
	end
	thumb:SetScript("OnMouseDown", function()
		local _, cursorY = GetCursorPosition()
		local scale = bar:GetEffectiveScale()
		local startY, startOffset = cursorY / scale, bar.offset
		thumb:SetScript("OnUpdate", function()
			local _, y = GetCursorPosition()
			local range = bar.total - bar.visible
			local travel = (bar.height or bar:GetHeight()) - thumb:GetHeight()
			if range > 0 and travel > 0 then
				onScroll(floor(startOffset + (startY - y / scale) / travel * range + 0.5))
			end
		end)
	end)
	thumb:SetScript("OnMouseUp", function()
		thumb:SetScript("OnUpdate", nil)
	end)
	thumb:SetScript("OnHide", function()
		thumb:SetScript("OnUpdate", nil)
	end)
	return bar
end

-- --- addon rows ---------------------------------------------------------------------------------

local function EntrySummary(e)
	return format(L["%s: %s a frame now, %s on average, peak %s, %d frames over %d ms %s, memory %s"],
		e.title, Utils.Ms(e.now), Utils.Ms(e.avg), Utils.Ms(e.peak), e.slow, P.spikeMs, P.PeriodText(),
		e.memoryAt and Utils.Memory(e.memory) or L["not scanned"])
end
W.EntrySummary = EntrySummary

local function EnableState(entry)
	local get = C_AddOns and C_AddOns.GetAddOnEnableState
	return Utils.Call(get, entry.name, UnitName("player"))
end

local function DisabledForNextReload(entry)
	return EnableState(entry) == 0
end

StaticPopupDialogs.LAGGYADDONDETECTOR_RELOAD = {
	text = L["%s changes after the interface reloads. Reload now?"],
	button1 = L["Reload"],
	button2 = L["Later"],
	OnAccept = function()
		ReloadUI()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Disables (or enables again) an addon for this character, from the next reload on.
function W.ToggleEnabled(entry)
	local character = UnitName("player")
	if DisabledForNextReload(entry) then
		Utils.Call(C_AddOns.EnableAddOn, entry.name, character)
	else
		Utils.Call(C_AddOns.DisableAddOn, entry.name, character)
	end
	StaticPopup_Show("LAGGYADDONDETECTOR_RELOAD", entry.title)
	W.Refresh()
end

local function ShowRowTooltip(row)
	local e = row.entry
	if not e then
		return
	end
	P.Fill(e, P.ALL_FIELDS)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(e.title, C.heading[1], C.heading[2], C.heading[3])
	local meta = {}
	if e.version then
		meta[#meta + 1] = format(L["version %s"], e.version)
	end
	if e.author then
		meta[#meta + 1] = format(L["by %s"], e.author)
	end
	if e.name ~= e.title then
		meta[#meta + 1] = format(L["folder %s"], e.name)
	end
	if e.lod then
		meta[#meta + 1] = L["load on demand"]
	end
	if #meta > 0 then
		GameTooltip:AddLine(table.concat(meta, " · "), C.dim[1], C.dim[2], C.dim[3], true)
	end
	if e.notes and e.notes ~= "" then
		GameTooltip:AddLine(e.notes, C.dim[1], C.dim[2], C.dim[3], true)
	end
	GameTooltip:AddLine(" ")
	local function Pair(label, value)
		GameTooltip:AddDoubleLine(label, value, C.dim[1], C.dim[2], C.dim[3], 1, 1, 1)
	end
	Pair(L["CPU now"], Utils.Ms(e.now) .. "  (" .. Utils.Percent(P.Share(e)) .. ")")
	Pair(L["Average since reload"], Utils.Ms(e.avg))
	Pair(L["Average in boss fights"], Utils.Ms(e.boss))
	Pair(L["Peak frame"], Utils.Ms(e.peak))
	Pair(format(L["Frames over %d ms, %s"], P.spikeMs, P.PeriodText()), tostring(e.slow))
	Pair(L["Memory"], e.memoryAt and Utils.Memory(e.memory) or L["not scanned"])
	Pair(L["Growth"], e.growthKnown and Utils.Rate(e.growth) or L["after two scans"])
	if DisabledForNextReload(e) then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Disabled from the next reload."], C.warn[1], C.warn[2], C.warn[3])
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Click: details · Shift-click: put in chat · Right-click: more"], C.faint[1], C.faint[2], C.faint[3], true)
	GameTooltip:Show()
end

local function OpenRowMenu(row)
	local e = row.entry
	if not e then
		return
	end
	Utils.Menu(row, function(root)
		root:CreateTitle(e.title)
		root:CreateButton(state.selected == e and L["Hide details"] or L["Show details"], function()
			W.Select(state.selected ~= e and e or nil)
		end)
		root:CreateButton(L["Put in chat"], function()
			Utils.InsertInChat(EntrySummary(e))
		end)
		root:CreateButton(DisabledForNextReload(e) and L["Enable again after reload"] or L["Disable after reload"], function()
			W.ToggleEnabled(e)
		end)
	end)
end

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.stripe = Utils.Pixel(row, "BACKGROUND", C.stripe)
	row.stripe:SetAllPoints()
	row.selected = Utils.Pixel(row, "BORDER", C.select)
	row.selected:SetAllPoints()
	row.selected:Hide()
	local hover = Utils.Pixel(row, "HIGHLIGHT", C.hover)
	hover:SetAllPoints()
	row.bar = Utils.Pixel(row, "ARTWORK", C.bar)
	row.bar:SetHeight(2)
	row.cells = {}
	for index, column in ipairs(COLUMNS) do
		local cell = Utils.FontString(row, "HighlightSmall")
		cell:SetJustifyH(column.align or "RIGHT")
		row.cells[index] = cell
	end
	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self, button)
		if not self.entry then
			return
		end
		if button == "RightButton" then
			OpenRowMenu(self)
		elseif IsShiftKeyDown() then
			Utils.InsertInChat(EntrySummary(self.entry))
		else
			W.Select(state.selected ~= self.entry and self.entry or nil)
		end
	end)
	return row
end

local function PlaceRowCells(row)
	for index, column in ipairs(COLUMNS) do
		local cell = row.cells[index]
		if column.shown then
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", row, "LEFT", column.x + 4, 0)
			cell:SetWidth(column.w - 8)
			cell:Show()
			cell.k = nil
		else
			cell:Hide()
		end
	end
	local share = COLUMN_BY_KEY.share
	row.bar:SetShown(share.shown)
	if share.shown then
		row.bar:ClearAllPoints()
		row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", share.x + 4, 3)
	end
end

local function PaintRow(row, e)
	if row.entry ~= e then
		row.entry = e
		for _, cell in ipairs(row.cells) do
			cell.k = nil
		end
	end
	row.selected:SetShown(e == state.selected)
	local warnOn = DB().warnColor
	for index, column in ipairs(COLUMNS) do
		if column.shown then
			local cell = row.cells[index]
			SetCell(cell, column.Key(e), column.Text(e))
			local tone = 0
			if warnOn and column.Warn and column.Warn(e) then
				tone = 2
			elseif column.Dim and column.Dim(e) then
				tone = 1
			end
			Tone(cell, tone)
		end
	end
	local share = COLUMN_BY_KEY.share
	if share.shown then
		local width = (share.w - 8) * min(1, P.Share(e) / 100)
		row.bar:SetWidth(max(1, width))
		row.bar:SetShown(width >= 1)
	end
end

-- --- the addon list -----------------------------------------------------------------------------

local function ScrollTo(offset)
	local maxOffset = max(0, #P.view - layout.visible)
	state.offset = max(0, min(maxOffset, offset or 0))
	W.PaintRows()
end

function W.PaintRows()
	if not ui.frame then
		return
	end
	local view = P.view
	local total = #view
	local maxOffset = max(0, total - layout.visible)
	if state.offset > maxOffset then
		state.offset = maxOffset
	end
	for i = 1, layout.visible do
		local row = rows[i]
		local e = view[state.offset + i]
		if e then
			if #rowFields > 0 then
				P.Fill(e, rowFields)
			end
			PaintRow(row, e)
			row:Show()
		else
			row.entry = nil
			row:Hide()
		end
	end
	for i = layout.visible + 1, #rows do
		rows[i].entry = nil
		rows[i]:Hide()
	end
	ui.scroll:Set(total, layout.visible, state.offset)
	if total == 0 then
		ui.empty:SetText(DB().onlyProblems and L["Nothing over your thresholds. Untick \"Only problems\" to see every addon."] or L["No addon matches the search."])
		ui.empty:Show()
	else
		ui.empty:Hide()
	end
end

local function PaintHeader()
	local key, ascending = DB().sortKey, DB().sortAsc
	for _, column in ipairs(COLUMNS) do
		local header = column.header
		header:SetShown(column.shown)
		if column.shown then
			header.label:SetText(ColumnLabel(column))
			local sorted = column.key == key
			Paint(header.label, sorted and C.text or C.dim)
			header.chevron:SetShown(sorted)
			if sorted then
				header.chevron:Point(not ascending)
				header.chevron:ClearAllPoints()
				if column.align == "LEFT" then
					header.chevron:SetPoint("LEFT", header.label, "LEFT", header.label:GetStringWidth() + 5, 0)
				else
					header.chevron:SetPoint("RIGHT", header.label, "RIGHT", -header.label:GetStringWidth() - 5, 0)
				end
			end
		end
	end
end

local function SetSort(key)
	local db = DB()
	if db.sortKey == key then
		db.sortAsc = not db.sortAsc
	else
		db.sortKey = key
		db.sortAsc = key == "name"
	end
	RebuildFields()
	PaintHeader()
	W.Tick()
end

local function OpenColumnMenu(anchor)
	Utils.Menu(anchor, function(root)
		root:CreateTitle(L["Columns"])
		for _, column in ipairs(COLUMNS) do
			if column.key ~= "name" then
				local key = column.key
				root:CreateCheckbox(ColumnLabel(column), function()
					return DB().columns[key] == true
				end, function()
					DB().columns[key] = not DB().columns[key]
					W.Refresh()
				end)
			end
		end
	end)
end

-- --- detail pane --------------------------------------------------------------------------------

local counts = {}

local function BuildDetail(parent)
	local d = CreateFrame("Frame", nil, parent)
	d.back = Utils.Pixel(d, "BACKGROUND", C.band)
	d.back:SetAllPoints()
	d.rule = Utils.Pixel(d, "BORDER", C.line)
	d.rule:SetHeight(1)
	d.rule:SetPoint("TOPLEFT")
	d.rule:SetPoint("TOPRIGHT")

	d.close = Utils.CloseButton(d, 18)
	d.close:SetPoint("TOPRIGHT", -6, -6)
	d.close:SetScript("OnClick", function()
		W.Select(nil)
	end)

	d.title = Utils.FontString(d, "Highlight")
	d.title:SetPoint("TOPLEFT", PAD, -PAD)
	d.title:SetJustifyH("LEFT")
	d.meta = Utils.FontString(d, "Disable")
	d.meta:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -3)
	d.meta:SetJustifyH("LEFT")
	d.notes = Utils.FontString(d, "Disable")
	d.notes:SetPoint("TOPLEFT", d.meta, "BOTTOMLEFT", 0, -3)
	d.notes:SetJustifyH("LEFT")
	d.notes:SetWordWrap(true)
	d.notes:SetMaxLines(2)

	-- Two columns of figures.
	d.pairs = {}
	local PAIRS = {
		{ L["CPU now"], function(e) return Utils.Ms(e.now) end },
		{ L["Share of frame"], function(e) return Utils.Percent(P.Share(e)) end },
		{ L["Average since reload"], function(e) return Utils.Ms(e.avg) end },
		{ L["Average in boss fights"], function(e) return Utils.Ms(e.boss) end },
		{ L["Last frame"], function(e) return Utils.Ms(e.last) end },
		{ L["Peak frame"], function(e) return Utils.Ms(e.peak) end },
		{ L["Memory"], function(e) return e.memoryAt and Utils.Memory(e.memory) or L["not scanned"] end },
		{ L["Growth"], function(e) return e.growthKnown and Utils.Rate(e.growth) or L["after two scans"] end },
	}
	for index, spec in ipairs(PAIRS) do
		local label = Utils.FontString(d, "Disable")
		label:SetJustifyH("LEFT")
		label:SetText(spec[1])
		local value = Utils.FontString(d, "HighlightSmall")
		value:SetJustifyH("RIGHT")
		d.pairs[index] = { label = label, value = value, get = spec[2] }
	end

	-- Slow frame counts, one bar per threshold.
	d.histTitle = Utils.FontString(d, "Disable")
	d.histTitle:SetJustifyH("LEFT")
	d.bars = {}
	for index, ms in ipairs(P.THRESHOLDS) do
		local bar = {}
		bar.label = Utils.FontString(d, "Disable")
		bar.label:SetJustifyH("RIGHT")
		bar.label:SetText(format(">%d ms", ms))
		bar.track = Utils.Pixel(d, "BORDER", C.cell)
		bar.fill = Utils.Pixel(d, "ARTWORK", C.bar)
		bar.count = Utils.FontString(d, "HighlightSmall")
		bar.count:SetJustifyH("RIGHT")
		d.bars[index] = bar
	end

	d.toggle = Utils.Button(d, L["Disable after reload"], 150, 22)
	d.toggle:SetScript("OnClick", function()
		if state.selected then
			W.ToggleEnabled(state.selected)
		end
	end)
	d.toggle:SetScript("OnEnter", function(self)
		Utils.Tooltip(self, "ANCHOR_TOP", self:GetText(), L["For this character. Handy for checking whether the stutter goes away without this addon; enable it again the same way."])
	end)
	d.toggle:SetScript("OnLeave", GameTooltip_Hide)
	d.chat = Utils.Button(d, L["Put in chat"], 110, 22)
	d.chat:SetScript("OnClick", function()
		if state.selected then
			Utils.InsertInChat(EntrySummary(state.selected))
		end
	end)
	return d
end

local function LayoutDetail(width)
	local d = ui.detail
	local left = floor(width * 0.52)
	local lineH = Utils.FontHeight("HighlightSmall") + 5
	d.title:SetWidth(left - PAD * 2)
	d.meta:SetWidth(left - PAD * 2)
	d.notes:SetWidth(left - PAD * 2)
	local pairTop = PAD + Utils.FontHeight("Highlight") + 3 + (Utils.FontHeight("Disable") + 3) * 3 + 8
	local half = floor((left - PAD * 2 - 16) / 2)
	for index, pair in ipairs(d.pairs) do
		local col = (index - 1) % 2
		local line = floor((index - 1) / 2)
		local x = PAD + col * (half + 16)
		local y = -(pairTop + line * lineH)
		pair.label:ClearAllPoints()
		pair.label:SetPoint("TOPLEFT", d, "TOPLEFT", x, y)
		pair.label:SetWidth(half - 60)
		pair.value:ClearAllPoints()
		pair.value:SetPoint("TOPRIGHT", d, "TOPLEFT", x + half, y)
		pair.value:SetWidth(70)
	end
	local right = left + 10
	local rightW = width - right - PAD - 20
	d.histTitle:ClearAllPoints()
	d.histTitle:SetPoint("TOPLEFT", d, "TOPLEFT", right, -PAD)
	d.histTitle:SetWidth(rightW)
	local barLine = Utils.FontHeight("HighlightSmall") + 3
	for index, bar in ipairs(d.bars) do
		local y = -(PAD + Utils.FontHeight("Disable") + 6 + (index - 1) * barLine)
		bar.label:ClearAllPoints()
		bar.label:SetPoint("TOPLEFT", d, "TOPLEFT", right, y)
		bar.label:SetWidth(62)
		bar.track:ClearAllPoints()
		bar.track:SetPoint("TOPLEFT", d, "TOPLEFT", right + 68, y - 2)
		bar.track:SetSize(max(20, rightW - 68 - 52), barLine - 6)
		bar.fill:ClearAllPoints()
		bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT", 0, 0)
		bar.fill:SetHeight(barLine - 6)
		bar.count:ClearAllPoints()
		bar.count:SetPoint("TOPRIGHT", d, "TOPLEFT", right + rightW, y)
		bar.count:SetWidth(48)
		bar.trackW = max(20, rightW - 68 - 52)
	end
	d.toggle:ClearAllPoints()
	d.toggle:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", right, PAD)
	d.chat:ClearAllPoints()
	d.chat:SetPoint("LEFT", d.toggle, "RIGHT", 8, 0)
end

-- The detail pane's height at this text size.
local function DetailHeight()
	local barLine = Utils.FontHeight("HighlightSmall") + 3
	local right = PAD + Utils.FontHeight("Disable") + 6 + #P.THRESHOLDS * barLine + 8 + 22 + PAD
	local lineH = Utils.FontHeight("HighlightSmall") + 5
	local left = PAD + Utils.FontHeight("Highlight") + 3 + (Utils.FontHeight("Disable") + 3) * 3 + 8 + 4 * lineH + PAD
	return max(right, left)
end

local function PaintDetail()
	local d = ui.detail
	local e = state.selected
	if not (d and e and d:IsShown()) then
		return
	end
	P.Fill(e, P.ALL_FIELDS)
	d.title:SetText(e.title)
	local meta = {}
	if e.version then
		meta[#meta + 1] = format(L["version %s"], e.version)
	end
	if e.author then
		meta[#meta + 1] = format(L["by %s"], e.author)
	end
	meta[#meta + 1] = format(L["folder %s"], e.name)
	if e.lod then
		meta[#meta + 1] = L["load on demand"]
	end
	d.meta:SetText(table.concat(meta, " · "))
	d.notes:SetText(e.notes or "")
	for _, pair in ipairs(d.pairs) do
		pair.value:SetText(pair.get(e))
	end
	d.histTitle:SetText(format(L["Frames this addon made slow, %s"], P.PeriodText()))
	P.Counts(e, counts)
	local top = 0
	for i = 1, #P.THRESHOLDS do
		top = max(top, counts[i])
	end
	local scale = math.log10(top + 1)
	for index, bar in ipairs(d.bars) do
		local value = counts[index]
		bar.count:SetText(tostring(value))
		Tone(bar.count, value > 0 and 0 or 1)
		local fraction = scale > 0 and math.log10(value + 1) / scale or 0
		bar.fill:SetWidth(max(1, bar.trackW * fraction))
		bar.fill:SetShown(value > 0)
	end
	d.toggle:SetText(DisabledForNextReload(e) and L["Enable again after reload"] or L["Disable after reload"])
	d.toggle:FitWidth(150)
end

function W.Select(entry)
	state.selected = entry
	W.Layout()
	W.Tick()
end

-- --- slow frame log -----------------------------------------------------------------------------

local function LogItem(index)
	local log = DB().spikeLog
	return log[#log - index + 1]
end

local function ShowLogTooltip(row)
	local item = row.item
	if not item then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(S.Who(item), C.heading[1], C.heading[2], C.heading[3])
	local function Pair(label, value)
		if value then
			GameTooltip:AddDoubleLine(label, value, C.dim[1], C.dim[2], C.dim[3], 1, 1, 1)
		end
	end
	Pair(L["When"], date("%Y-%m-%d %H:%M:%S", item.t))
	Pair(L["Frame"], S.HowBad(item))
	if item.folder and item.folder ~= item.addon then
		Pair(L["Folder"], item.folder)
	end
	Pair(L["Where"], item.zone)
	Pair(L["State"], S.State(item))
	if not item.addon then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format(L["No single addon took %d ms or more: several shared the frame. Sort the table by Last frame or Peak to see who was busy."], item.over or P.spikeMs), 1, 1, 1, true)
	elseif not item.ms then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["The exact length isn't known: the addon had a longer frame earlier, so its peak didn't move."], C.dim[1], C.dim[2], C.dim[3], true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Shift-click: put in chat"], C.faint[1], C.faint[2], C.faint[3])
	GameTooltip:Show()
end

local function CreateLogRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row.stripe = Utils.Pixel(row, "BACKGROUND", C.stripe)
	row.stripe:SetAllPoints()
	local hover = Utils.Pixel(row, "HIGHLIGHT", C.hover)
	hover:SetAllPoints()
	row.time = Utils.FontString(row, "HighlightSmall")
	row.who = Utils.FontString(row, "HighlightSmall")
	row.frame = Utils.FontString(row, "HighlightSmall")
	row.where = Utils.FontString(row, "HighlightSmall")
	row.state = Utils.FontString(row, "HighlightSmall")
	row.time:SetJustifyH("LEFT")
	row.who:SetJustifyH("LEFT")
	row.frame:SetJustifyH("RIGHT")
	row.where:SetJustifyH("LEFT")
	row.state:SetJustifyH("LEFT")
	row:SetScript("OnEnter", ShowLogTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self)
		if self.item and IsShiftKeyDown() then
			Utils.InsertInChat(date("%H:%M:%S ", self.item.t) .. S.Describe(self.item))
		end
	end)
	return row
end

local function PlaceLogRow(row, width)
	local flex = max(80, width - LOG_TIME_W - LOG_FRAME_W - LOG_STATE_W - 16)
	local whoW = floor(flex * 0.45)
	local whereW = flex - whoW
	local x = 4
	local function Put(fontString, w)
		fontString:ClearAllPoints()
		fontString:SetPoint("LEFT", row, "LEFT", x + 4, 0)
		fontString:SetWidth(w - 8)
		x = x + w
	end
	Put(row.time, LOG_TIME_W)
	Put(row.who, whoW)
	Put(row.frame, LOG_FRAME_W)
	Put(row.where, whereW + 4)
	Put(row.state, LOG_STATE_W)
end

function W.PaintLog()
	if not (ui.frame and ui.logList:IsShown()) then
		return
	end
	local log = DB().spikeLog
	local total = #log
	local maxOffset = max(0, total - layout.logVisible)
	state.logOffset = max(0, min(state.logOffset, maxOffset))
	for i = 1, layout.logVisible do
		local row = logRows[i]
		local item = LogItem(state.logOffset + i)
		if item then
			row.item = item
			row.time:SetText(Utils.Clock(item.t))
			row.who:SetText(S.Who(item))
			Tone(row.who, item.addon and 0 or 1)
			row.frame:SetText(S.HowBad(item))
			row.where:SetText(item.zone or "")
			row.state:SetText(S.State(item))
			row:Show()
		else
			row.item = nil
			row:Hide()
		end
	end
	for i = layout.logVisible + 1, #logRows do
		logRows[i].item = nil
		logRows[i]:Hide()
	end
	ui.logScroll:Set(total, layout.logVisible, state.logOffset)
	if total == 0 then
		ui.logEmpty:SetText(S.Watching() and format(L["No slow frames over %d ms yet. They're logged here as they happen, with where and when."], P.spikeMs)
			or L["The slow frame watch is off. Turn it on in the settings to log stutters as they happen."])
		ui.logEmpty:Show()
	else
		ui.logEmpty:Hide()
	end
	ui.logStatus:SetText(S.Watching()
		and format(L["Watching for frames over %d ms. %d logged, %d this session."], P.spikeMs, total, S.session)
		or format(L["The watch is off. %d logged."], total))
end

-- --- summary and footer -------------------------------------------------------------------------

local function PaintSummary()
	local s = ui.summary
	local t = P.totals
	local fps = t.fps
	s[1].value:SetText(format(L["%.0f fps"], fps))
	s[1].sub:SetText(fps > 0 and format(L["%.1f ms a frame"], 1000 / fps) or "")
	if P.available then
		s[2].value:SetText(Utils.Ms(t.now))
		s[2].sub:SetText(format(L["%s of each frame"], Utils.Percent(t.share)))
	else
		s[2].value:SetText("-")
		s[2].sub:SetText(L["profiler off"])
	end
	s[3].value:SetText(Utils.Memory(M.heap))
	s[3].sub:SetText(M.heapKnown and format(L["%s growth"], Utils.Rate(M.heapGrowth)) or L["measuring..."])
	s[4].label:SetText(format(L["Frames over %d ms"], P.spikeMs))
	s[4].value:SetText(P.available and tostring(t.slow) or "-")
	local last = S.Latest()
	local period = P.PeriodText()
	if last and last.addon then
		s[4].sub:SetText(format(L["%s, last: %s"], period, last.addon))
	else
		s[4].sub:SetText(period)
	end
	Tone(s[4].value, (DB().warnColor and t.slow > 0) and 2 or 0)
end

local function PaintFooter()
	local parts = {}
	if P.available then
		parts[#parts + 1] = format(L["CPU every %s s"], tostring(DB().refreshRate))
	else
		parts[#parts + 1] = L["no CPU figures (profiler off)"]
	end
	local interval = M.Interval()
	if not M.Supported() then
		parts[#parts + 1] = L["no memory figures"]
	elseif interval then
		local text = format(L["memory every %d s"], interval)
		if M.lastAt then
			text = text .. " " .. format(L["(last scan %d ms, %s ago)"], M.lastCost or 0, Utils.Duration(GetTime() - M.lastAt))
		end
		if InCombatLockdown() then
			text = text .. ", " .. L["paused in combat"]
		end
		parts[#parts + 1] = text
	else
		parts[#parts + 1] = L["memory only when asked"]
	end
	parts[#parts + 1] = format(L["%d addons"], #P.list)
	local own = P.byName[addonName]
	if own and P.available then
		parts[#parts + 1] = format(L["this addon %s"], Utils.Ms(own.now))
	end
	ui.footer:SetText(table.concat(parts, "  ·  "))
end

-- --- ticking ------------------------------------------------------------------------------------

local ticker

function W.Tick()
	if not (ui.frame and ui.frame:IsShown()) then
		return
	end
	local db = DB()
	M.SampleHeap()
	if state.tab == "addons" then
		P.Sample(sortFields)
		M.ScanIfDue()
		P.BuildView(state.search, db.onlyProblems, db.sortKey, db.sortAsc)
		if state.selected and not P.byName[state.selected.name] then
			state.selected = nil
		end
		W.PaintRows()
		PaintDetail()
	else
		P.SampleTotals()
	end
	PaintSummary()
	PaintFooter()
end

local SafeTick = Utils.Protect("window", function()
	W.Tick()
end)

local function StartTicker()
	if ticker then
		ticker:Cancel()
	end
	ticker = C_Timer.NewTicker(DB().refreshRate, SafeTick)
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- --- layout -------------------------------------------------------------------------------------

local function LayoutColumns(width)
	local fixed = 0
	for _, column in ipairs(COLUMNS) do
		column.shown = ColumnShown(column)
		if column.shown and column.width then
			fixed = fixed + column.width
		end
	end
	local nameW = max(NAME_MIN, width - fixed)
	local x = 0
	for _, column in ipairs(COLUMNS) do
		if column.shown then
			column.x = x
			column.w = column.width or nameW
			x = x + column.w
		end
	end
	return fixed + NAME_MIN
end

local function SummaryHeight()
	return 10 + Utils.FontHeight("Disable") + 2 + Utils.FontHeight("HighlightLarge") + 2 + Utils.FontHeight("Disable") + 10
end

function W.Layout()
	local f = ui.frame
	if not f then
		return
	end
	layout.rowH = max(18, Utils.FontHeight("HighlightSmall") + 8)
	local width = f:GetWidth()
	local height = f:GetHeight()
	local summaryH = SummaryHeight()
	local headerH = layout.rowH + 2

	-- Summary cells side by side.
	local cellW = (width - PAD * 2 - 8 * 3) / 4
	for index, cell in ipairs(ui.summary) do
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (index - 1) * (cellW + 8), -(TITLE_H + 8))
		cell:SetSize(cellW, summaryH)
	end
	local toolbarTop = TITLE_H + 8 + summaryH + 8
	ui.toolbar:ClearAllPoints()
	ui.toolbar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -toolbarTop)
	ui.toolbar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -toolbarTop)
	ui.toolbar:SetHeight(TOOLBAR_H)
	local listTop = toolbarTop + TOOLBAR_H + 6

	local detailShown = state.tab == "addons" and state.selected ~= nil
	local detailH = detailShown and DetailHeight() or 0
	ui.detail:SetShown(detailShown)
	if detailShown then
		ui.detail:ClearAllPoints()
		ui.detail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, FOOTER_H)
		ui.detail:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H)
		ui.detail:SetHeight(detailH)
		LayoutDetail(width - 2)
	end

	-- The addon table.
	local listW = width - PAD * 2 - SCROLL_W - 4
	local minimum = LayoutColumns(listW)
	if f.SetResizeBounds then
		f:SetResizeBounds(minimum + PAD * 2 + SCROLL_W + 4, 360, 1600, 1100)
	end
	ui.header:ClearAllPoints()
	ui.header:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -listTop)
	ui.header:SetSize(listW, headerH)
	for _, column in ipairs(COLUMNS) do
		local header = column.header
		if column.shown then
			header:ClearAllPoints()
			header:SetPoint("LEFT", ui.header, "LEFT", column.x, 0)
			header:SetSize(column.w, headerH)
			header.label:ClearAllPoints()
			header.label:SetPoint("LEFT", header, "LEFT", 4, 0)
			header.label:SetPoint("RIGHT", header, "RIGHT", -4, 0)
			header.label:SetJustifyH(column.align or "RIGHT")
		end
	end
	local bodyTop = listTop + headerH
	local bodyH = height - bodyTop - FOOTER_H - detailH - 4
	ui.list:ClearAllPoints()
	ui.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -bodyTop)
	ui.list:SetSize(listW, max(layout.rowH, bodyH))
	ui.scroll.height = max(layout.rowH, bodyH)
	ui.scroll:ClearAllPoints()
	ui.scroll:SetPoint("TOPLEFT", ui.list, "TOPRIGHT", 4, 0)
	ui.scroll:SetPoint("BOTTOMLEFT", ui.list, "BOTTOMRIGHT", 4, 0)
	layout.visible = max(1, floor(bodyH / layout.rowH))
	for i = 1, layout.visible do
		local row = rows[i]
		if not row then
			row = CreateRow(ui.list)
			rows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, -(i - 1) * layout.rowH)
		row:SetSize(listW, layout.rowH)
		row.stripe:SetShown(i % 2 == 0)
		PlaceRowCells(row)
	end
	-- The slow frame log, in the same place.
	local logW = width - PAD * 2 - SCROLL_W - 4
	ui.logHeader:ClearAllPoints()
	ui.logHeader:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -listTop)
	ui.logHeader:SetSize(logW, headerH)
	PlaceLogRow(ui.logHeader, logW)
	local logBodyH = height - bodyTop - FOOTER_H - 4
	ui.logList:ClearAllPoints()
	ui.logList:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -bodyTop)
	ui.logList:SetSize(logW, max(layout.rowH, logBodyH))
	ui.logScroll.height = max(layout.rowH, logBodyH)
	ui.logScroll:ClearAllPoints()
	ui.logScroll:SetPoint("TOPLEFT", ui.logList, "TOPRIGHT", 4, 0)
	ui.logScroll:SetPoint("BOTTOMLEFT", ui.logList, "BOTTOMRIGHT", 4, 0)
	layout.logVisible = max(1, floor(logBodyH / layout.rowH))
	for i = 1, layout.logVisible do
		local row = logRows[i]
		if not row then
			row = CreateLogRow(ui.logList)
			logRows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui.logList, "TOPLEFT", 0, -(i - 1) * layout.rowH)
		row:SetSize(logW, layout.rowH)
		row.stripe:SetShown(i % 2 == 0)
		PlaceLogRow(row, logW)
	end

	local addons = state.tab == "addons"
	ui.header:SetShown(addons)
	ui.list:SetShown(addons)
	ui.addonTools:SetShown(addons)
	ui.logHeader:SetShown(not addons)
	ui.logList:SetShown(not addons)
	ui.logTools:SetShown(not addons)
	if not addons then
		ui.scroll:Hide()
	else
		ui.logScroll:Hide()
	end
	for _, tab in ipairs(ui.tabs) do
		local on = tab.key == state.tab
		Paint(tab.label, on and C.text or C.dim)
		tab.line:SetShown(on)
	end
	ui.markButton:SetText(P.Marked() and L["Back to since login"] or L["Measure from now"])
	ui.markButton:FitWidth(120)
	PaintHeader()
	W.PaintLog()
end

-- After a setting changed: columns, threshold, text size or refresh rate.
function W.Refresh()
	if not ui.frame then
		return
	end
	RebuildFields()
	W.Layout()
	if ui.frame:IsShown() then
		StartTicker()
		W.Tick()
	end
end

-- --- building -----------------------------------------------------------------------------------

local function SaveGeometry()
	local f = ui.frame
	local point, _, relativePoint, x, y = f:GetPoint(1)
	local db = DB()
	db.window.point, db.window.relativePoint, db.window.x, db.window.y = point, relativePoint, x, y
	db.window.width, db.window.height = floor(f:GetWidth() + 0.5), floor(f:GetHeight() + 0.5)
end

local function RestoreGeometry()
	local f = ui.frame
	local g = DB().window
	f:SetSize(g.width or 840, g.height or 580)
	f:ClearAllPoints()
	if g.point then
		f:SetPoint(g.point, UIParent, g.relativePoint or g.point, g.x or 0, g.y or 0)
	else
		f:SetPoint("CENTER")
	end
end

function W.ResetGeometry()
	local db = DB()
	db.window = {}
	if ui.frame then
		RestoreGeometry()
		W.Layout()
	end
end

local function BuildSummaryCell(parent)
	local cell = CreateFrame("Frame", nil, parent)
	local back = Utils.Pixel(cell, "BACKGROUND", C.band)
	back:SetAllPoints()
	cell.label = Utils.FontString(cell, "Disable")
	cell.label:SetPoint("TOPLEFT", 10, -10)
	cell.label:SetPoint("RIGHT", -8, 0)
	cell.label:SetJustifyH("LEFT")
	cell.value = Utils.FontString(cell, "HighlightLarge")
	cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
	cell.value:SetPoint("RIGHT", -8, 0)
	cell.value:SetJustifyH("LEFT")
	cell.sub = Utils.FontString(cell, "Disable")
	cell.sub:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -2)
	cell.sub:SetPoint("RIGHT", -8, 0)
	cell.sub:SetJustifyH("LEFT")
	return cell
end

local function BuildSearch(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(190, 22)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetFontObject(Utils.Font("HighlightSmall"))
	box:SetTextInsets(22, 20, 0, 0)
	local back = Utils.Pixel(box, "BACKGROUND", C.cell)
	back:SetAllPoints()
	Utils.Border(box, C.line)
	local icon = box:CreateTexture(nil, "OVERLAY")
	icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	icon:SetSize(13, 13)
	icon:SetPoint("LEFT", 6, -1)
	icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
	box.hint = Utils.FontString(box, "Disable")
	box.hint:SetPoint("LEFT", 22, 0)
	box.hint:SetText(L["Search addons"])
	local clear = Utils.CloseButton(box, 16)
	clear:SetPoint("RIGHT", -3, 0)
	clear:Hide()
	clear:SetScript("OnClick", function()
		box:SetText("")
		box:ClearFocus()
	end)
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.hint:SetShown(text == "" and not self:HasFocus())
		clear:SetShown(text ~= "")
		local search = Utils.Trim(text):lower()
		if search ~= state.search then
			state.search = search
			state.offset = 0
			W.Tick()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.hint:Hide()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self.hint:SetShown((self:GetText() or "") == "")
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function TipOn(widget, title, text)
	widget:EnableMouse(true)
	widget:SetScript("OnEnter", function(self)
		Utils.Tooltip(self, "ANCHOR_TOP", title, text)
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function Build()
	local f = CreateFrame("Frame", "LaggyAddonDetectorFrame", UIParent)
	ui.frame = f
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:EnableMouse(true)
	f:Hide()
	Utils.Panel(f)
	tinsert(UISpecialFrames, f:GetName())

	-- Title bar: the name, the two views, settings and close.
	local band = Utils.Pixel(f, "BACKGROUND", C.band)
	band:SetDrawLayer("BACKGROUND", -6)
	band:SetPoint("TOPLEFT", 1, -1)
	band:SetPoint("TOPRIGHT", -1, -1)
	band:SetHeight(TITLE_H - 1)
	local rule = Utils.Pixel(f, "BORDER", C.line)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
	rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")

	-- Dragging any bare part of the window moves it (rows and controls keep their own clicks).
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function()
		f:StartMoving()
	end)
	f:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		f:SetUserPlaced(false)
		SaveGeometry()
	end)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(Utils.ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", PAD, -7)
	local title = Utils.FontString(f, "Normal")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetText(Utils.TITLE)
	Paint(title, C.text)

	ui.tabs = {}
	local previous = title
	for _, spec in ipairs({ { key = "addons", text = L["Addons"] }, { key = "log", text = L["Slow frame log"] } }) do
		local tab = CreateFrame("Button", nil, f)
		tab.key = spec.key
		tab.label = Utils.FontString(tab, "HighlightSmall")
		tab.label:SetPoint("CENTER")
		tab.label:SetText(spec.text)
		tab:SetSize(tab.label:GetStringWidth() + 20, TITLE_H - 2)
		tab:SetPoint("LEFT", previous, "RIGHT", previous == title and 18 or 2, 0)
		tab.line = Utils.Pixel(tab, "ARTWORK", C.text)
		tab.line:SetHeight(2)
		tab.line:SetPoint("BOTTOMLEFT", 6, 0)
		tab.line:SetPoint("BOTTOMRIGHT", -6, 0)
		local glow = Utils.Pixel(tab, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
		glow:SetAllPoints()
		tab:SetScript("OnClick", function(self)
			state.tab = self.key
			W.Layout()
			W.Tick()
		end)
		ui.tabs[#ui.tabs + 1] = tab
		previous = tab
	end

	local close = Utils.CloseButton(f, 22)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		f:Hide()
	end)
	local settings = Utils.Button(f, L["Settings"], 70, 20)
	settings:FitWidth(70)
	settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
	settings:SetScript("OnClick", function()
		if ns.Settings then
			ns.Settings.Open()
		end
	end)

	-- Summary strip.
	ui.summary = {}
	local labels = { L["Frame rate"], L["Addons' CPU a frame"], L["Lua memory"], "" }
	for index = 1, 4 do
		local cell = BuildSummaryCell(f)
		cell.label:SetText(labels[index])
		ui.summary[index] = cell
	end
	TipOn(ui.summary[2], L["Addons' CPU a frame"], L["All addons' CPU time a frame, averaged over the last 60 frames, and its share of the whole frame."])
	TipOn(ui.summary[3], L["Lua memory"], L["All Lua memory (the game's interface and every addon) and how fast it grows. The faster it grows, the more often the garbage collector runs."])
	ui.summary[4]:EnableMouse(true)
	ui.summary[4]:SetScript("OnEnter", function(self)
		local last = S.Latest()
		Utils.Tooltip(self, "ANCHOR_TOP", format(L["Frames over %d ms"], P.spikeMs),
			format(L["Frames where addons together took longer than %d ms, %s."], P.spikeMs, P.PeriodText()),
			last and format(L["Latest: %s, %s, %s (%s)."], S.Who(last), S.HowBad(last), Utils.Clock(last.t), S.State(last):lower()) or nil,
			L["Click for the slow frame log."])
	end)
	ui.summary[4]:SetScript("OnLeave", GameTooltip_Hide)
	ui.summary[4]:SetScript("OnMouseUp", function()
		state.tab = "log"
		W.Layout()
		W.Tick()
	end)

	-- Toolbar: one set of tools for each view.
	ui.toolbar = CreateFrame("Frame", nil, f)
	ui.addonTools = CreateFrame("Frame", nil, ui.toolbar)
	ui.addonTools:SetAllPoints()
	ui.search = BuildSearch(ui.addonTools)
	ui.search:SetPoint("LEFT", 0, 0)
	local problems = Utils.Checkbox(ui.addonTools, L["Only problems"], function()
		return DB().onlyProblems
	end, function(value)
		DB().onlyProblems = value
		state.offset = 0
		W.Tick()
	end)
	problems:SetPoint("LEFT", ui.search, "RIGHT", 12, 0)
	problems:HookScript("OnEnter", function(self)
		Utils.Tooltip(self, "ANCHOR_TOP", L["Only problems"],
			format(L["Addons using %s or more a frame, that made a frame over %d ms (%s), or whose memory grows %s or faster. Thresholds are in the settings."],
				Utils.Ms(DB().cpuWarn), P.spikeMs, P.PeriodText(), Utils.Rate(DB().growthWarn)))
	end)
	problems:HookScript("OnLeave", GameTooltip_Hide)
	ui.problems = problems

	local report = Utils.Button(ui.addonTools, L["Report"], 70, 22)
	report:FitWidth(70)
	report:SetPoint("RIGHT", 0, 0)
	report:SetScript("OnClick", function()
		ns.Report()
	end)
	TipOn(report, L["Report"], L["A summary in chat: the busiest addons, slow frames and memory growth."])
	local scan = Utils.Button(ui.addonTools, L["Scan memory"], 100, 22)
	scan:FitWidth(100)
	scan:SetPoint("RIGHT", report, "LEFT", -6, 0)
	scan:SetScript("OnClick", function()
		if not M.Scan() then
			Utils.Print(L["Memory can't be scanned in combat."])
		end
		W.Tick()
	end)
	TipOn(scan, L["Scan memory"], L["Reads every addon's memory now. The game pauses for a moment while it counts, so it never runs in combat."])
	local mark = Utils.Button(ui.addonTools, L["Measure from now"], 120, 22)
	mark:SetPoint("RIGHT", scan, "LEFT", -6, 0)
	mark:SetScript("OnClick", function()
		if P.Marked() then
			P.ClearMark()
		else
			P.Mark()
		end
	end)
	TipOn(mark, L["Measure from now"], L["Counts slow frames from this moment: handy for one pull or one key. Averages and peaks still count from the last reload."])
	ui.markButton = mark

	ui.logTools = CreateFrame("Frame", nil, ui.toolbar)
	ui.logTools:SetAllPoints()
	ui.logStatus = Utils.FontString(ui.logTools, "HighlightSmall")
	ui.logStatus:SetPoint("LEFT", 2, 0)
	ui.logStatus:SetJustifyH("LEFT")
	local clear = Utils.Button(ui.logTools, L["Clear log"], 80, 22)
	clear:FitWidth(80)
	clear:SetPoint("RIGHT", 0, 0)
	local armed = 0
	clear:SetScript("OnClick", function(self)
		if GetTime() - armed < 4 then
			armed = 0
			self:SetText(L["Clear log"])
			S.Clear()
		else
			armed = GetTime()
			self:SetText(L["Click again to clear"])
			self:FitWidth(80)
			C_Timer.After(4, function()
				if armed > 0 and GetTime() - armed >= 4 then
					armed = 0
					self:SetText(L["Clear log"])
				end
			end)
		end
	end)
	local logReport = Utils.Button(ui.logTools, L["Report"], 70, 22)
	logReport:FitWidth(70)
	logReport:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	logReport:SetScript("OnClick", function()
		ns.ReportSpikes(10)
	end)
	TipOn(logReport, L["Report"], L["The last 10 slow frames in chat."])

	-- Addon table.
	ui.header = CreateFrame("Frame", nil, f)
	local headerBack = Utils.Pixel(ui.header, "BACKGROUND", C.band)
	headerBack:SetAllPoints()
	for _, column in ipairs(COLUMNS) do
		local header = CreateFrame("Button", nil, ui.header)
		header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		header.label = Utils.FontString(header, "HighlightSmall")
		header.chevron = Chevron(header)
		local glow = Utils.Pixel(header, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
		glow:SetAllPoints()
		header:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				OpenColumnMenu(self)
			else
				SetSort(column.key)
			end
		end)
		header:SetScript("OnEnter", function(self)
			local tip = column.key == "slow" and SlowTip() or column.tip
			Utils.Tooltip(self, "ANCHOR_TOP", ColumnLabel(column), tip, " ", L["Click to sort. Right-click to choose columns."])
		end)
		header:SetScript("OnLeave", GameTooltip_Hide)
		column.header = header
	end
	ui.list = CreateFrame("Frame", nil, f)
	ui.list:EnableMouseWheel(true)
	ui.list:SetScript("OnMouseWheel", function(_, delta)
		ScrollTo(state.offset - delta * 3)
	end)
	ui.scroll = ScrollBar(f, ScrollTo)
	ui.empty = Utils.FontString(ui.list, "Disable")
	ui.empty:SetPoint("TOPLEFT", 20, -30)
	ui.empty:SetPoint("TOPRIGHT", -20, -30)
	ui.empty:SetWordWrap(true)

	ui.detail = BuildDetail(f)
	ui.detail:Hide()

	-- Slow frame log.
	ui.logHeader = CreateFrame("Frame", nil, f)
	local logHeaderBack = Utils.Pixel(ui.logHeader, "BACKGROUND", C.band)
	logHeaderBack:SetAllPoints()
	for key, text in pairs({ time = L["Time"], who = L["Addon"], frame = L["Frame"], where = L["Where"], state = L["State"] }) do
		local label = Utils.FontString(ui.logHeader, "HighlightSmall")
		label:SetText(text)
		Paint(label, C.dim)
		label:SetJustifyH(key == "frame" and "RIGHT" or "LEFT")
		ui.logHeader[key] = label
	end
	ui.logList = CreateFrame("Frame", nil, f)
	ui.logList:EnableMouseWheel(true)
	ui.logScroll = ScrollBar(f, function(offset)
		state.logOffset = offset
		W.PaintLog()
	end)
	ui.logList:SetScript("OnMouseWheel", function(_, delta)
		state.logOffset = state.logOffset - delta * 3
		W.PaintLog()
	end)
	ui.logEmpty = Utils.FontString(ui.logList, "Disable")
	ui.logEmpty:SetPoint("TOPLEFT", 20, -30)
	ui.logEmpty:SetPoint("TOPRIGHT", -20, -30)
	ui.logEmpty:SetWordWrap(true)

	-- Footer and resize grip.
	ui.footer = Utils.FontString(f, "Disable")
	ui.footer:SetPoint("BOTTOMLEFT", PAD, 6)
	ui.footer:SetPoint("BOTTOMRIGHT", -24, 6)
	ui.footer:SetJustifyH("LEFT")
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		f:SetUserPlaced(false)
		SaveGeometry()
		W.Layout()
		W.Tick()
	end)

	f:SetScript("OnSizeChanged", function()
		W.Layout()
		W.PaintRows()
	end)
	f:SetScript("OnShow", function()
		RebuildFields()
		W.Layout()
		problems:Refresh()
		-- A memory scan on opening, unless one ran moments ago.
		if not M.lastAt or GetTime() - M.lastAt > 3 then
			M.Scan()
		end
		SafeTick()
		StartTicker()
	end)
	f:SetScript("OnHide", function()
		StopTicker()
		ui.search:ClearFocus()
	end)

	RestoreGeometry()
	RebuildFields()
	W.Layout()
end

function W.Toggle()
	if not ui.frame then
		Build()
	end
	ui.frame:SetShown(not ui.frame:IsShown())
end

function W.Show(tab)
	if not ui.frame then
		Build()
	end
	if tab then
		state.tab = tab
	end
	if ui.frame:IsShown() then
		W.Layout()
		W.Tick()
	else
		ui.frame:Show()
	end
end

function W.IsShown()
	return ui.frame and ui.frame:IsShown()
end

ns.On("SPIKE", function()
	if W.IsShown() then
		W.PaintLog()
		PaintSummary()
	end
end)

ns.On("PERIOD_CHANGED", function()
	if W.IsShown() then
		W.Layout()
		W.Tick()
	end
end)

-- For the tests (tests/scenarios.lua): the window's parts.
function W.Internals()
	return ui, rows, logRows, state, COLUMNS, layout
end
