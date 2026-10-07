local addonName, ns = ...

-- The minimap button, its popup, the addon compartment entry and the data bar feed. The popup reads
-- the totals and the profiler's own top-5 ranking: a handful of calls a second, only while it shows.

local Utils, L, P, M, S = ns.Utils, ns.L, ns.Profiler, ns.Memory, ns.SpikeWatch
local C = Utils.COLORS
local Popup = {}
ns.Popup = Popup

local format = string.format
local TOP_COUNT = 5
local DEFAULT_ANGLE = 215

-- --- clicks -------------------------------------------------------------------------------------

function Popup.Click(button)
	if button == "RightButton" then
		ns.Settings.Open()
	elseif button == "MiddleButton" then
		ns.Overlay.Toggle()
	elseif IsShiftKeyDown() then
		ns.Report()
	else
		ns.Window.Toggle()
	end
end

-- --- the popup ----------------------------------------------------------------------------------

-- Fills `tooltip` (GameTooltip, or a data bar's) with the UI's cost right now.
function Popup.Fill(tooltip, showDrag)
	P.SampleTotals()
	M.SampleHeap()
	local t = P.totals
	tooltip:AddDoubleLine(Utils.TITLE, format(L["%.0f fps"], t.fps), C.heading[1], C.heading[2], C.heading[3], 1, 1, 1)
	if P.available then
		tooltip:AddLine(format(L["Addons: %s a frame, %s of frame time"], Utils.Ms(t.now), Utils.Percent(t.share)), C.text[1], C.text[2], C.text[3])
	else
		tooltip:AddLine(L["The game's addon profiler isn't answering, so there are no CPU figures."], C.dim[1], C.dim[2], C.dim[3], true)
	end
	tooltip:AddLine(format(L["Lua memory: %s, %s"], Utils.Memory(M.heap), M.heapKnown and Utils.Rate(M.heapGrowth) or L["measuring..."]), C.text[1], C.text[2], C.text[3])

	if P.available then
		local top = P.Top(TOP_COUNT)
		local warnOn = ns.db.warnColor
		local shown = 0
		for i = 1, #top do
			local entry = top[i]
			if entry.now >= 0.005 then
				if shown == 0 then
					tooltip:AddLine(" ")
					tooltip:AddLine(L["Busiest right now"], C.heading[1], C.heading[2], C.heading[3])
				end
				local color = (warnOn and entry.now >= ns.db.cpuWarn) and C.warn or C.text
				tooltip:AddDoubleLine(entry.title, Utils.Ms(entry.now), 1, 1, 1, color[1], color[2], color[3])
				shown = shown + 1
			end
		end

		tooltip:AddLine(" ")
		local slowColor = (warnOn and t.slow > 0) and C.warn or C.text
		tooltip:AddDoubleLine(format(L["Frames over %d ms, %s"], P.spikeMs, P.PeriodText()), tostring(t.slow),
			C.text[1], C.text[2], C.text[3], slowColor[1], slowColor[2], slowColor[3])
		local last = S.Latest()
		if last then
			tooltip:AddLine(format(L["Latest: %s, %s, %s"], S.Who(last), S.HowBad(last), Utils.Clock(last.t)), C.dim[1], C.dim[2], C.dim[3], true)
		end
	end

	tooltip:AddLine(" ")
	local faint = C.faint
	tooltip:AddLine(L["Click: window · Right-click: settings"], faint[1], faint[2], faint[3])
	tooltip:AddLine(L["Shift-click: report in chat · Middle-click: on-screen stats"], faint[1], faint[2], faint[3])
	if showDrag then
		tooltip:AddLine(L["Drag: move this button"], faint[1], faint[2], faint[3])
	end
end

-- GameTooltip at `owner`, refreshed every second while it's still the owner.
local refresher

local function ShowPopup(owner, showDrag)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:ClearLines()
	Popup.Fill(GameTooltip, showDrag)
	GameTooltip:Show()
	if refresher then
		refresher:Cancel()
	end
	refresher = C_Timer.NewTicker(1, Utils.Protect("popup", function()
		if GameTooltip:IsOwned(owner) and owner:IsVisible() then
			GameTooltip:ClearLines()
			Popup.Fill(GameTooltip, showDrag)
			GameTooltip:Show()
		else
			refresher:Cancel()
			refresher = nil
		end
	end))
end

local function HidePopup()
	if refresher then
		refresher:Cancel()
		refresher = nil
	end
	GameTooltip:Hide()
end

-- --- the minimap button -------------------------------------------------------------------------

local button

local function Place()
	local angle = math.rad(ns.db.minimap.angle or DEFAULT_ANGLE)
	local x, y = math.cos(angle), math.sin(angle)
	local radius = Minimap:GetWidth() / 2 + 5
	local px, py = x * radius, y * radius
	local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		-- Out to the square's edge rather than a circle inside it.
		local scale = 1 / math.max(math.abs(x), math.abs(y))
		px, py = x * radius * scale, y * radius * scale
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", px, py)
end

local function Build()
	button = CreateFrame("Button", "LaggyAddonDetectorMinimapButton", Minimap)
	button:SetSize(32, 32)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- The icon is round with its own rim, so it fills the button with no border around it.
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexture(Utils.ICON)
	button.icon = icon

	-- Pressed, the icon darkens a little.
	button:SetScript("OnMouseDown", function()
		icon:SetVertexColor(0.72, 0.72, 0.72)
	end)
	button:SetScript("OnMouseUp", function()
		icon:SetVertexColor(1, 1, 1)
	end)
	button:SetScript("OnClick", function(_, mouseButton)
		HidePopup()
		Popup.Click(mouseButton)
	end)
	button:SetScript("OnEnter", function(self)
		ShowPopup(self, not ns.db.minimap.lock)
	end)
	button:SetScript("OnLeave", HidePopup)

	local function Follow(self)
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		ns.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
		Place()
	end
	button:SetScript("OnDragStart", function(self)
		if ns.db.minimap.lock then
			return
		end
		HidePopup()
		self:LockHighlight()
		self:SetScript("OnUpdate", Follow)
	end)
	button:SetScript("OnDragStop", function(self)
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
	end)
end

-- Shows, hides and places the button as the settings say.
function Popup.Apply()
	if ns.db.minimap.show then
		if not button then
			Build()
		end
		Place()
		button:Show()
	elseif button then
		button:Hide()
	end
end

function Popup.ResetPosition()
	ns.db.minimap.angle = DEFAULT_ANGLE
	if button then
		Place()
	end
end

-- --- the addon compartment ----------------------------------------------------------------------

-- The game lists the addon in its compartment from the TOC; with the option off, the entry is taken
-- out of the menu's list (and put back when it's turned on again).
local compartmentEntry

function Popup.ApplyCompartment()
	local menu = AddonCompartmentFrame
	if not (menu and type(menu.registeredAddons) == "table") then
		return
	end
	local wanted = ns.db.compartment
	local title = Utils.Metadata(addonName, "Title")
	local index
	for i, data in ipairs(menu.registeredAddons) do
		if data == compartmentEntry or (type(data) == "table" and title and data.text == title) then
			index = i
			break
		end
	end
	if wanted and not index and compartmentEntry then
		table.insert(menu.registeredAddons, compartmentEntry)
	elseif not wanted and index then
		compartmentEntry = table.remove(menu.registeredAddons, index)
	else
		return
	end
	if type(menu.UpdateDisplay) == "function" then
		menu:UpdateDisplay()
	end
end

LaggyAddonDetector_OnCompartmentClick = Utils.Protect("compartment", function(_, mouseButton)
	HidePopup()
	Popup.Click(mouseButton)
end)

LaggyAddonDetector_OnCompartmentEnter = Utils.Protect("compartment", function(_, menuButton)
	if menuButton then
		ShowPopup(menuButton, false)
	end
end)

LaggyAddonDetector_OnCompartmentLeave = Utils.Protect("compartment", function()
	HidePopup()
end)

-- --- data bars (LibDataBroker) ------------------------------------------------------------------

-- A feed for data bar addons (ElvUI, Titan Panel, ChocolateBar...) when one of them has loaded
-- LibDataBroker. Nothing is bundled: without it, nothing runs.
local feed, feedTicker

local function UpdateFeed()
	P.SampleTotals()
	local t = P.totals
	if P.available then
		feed.text = format(L["%.0f fps  %s"], t.fps, Utils.Ms(t.now))
	else
		feed.text = format(L["%.0f fps"], t.fps)
	end
end

function Popup.ApplyBroker()
	local broker = LibStub and LibStub("LibDataBroker-1.1", true)
	if not broker then
		return
	end
	if ns.db.broker then
		if not feed then
			feed = broker:NewDataObject(addonName, {
				type = "data source",
				label = L["Addons"],
				text = "",
				icon = Utils.ICON,
				OnClick = function(_, mouseButton)
					Popup.Click(mouseButton)
				end,
				OnTooltipShow = function(tooltip)
					Popup.Fill(tooltip, false)
				end,
			})
		end
		if feed and not feedTicker then
			UpdateFeed()
			feedTicker = C_Timer.NewTicker(2, Utils.Protect("data bar feed", UpdateFeed))
		end
	elseif feedTicker then
		-- The feed can't be taken back from the bars until a reload; it just stops updating.
		feedTicker:Cancel()
		feedTicker = nil
		if feed then
			feed.text = L["off"]
		end
	end
end
