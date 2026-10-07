local _, ns = ...

-- On-screen stats: a few live numbers on screen (off unless turned on in the settings). Each update
-- is a handful of cheap reads, and a line's text is set only when it changed.
--
-- The stats hang from an anchor: a top one grows down, a bottom one grows up, and left, centre or
-- right decide which way lines line up. Unlocked, they can be dragged anywhere; where they're
-- dropped picks the anchor (the nearer half of the screen top or bottom, the third left, centre or
-- right), so they stay put at any resolution. Locked, clicks go through them.

local Utils, L, P, M, S = ns.Utils, ns.L, ns.Profiler, ns.Memory, ns.SpikeWatch
local C = Utils.COLORS
local O = {}
ns.Overlay = O

local format, max = string.format, math.max

-- In the order they show.
O.ITEMS = {
	{ key = "fps", label = L["Frame rate"] },
	{ key = "frametime", label = L["Frame time"] },
	{ key = "latency", label = L["Latency (home / world)"] },
	{ key = "addons", label = L["Addons' CPU a frame"] },
	{ key = "top", label = L["Busiest addon"] },
	{ key = "memory", label = L["Lua memory and growth"] },
	{ key = "slow", label = L["Slow frames and the latest culprit"] },
}

O.ANCHORS = {
	{ "TOPLEFT", L["Top left"] },
	{ "TOP", L["Top"] },
	{ "TOPRIGHT", L["Top right"] },
	{ "BOTTOMLEFT", L["Bottom left"] },
	{ "BOTTOM", L["Bottom"] },
	{ "BOTTOMRIGHT", L["Bottom right"] },
}
local VALID_ANCHOR = {}
for _, anchor in ipairs(O.ANCHORS) do
	VALID_ANCHOR[anchor[1]] = true
end

-- A new slow frame stays tinted this long, so it catches the eye.
local RECENT_SLOW = 10
local PAD_X, PAD_Y, LINE_GAP = 6, 4, 2
-- Away from the screen's edge when an anchor is picked from the list.
local EDGE = 6

local frame, back, border, hint, ticker
local lines = {} -- one font string per line, reused
local parts = {}
local lastContent, lastSlow
local slowSeenAt = 0

local function Anchor()
	local point = ns.db.overlay.point
	return VALID_ANCHOR[point] and point or "TOPLEFT"
end

-- "LEFT", "RIGHT" or "" (centre), and whether the anchor is at the top.
local function Sides(point)
	local horizontal = point:find("LEFT") and "LEFT" or (point:find("RIGHT") and "RIGHT" or "")
	return horizontal, point:find("TOP") ~= nil
end

local function Content()
	table.wipe(parts)
	local items = ns.db.overlay.items
	P.SampleTotals()
	M.SampleHeap()
	local t = P.totals
	if items.fps then
		parts[#parts + 1] = format(L["%.0f fps"], t.fps)
	end
	if items.frametime and t.fps > 0 then
		parts[#parts + 1] = format(L["%.1f ms a frame"], 1000 / t.fps)
	end
	if items.latency then
		local _, _, home, world = GetNetStats()
		parts[#parts + 1] = format(L["Latency %d / %d ms"], home or 0, world or 0)
	end
	if items.addons and P.available then
		parts[#parts + 1] = format(L["Addons %s (%s)"], Utils.Ms(t.now), Utils.Percent(t.share))
	end
	if items.top and P.available then
		local top = P.Top(1)[1]
		if top and top.now >= 0.005 then
			parts[#parts + 1] = format(L["Busiest: %s %s"], top.title, Utils.Ms(top.now))
		end
	end
	if items.memory then
		parts[#parts + 1] = format(L["Lua %s, %s"], Utils.Memory(M.heap), Utils.Rate(M.heapGrowth))
	end
	if items.slow and P.available then
		if lastSlow and t.slow > lastSlow then
			slowSeenAt = GetTime()
		end
		lastSlow = t.slow
		local line = format(L["Slow frames %d"], t.slow)
		if S.last and S.last.addon then
			line = line .. " (" .. S.last.addon .. ")"
		end
		if ns.db.warnColor and GetTime() - slowSeenAt < RECENT_SLOW then
			line = Utils.Paint(line, C.warn)
		end
		parts[#parts + 1] = line
	end
	if #parts == 0 then
		parts[1] = L["(no items picked)"]
	end
	if ns.db.overlay.layout == "line" then
		local joined = table.concat(parts, "    ")
		table.wipe(parts)
		parts[1] = joined
	end
end

local function Line(index)
	local line = lines[index]
	if not line then
		line = frame:CreateFontString(nil, "OVERLAY")
		line:SetFontObject(Utils.Font("Overlay"))
		line:SetWordWrap(false)
		lines[index] = line
		line.placed = nil
	end
	return line
end

-- Lines top to bottom inside the frame, lined up on the anchor's side. The frame hangs from its
-- anchor, so growing taller moves its far edge: down from a top anchor, up from a bottom one.
local function PlaceLines()
	local horizontal = Sides(Anchor())
	local justify = horizontal ~= "" and horizontal or "CENTER"
	local x = horizontal == "LEFT" and PAD_X or (horizontal == "RIGHT" and -PAD_X or 0)
	for index, line in ipairs(lines) do
		line:ClearAllPoints()
		if index == 1 then
			line:SetPoint("TOP" .. horizontal, frame, "TOP" .. horizontal, x, -PAD_Y)
		else
			line:SetPoint("TOP" .. horizontal, lines[index - 1], "BOTTOM" .. horizontal, 0, -LINE_GAP)
		end
		line:SetJustifyH(justify)
		line.placed = true
	end
end

local function Update()
	Content()
	local content = table.concat(parts, "\n")
	if content == lastContent then
		return
	end
	lastContent = content
	local width, height = 0, 0
	local fontHeight = Utils.FontHeight("Overlay")
	for index = 1, #parts do
		local line = Line(index)
		if not line.placed then
			PlaceLines()
		end
		if line.text ~= parts[index] then
			line.text = parts[index]
			line:SetText(parts[index])
		end
		line:Show()
		width = max(width, line:GetStringWidth())
		height = height + max(fontHeight, line:GetStringHeight()) + (index > 1 and LINE_GAP or 0)
	end
	for index = #parts + 1, #lines do
		lines[index].text = nil
		lines[index]:Hide()
	end
	frame:SetSize(max(20, math.ceil(width) + PAD_X * 2), max(12, math.ceil(height) + PAD_Y * 2))
end

local function Position()
	local db = ns.db.overlay
	local point = Anchor()
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, db.x or 0, db.y or 0)
	local _, top = Sides(point)
	hint:ClearAllPoints()
	-- The hint goes on the side the stats grow towards, out of the way of the anchor.
	if top then
		hint:SetPoint("TOP", frame, "BOTTOM", 0, -3)
	else
		hint:SetPoint("BOTTOM", frame, "TOP", 0, 3)
	end
	PlaceLines()
end

-- After a drag: the anchor that matches where the stats were dropped, at that same spot.
local function Settle()
	local scale = frame:GetScale()
	local width, height = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (left and right and top and bottom) then
		return
	end
	local middle = (left + right) / 2
	local horizontal = middle < width / 3 and "LEFT" or (middle > width * 2 / 3 and "RIGHT" or "")
	local vertical = (top + bottom) / 2 > height / 2 and "TOP" or "BOTTOM"
	local db = ns.db.overlay
	db.point = vertical .. horizontal
	if horizontal == "LEFT" then
		db.x = left
	elseif horizontal == "RIGHT" then
		db.x = right - width
	else
		db.x = middle - width / 2
	end
	db.y = vertical == "TOP" and top - height or bottom
	Position()
end

local function Build()
	frame = CreateFrame("Frame", "LaggyAddonDetectorOverlay", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(50)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetSize(20, 12)
	back = Utils.Pixel(frame, "BACKGROUND", { 0, 0, 0 }, 0.45)
	back:SetAllPoints()
	border = Utils.Border(frame, C.dim)
	hint = Utils.FontString(frame, "Overlay")
	hint:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	hint:SetText(L["Drag to move · right-click to lock"])
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- The addon keeps the position, not the game's layout cache.
		self:SetUserPlaced(false)
		Settle()
	end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			O.Lock()
		end
	end)
	frame:SetScript("OnEnter", function(self)
		Utils.Tooltip(self, "ANCHOR_CURSOR", L["On-screen stats"], L["Drag them where you want them. They hang from the nearest top or bottom edge: from the top they grow down, from the bottom they grow up."], L["Right-click to lock them there. Locked, clicks go through them."])
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Shows, hides and lays out the stats as the settings say.
function O.Apply()
	local db = ns.db.overlay
	if not db.enabled then
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		if frame then
			frame:Hide()
		end
		return
	end
	if not frame then
		Build()
	end
	frame:SetScale(db.scale or 1)
	local moving = not db.lock
	back:SetShown(db.background or moving)
	for _, edge in ipairs(border) do
		edge:SetShown(moving)
	end
	hint:SetShown(moving)
	frame:EnableMouse(moving)
	Position()
	lastContent = nil
	Update()
	frame:Show()
	if ticker then
		ticker:Cancel()
	end
	ticker = C_Timer.NewTicker(db.rate or 1, Utils.Protect("on-screen stats", Update))
end

function O.Toggle()
	ns.db.overlay.enabled = not ns.db.overlay.enabled
	O.Apply()
	if ns.Settings then
		ns.Settings.Refresh()
	end
end

-- Unlocks the stats to be dragged (turning them on if they're off).
function O.Move()
	local db = ns.db.overlay
	db.enabled = true
	db.lock = false
	O.Apply()
	if ns.Settings then
		ns.Settings.Refresh()
	end
	Utils.Print(L["Drag the on-screen stats where you want them, then right-click them to lock."])
end

function O.Lock()
	ns.db.overlay.lock = true
	O.Apply()
	if ns.Settings then
		ns.Settings.Refresh()
	end
	Utils.Print(L["On-screen stats locked. /lad stats move to move them again."])
end

-- One of the anchors from the list, a little in from the screen's edge.
function O.SetAnchor(point)
	if not VALID_ANCHOR[point] then
		point = "TOPLEFT"
	end
	local db = ns.db.overlay
	db.point = point
	local horizontal, top = Sides(point)
	db.x = horizontal == "LEFT" and EDGE or (horizontal == "RIGHT" and -EDGE or 0)
	db.y = top and -EDGE or EDGE
	if frame then
		Position()
	end
end

function O.ResetPosition()
	O.SetAnchor("TOPLEFT")
end

function O.IsValidAnchor(point)
	return VALID_ANCHOR[point] == true
end

-- For the tests: the frame, its lines and the hint.
function O.Internals()
	return frame, lines, hint
end
