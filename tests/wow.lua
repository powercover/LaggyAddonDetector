-- A small model of the game's API: enough to load the addon's files and drive them. Widgets know
-- only the methods the game has (an unknown one is an error, so a typo shows up here), and keep the
-- state the addon reads back: sizes, text, shown, scripts.

local WOW = {}
_G.WOW = WOW

WOW.now = 1000
WOW.epoch = 1760000000
WOW.chat = {}
WOW.inCombat = false
WOW.shift = false
WOW.reloads = 0

function GetTime()
	return WOW.now
end

function time()
	return WOW.epoch + math.floor(WOW.now - 1000)
end

date = os.date

function debugprofilestop()
	return os.clock() * 1000
end

function table.wipe(t)
	for key in pairs(t) do
		t[key] = nil
	end
	return t
end
wipe = table.wipe
tinsert = table.insert
strtrim = function(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- --- timers -------------------------------------------------------------------------------------

local timers = {}

C_Timer = {}

function C_Timer.After(seconds, fn)
	timers[#timers + 1] = { at = WOW.now + seconds, fn = fn }
end

function C_Timer.NewTicker(seconds, fn)
	local ticker = { at = WOW.now + seconds, fn = fn, every = seconds }
	function ticker:Cancel()
		self.cancelled = true
	end
	function ticker:IsCancelled()
		return self.cancelled == true
	end
	timers[#timers + 1] = ticker
	return ticker
end

-- Moves the clock forward, running every timer that comes due, in order.
function WOW.Advance(seconds)
	local target = WOW.now + seconds
	while true do
		local nextTimer, nextIndex
		for index, timer in ipairs(timers) do
			if not timer.cancelled and timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then
				nextTimer, nextIndex = timer, index
			end
		end
		if not nextTimer then
			break
		end
		WOW.now = math.max(WOW.now, nextTimer.at)
		if nextTimer.every then
			nextTimer.at = nextTimer.at + nextTimer.every
		else
			table.remove(timers, nextIndex)
		end
		nextTimer.fn(nextTimer)
	end
	WOW.now = target
	for index = #timers, 1, -1 do
		if timers[index].cancelled then
			table.remove(timers, index)
		end
	end
end

function WOW.ActiveTickers()
	local count = 0
	for _, timer in ipairs(timers) do
		if timer.every and not timer.cancelled then
			count = count + 1
		end
	end
	return count
end

-- --- fonts --------------------------------------------------------------------------------------

local Font = {}
Font.__index = Font

local function NewFont(name, file, height, flags)
	local font = setmetatable({ name = name, file = file or "Fonts\\FRIZQT__.TTF", height = height or 12, flags = flags or "" }, Font)
	if name then
		_G[name] = font
	end
	return font
end

function Font:GetFont()
	return self.file, self.height, self.flags
end
function Font:SetFont(file, height, flags)
	self.file, self.height, self.flags = file, height, flags
end
function Font:GetFontObjectForAlphabet()
	return self
end
function Font:SetTextColor() end
function Font:GetTextColor()
	return 1, 1, 1, 1
end
function Font:SetShadowColor() end
function Font:GetShadowColor()
	return 0, 0, 0, 1
end
function Font:SetShadowOffset() end
function Font:GetShadowOffset()
	return 1, -1
end
function Font:CopyFontObject(other)
	self.file, self.height, self.flags = other.file, other.height, other.flags
end

for name, height in pairs({
	GameFontHighlight = 12, GameFontNormal = 12, GameFontHighlightSmall = 10, GameFontNormalSmall = 10,
	GameFontHighlightLarge = 16, GameFontDisableSmall = 10, GameFontDisable = 12,
}) do
	NewFont(name, nil, height)
end

function CreateFontFamily(name, definition)
	return NewFont(name, definition[1].file, definition[1].height, definition[1].flags)
end

function CreateFont(name)
	return NewFont(name)
end

-- --- widgets ------------------------------------------------------------------------------------

local Widget = {}
local WidgetMeta = { __index = Widget }
WOW.Widget = Widget

local function NewWidget(kind, name, parent)
	local widget = setmetatable({
		kind = kind, name = name, parent = parent, shown = true, width = 0, height = 0, alpha = 1, scale = 1,
		scripts = {}, points = {}, text = nil, value = 0, min = 0, max = 0, children = {},
	}, WidgetMeta)
	if parent and parent.children then
		parent.children[#parent.children + 1] = widget
	end
	if name then
		_G[name] = widget
	end
	return widget
end
WOW.NewWidget = NewWidget

function Widget:GetObjectType()
	return self.kind
end
function Widget:IsObjectType(kind)
	return self.kind == kind or (kind == "Frame" and self.kind ~= "Texture" and self.kind ~= "FontString")
end
function Widget:GetName()
	return self.name
end
function Widget:GetParent()
	return self.parent
end
function Widget:SetParent(parent)
	self.parent = parent
end

function Widget:SetSize(width, height)
	self.width, self.height = width, height
	self:Fire("OnSizeChanged", width, height)
end
function Widget:SetWidth(width)
	self.width = width
end
function Widget:SetHeight(height)
	self.height = height
end
function Widget:GetWidth()
	return self.width
end
function Widget:GetHeight()
	return self.height
end
function Widget:GetSize()
	return self.width, self.height
end
function Widget:SetPoint(point, relative, relativePoint, x, y)
	if type(relative) == "number" then
		relative, relativePoint, x, y = nil, point, relative, relativePoint
	end
	self.points[#self.points + 1] = { point, relative, relativePoint or point, x or 0, y or 0 }
end
function Widget:ClearAllPoints()
	self.points = {}
end
function Widget:SetAllPoints()
	self.points = { { "ALL" } }
end
function Widget:GetPoint(index)
	local p = self.points[index or 1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
end
function Widget:GetLeft()
	return self.left or 100
end
function Widget:GetRight()
	return (self.left or 100) + self.width
end
function Widget:GetTop()
	return self.top or 700
end
function Widget:GetBottom()
	return (self.top or 700) - self.height
end
function Widget:GetCenter()
	return (self.left or 100) + self.width / 2, (self.top or 700) - self.height / 2
end

function Widget:Fire(script, ...)
	local fn = self.scripts[script]
	if fn then
		return fn(self, ...)
	end
end
function Widget:Show()
	if not self.shown then
		self.shown = true
		self:Fire("OnShow")
	end
end
function Widget:Hide()
	if self.shown then
		self.shown = false
		self:Fire("OnHide")
	end
end
function Widget:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end
function Widget:IsShown()
	return self.shown
end
function Widget:IsVisible()
	local widget = self
	while widget do
		if not widget.shown then
			return false
		end
		widget = widget.parent
	end
	return true
end
function Widget:SetAlpha(alpha)
	self.alpha = alpha
end
function Widget:GetAlpha()
	return self.alpha
end
function Widget:SetScale(scale)
	self.scale = scale
end
function Widget:GetScale()
	return self.scale
end
function Widget:GetEffectiveScale()
	return self.scale
end

function Widget:SetScript(script, fn)
	self.scripts[script] = fn
end
function Widget:GetScript(script)
	return self.scripts[script]
end
function Widget:HookScript(script, fn)
	local previous = self.scripts[script]
	self.scripts[script] = function(...)
		if previous then
			previous(...)
		end
		fn(...)
	end
end

local noops = {
	"EnableMouse", "EnableMouseWheel", "RegisterForClicks", "RegisterForDrag", "SetMovable", "SetResizable",
	"SetResizeBounds", "SetClampedToScreen", "SetToplevel", "SetFrameStrata", "SetFrameLevel", "StartMoving",
	"StopMovingOrSizing", "StartSizing", "LockHighlight", "UnlockHighlight", "SetHighlightTexture",
	"SetNormalTexture", "SetPushedTexture", "SetTexture", "SetVertexColor", "SetColorTexture", "SetTexCoord",
	"SetDrawLayer", "SetRotation", "SetBlendMode", "SetAtlas", "SetJustifyH", "SetJustifyV", "SetWordWrap",
	"SetMaxLines", "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetOrientation", "SetValueStep",
	"SetObeyStepOnDrag", "SetThumbTexture", "SetScrollChild", "SetFont", "SetUserPlaced",
}
for _, method in ipairs(noops) do
	Widget[method] = function() end
end

function Widget:IsEnabled()
	return true
end

function Widget:CreateTexture()
	return NewWidget("Texture", nil, self)
end
function Widget:CreateFontString()
	return NewWidget("FontString", nil, self)
end

function Widget:SetFontObject(font)
	assert(font, "SetFontObject without a font")
	self.font = font
end
function Widget:GetFont()
	local font = self.font or GameFontHighlight
	return font:GetFont()
end
function Widget:SetText(text)
	if text ~= nil then
		assert(type(text) == "string" or type(text) == "number", "SetText with a " .. type(text))
	end
	local changed = self.text ~= text
	self.text = text
	if self.kind == "EditBox" and changed then
		self:Fire("OnTextChanged", true)
	end
end
function Widget:GetText()
	return self.text
end
function Widget:SetTextColor(r, g, b)
	self.color = { r, g, b }
end
function Widget:GetStringWidth()
	return #(self.text or "") * 6
end
function Widget:GetStringHeight()
	local lines = 1
	for _ in (self.text or ""):gmatch("\n") do
		lines = lines + 1
	end
	return lines * 12
end

function Widget:HasFocus()
	return self.focus == true
end
function Widget:SetFocus()
	self.focus = true
	self:Fire("OnEditFocusGained")
end
function Widget:ClearFocus()
	if self.focus then
		self.focus = false
		self:Fire("OnEditFocusLost")
	end
end

function Widget:SetMinMaxValues(low, high)
	self.min, self.max = low, high
end
function Widget:GetMinMaxValues()
	return self.min, self.max
end
function Widget:SetValue(value)
	value = math.max(self.min, math.min(self.max, value))
	local changed = self.value ~= value
	self.value = value
	if changed then
		self:Fire("OnValueChanged", value, true)
	end
end
function Widget:GetValue()
	return self.value
end
function Widget:SetVerticalScroll(value)
	self.scroll = value
end
function Widget:GetVerticalScroll()
	return self.scroll or 0
end

local eventFrames = {}

function Widget:RegisterEvent(event)
	eventFrames[event] = eventFrames[event] or {}
	eventFrames[event][self] = true
end
function Widget:UnregisterEvent(event)
	if eventFrames[event] then
		eventFrames[event][self] = nil
	end
end

function WOW.Fire(event, ...)
	for frame in pairs(eventFrames[event] or {}) do
		frame:Fire("OnEvent", event, ...)
	end
end

-- Clicks a button as the game would.
function WOW.Click(button, mouseButton)
	assert(button.scripts.OnClick, "no OnClick")
	button:Fire("OnClick", mouseButton or "LeftButton", false)
end

function CreateFrame(kind, name, parent)
	local widget = NewWidget(kind, name, parent)
	if kind ~= "GameTooltip" then
		widget.shown = true
	end
	return widget
end

UIParent = NewWidget("Frame", "UIParent")
UIParent.width, UIParent.height = 1920, 1080
Minimap = NewWidget("Frame", "Minimap", UIParent)
Minimap.width, Minimap.height = 140, 140
UISpecialFrames = {}
SlashCmdList = {}

-- --- tooltip and chat ---------------------------------------------------------------------------

GameTooltip = NewWidget("GameTooltip", "GameTooltip", UIParent)
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner)
	self.owner = owner
	self.lines = {}
end
function GameTooltip:ClearLines()
	self.lines = {}
end
function GameTooltip:AddLine(text)
	assert(type(text) == "string", "AddLine with a " .. type(text))
	self.lines[#self.lines + 1] = text
end
function GameTooltip:AddDoubleLine(left, right)
	assert(type(left) == "string" and type(right) == "string", "AddDoubleLine needs two strings")
	self.lines[#self.lines + 1] = left .. " | " .. right
end
function GameTooltip:IsOwned(owner)
	return self.owner == owner and self.shown
end
function GameTooltip:NumLines()
	return #self.lines
end
function GameTooltip_Hide()
	GameTooltip:Hide()
end

DEFAULT_CHAT_FRAME = {
	AddMessage = function(_, text)
		WOW.chat[#WOW.chat + 1] = text
	end,
}

function WOW.ChatContains(pattern)
	for _, line in ipairs(WOW.chat) do
		if line:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

-- --- addons and the profiler --------------------------------------------------------------------

WOW.addons = {
	{ name = "LaggyAddonDetector", title = "Laggy Addon Detector", version = "2.0.0", author = "powercover" },
	{ name = "Plater", title = "|cff00ff00Plater|r Nameplates", version = "5.18", author = "Tercioo", notes = "Nameplates" },
	{ name = "WeakAuras", title = "WeakAuras |TInterface\\Icon:16|t", version = "5.19" },
	{ name = "Details", title = "Details! Damage Meter" },
	{ name = "BigWigs", title = "BigWigs" },
	{ name = "AllTheThings", title = "All The Things" },
	{ name = "Blizzard_Foo", title = "Blizzard Foo", security = "SECURE" },
	{ name = "NotLoaded", title = "Not loaded", loaded = false },
	{ name = "LateLoad", title = "Late Loader", loaded = false, lod = true },
}
WOW.metrics = {}
WOW.overall = {}
WOW.memory = {}
WOW.app = 8.3

Enum = {
	AddOnProfilerMetric = {
		SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4,
		CountTimeOver1Ms = 5, CountTimeOver5Ms = 6, CountTimeOver10Ms = 7, CountTimeOver50Ms = 8,
		CountTimeOver100Ms = 9, CountTimeOver500Ms = 10, CountTimeOver1000Ms = 11,
	},
}
local Metric = Enum.AddOnProfilerMetric

local function Find(indexOrName)
	if type(indexOrName) == "number" then
		return WOW.addons[indexOrName]
	end
	for _, addon in ipairs(WOW.addons) do
		if addon.name == indexOrName then
			return addon
		end
	end
end

function WOW.SetMetric(name, metric, value)
	WOW.metrics[name] = WOW.metrics[name] or {}
	WOW.metrics[name][metric] = value
end

function WOW.AddMetric(name, metric, delta)
	WOW.SetMetric(name, metric, ((WOW.metrics[name] or {})[metric] or 0) + delta)
end

function WOW.AddOverall(metric, delta)
	WOW.overall[metric] = (WOW.overall[metric] or 0) + delta
end

C_AddOns = {}
function C_AddOns.GetNumAddOns()
	return #WOW.addons
end
function C_AddOns.GetAddOnInfo(indexOrName)
	local addon = Find(indexOrName)
	if not addon then
		return nil
	end
	return addon.name, addon.title, addon.notes or "", true, nil, addon.security or "INSECURE"
end
function C_AddOns.IsAddOnLoaded(indexOrName)
	local addon = Find(indexOrName)
	local loaded = addon and addon.loaded ~= false
	return loaded, loaded
end
function C_AddOns.IsAddOnLoadOnDemand(indexOrName)
	local addon = Find(indexOrName)
	return addon and addon.lod == true or false
end
function C_AddOns.GetAddOnMetadata(name, field)
	local addon = Find(name)
	if not addon then
		return nil
	end
	if field == "Version" then
		return addon.version
	elseif field == "Author" then
		return addon.author
	elseif field == "Title" then
		return addon.title
	end
end
WOW.enableState = {}
function C_AddOns.GetAddOnEnableState(name, character)
	assert(type(name) == "string" and type(character) == "string", "GetAddOnEnableState(name, character)")
	return WOW.enableState[name] or 2
end
function C_AddOns.DisableAddOn(name, character)
	assert(type(character) == "string")
	WOW.enableState[name] = 0
end
function C_AddOns.EnableAddOn(name, character)
	assert(type(character) == "string")
	WOW.enableState[name] = 2
end

C_AddOnProfiler = {}
WOW.profilerOn = true
function C_AddOnProfiler.IsEnabled()
	return WOW.profilerOn
end
function C_AddOnProfiler.GetAddOnMetric(name, metric)
	assert(type(name) == "string" and type(metric) == "number", "GetAddOnMetric(name, metric)")
	local addon = Find(name)
	if not addon or addon.security == "SECURE" then
		error("Blizzard addons can't be queried")
	end
	return (WOW.metrics[name] or {})[metric] or 0
end
function C_AddOnProfiler.GetOverallMetric(metric)
	if WOW.overall[metric] then
		return WOW.overall[metric]
	end
	local sum = 0
	for _, values in pairs(WOW.metrics) do
		sum = sum + (values[metric] or 0)
	end
	return sum
end
function C_AddOnProfiler.GetApplicationMetric(metric)
	return WOW.app
end
WOW.topCalls = 0
function C_AddOnProfiler.GetTopKAddOnsForMetric(metric, k)
	WOW.topCalls = WOW.topCalls + 1
	local results = {}
	for name, values in pairs(WOW.metrics) do
		results[#results + 1] = { addOnName = name, metricValue = values[metric] or 0 }
	end
	table.sort(results, function(a, b)
		return a.metricValue > b.metricValue
	end)
	for i = #results, k + 1, -1 do
		results[i] = nil
	end
	return results
end

WOW.memoryScans = 0
function UpdateAddOnMemoryUsage()
	assert(not WOW.inCombat, "memory scanned in combat")
	WOW.memoryScans = WOW.memoryScans + 1
end
function GetAddOnMemoryUsage(name)
	return WOW.memory[name] or 0
end

-- --- the rest -----------------------------------------------------------------------------------

function GetFramerate()
	return 120
end
function GetNetStats()
	return 0, 0, 24, 31
end
function InCombatLockdown()
	return WOW.inCombat
end
function IsShiftKeyDown()
	return WOW.shift
end
function GetCursorPosition()
	return 0, 0
end
function UnitName()
	return "Tester"
end
function GetLocale()
	return "enUS"
end
function GetMinimapShape()
	return "ROUND"
end
function GetInstanceInfo()
	return WOW.instance or "Dornogal", WOW.instanceType or "none", WOW.difficulty or 0, WOW.difficultyName or ""
end
function GetRealZoneText()
	return "Dornogal"
end
C_ChallengeMode = {
	GetActiveKeystoneInfo = function()
		return WOW.keystone or 0
	end,
}
function ReloadUI()
	WOW.reloads = WOW.reloads + 1
end
StaticPopupDialogs = {}
function StaticPopup_Show(which, arg)
	WOW.popup = { which = which, arg = arg }
end
function HideUIPanel(frame)
	frame:Hide()
end
function ChatEdit_InsertLink(text)
	WOW.inserted = text
	return true
end

AddonCompartmentFrame = {
	registeredAddons = { { text = "Laggy Addon Detector" }, { text = "Other" } },
	UpdateDisplay = function() end,
}

SettingsPanel = NewWidget("Frame", "SettingsPanel", UIParent)
SettingsPanel.shown = false
Settings = {}
local categories = {}
function Settings.RegisterCanvasLayoutCategory(frame, name)
	local category = { frame = frame, name = name, id = #categories + 1 }
	function category:GetID()
		return self.id
	end
	categories[#categories + 1] = category
	frame.parent = SettingsPanel
	frame.width, frame.height = 640, 560
	return category
end
function Settings.RegisterAddOnCategory() end
function Settings.OpenToCategory(id)
	SettingsPanel:Show()
	categories[id].frame:Show()
end

-- A menu: records what's built so a test can pick an entry.
MenuUtil = {}
WOW.menu = nil
function MenuUtil.CreateContextMenu(owner, generator)
	local menu = { entries = {} }
	local root = {}
	local function Entry(kind, text, a, b)
		local entry = { kind = kind, text = text, a = a, b = b }
		function entry.SetEnabled() end
		menu.entries[#menu.entries + 1] = entry
		return entry
	end
	function root:CreateTitle(text)
		return Entry("title", text)
	end
	function root:CreateButton(text, onClick)
		return Entry("button", text, onClick)
	end
	function root:CreateRadio(text, isSelected, onSelect)
		return Entry("radio", text, isSelected, onSelect)
	end
	function root:CreateCheckbox(text, isSelected, onSelect)
		return Entry("checkbox", text, isSelected, onSelect)
	end
	function root:CreateDivider()
		return Entry("divider")
	end
	generator(owner, root)
	WOW.menu = menu
	return menu
end

-- Picks the menu entry whose text contains `text`.
function WOW.Pick(text)
	for _, entry in ipairs(WOW.menu.entries) do
		if entry.text and entry.text:find(text, 1, true) then
			if entry.kind == "button" then
				entry.a()
			else
				entry.b()
			end
			return entry
		end
	end
	error("no menu entry " .. text)
end

-- LibDataBroker, as a data bar addon would bring it.
local broker = { objects = {} }
function broker:NewDataObject(name, object)
	self.objects[name] = object
	return object
end
WOW.broker = broker
function LibStub(name)
	if name == "LibDataBroker-1.1" then
		return broker
	end
end

-- Loads the addon's files in TOC order, as the game does.
function WOW.LoadAddon(root)
	local ns = {}
	local toc = assert(io.open(root .. "/LaggyAddonDetector.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:find("^##") and line:find("%.lua$") then
			local path = root .. "/" .. line:gsub("\\", "/")
			local source = assert(io.open(path)):read("*a")
			local chunk = assert(loadstring(source, "@" .. line))
			chunk("LaggyAddonDetector", ns)
		end
	end
	return ns
end
