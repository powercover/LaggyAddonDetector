local addonName, ns = ...

local Utils = {}
ns.Utils = Utils

local L = ns.L
local format, floor, abs, max, min = string.format, math.floor, math.abs, math.max, math.min

Utils.TITLE = "Laggy Addon Detector"
Utils.ICON = "Interface\\AddOns\\LaggyAddonDetector\\Icon"

-- One neutral palette. The only signal colour is `warn`: a number over one of the player's
-- thresholds (and that can be turned off in the settings).
Utils.COLORS = {
	text = { 0.92, 0.92, 0.93 },
	dim = { 0.64, 0.64, 0.68 },
	faint = { 0.46, 0.46, 0.50 },
	warn = { 1.00, 0.76, 0.28 },
	heading = { 1.00, 0.82, 0.00 },
	body = { 0.055, 0.055, 0.065, 0.97 },
	band = { 0.085, 0.085, 0.097, 1 },
	cell = { 0.10, 0.10, 0.115, 1 },
	line = { 0.24, 0.24, 0.27, 1 },
	stripe = { 1, 1, 1, 0.025 },
	hover = { 1, 1, 1, 0.06 },
	select = { 1, 1, 1, 0.11 },
	bar = { 0.60, 0.60, 0.66, 0.45 },
}
local C = Utils.COLORS

-- --- secret values and safe calls ---------------------------------------------------------------

function Utils.IsSecret(value)
	if type(issecretvalue) ~= "function" then
		return false
	end
	-- a check that fails counts as secret: the value isn't safe to compare or do sums with
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret == true
end

-- `value` when it is a number that's safe to compare and do sums with, nil otherwise.
function Utils.Number(value)
	if type(value) == "number" and not Utils.IsSecret(value) then
		return value
	end
end

local function Answered(ok, first, ...)
	if not ok or Utils.IsSecret(first) then
		return
	end
	return first, ...
end

-- Calls a game function that may be missing, fail, or answer with a secret value: nothing comes back
-- then.
function Utils.Call(func, ...)
	if type(func) ~= "function" then
		return
	end
	return Answered(pcall(func, ...))
end

-- --- errors -------------------------------------------------------------------------------------

-- The last few errors the addon caught (Utils.Protect), each with how often it happened. /lad debug
-- lists them.
ns.errors = {}
local MAX_ERRORS = 10

function Utils.NoteError(label, err)
	local message = Utils.IsSecret(err) and "(secret value)" or tostring(err)
	for _, known in ipairs(ns.errors) do
		if known.message == message then
			known.count = known.count + 1
			return
		end
	end
	if #ns.errors >= MAX_ERRORS then
		table.remove(ns.errors, 1)
	end
	ns.errors[#ns.errors + 1] = { label = label, message = message, count = 1 }
	if ns.db and ns.db.debug then
		Utils.Print(label .. ": " .. message)
	end
end

local function Settled(label, ok, ...)
	if ok then
		return ...
	end
	Utils.NoteError(label, (...))
end

-- `fn` wrapped so an error in it is noted instead of reaching the game's error frame: a profiler
-- must never be the thing that breaks your UI.
function Utils.Protect(label, fn)
	return function(...)
		return Settled(label, pcall(fn, ...))
	end
end

-- --- messages between files ---------------------------------------------------------------------

local listeners = {}

function ns.On(message, fn)
	local list = listeners[message]
	if not list then
		list = {}
		listeners[message] = list
	end
	list[#list + 1] = fn
end

function ns.Fire(message, ...)
	local list = listeners[message]
	if list then
		for i = 1, #list do
			list[i](...)
		end
	end
end

-- --- text ---------------------------------------------------------------------------------------

function Utils.Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff" .. Utils.TITLE .. "|r: " .. tostring(message))
end

-- An indented follow-up line under Utils.Print.
function Utils.Line(message)
	DEFAULT_CHAT_FRAME:AddMessage("    " .. tostring(message))
end

function Utils.Trim(value)
	if type(value) ~= "string" then
		return ""
	end
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Text without colour codes, textures or atlases (addon titles often carry them).
function Utils.StripCodes(text)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return Utils.Trim(text)
end

function Utils.Hex(color)
	return format("ff%02x%02x%02x", floor(color[1] * 255 + 0.5), floor(color[2] * 255 + 0.5), floor(color[3] * 255 + 0.5))
end

function Utils.Paint(text, color)
	return "|c" .. Utils.Hex(color) .. text .. "|r"
end

-- CPU time: milliseconds with the precision that matters at that size.
function Utils.Ms(ms)
	ms = ms or 0
	if ms >= 100 then
		return format("%.0f ms", ms)
	elseif ms >= 10 then
		return format("%.1f ms", ms)
	end
	return format("%.2f ms", ms)
end

-- Memory from kilobytes.
function Utils.Memory(kb)
	kb = kb or 0
	if kb >= 1024 * 1024 then
		return format("%.2f GB", kb / (1024 * 1024))
	elseif kb >= 100 * 1024 then
		return format("%.0f MB", kb / 1024)
	elseif kb >= 1024 then
		return format("%.1f MB", kb / 1024)
	end
	return format("%.0f KB", kb)
end

-- Memory growth from kilobytes a second.
function Utils.Rate(kbps)
	kbps = kbps or 0
	if kbps >= 1024 then
		return format("+%.1f MB/s", kbps / 1024)
	elseif kbps >= 0.5 then
		return format("+%.0f KB/s", kbps)
	end
	return "0 KB/s"
end

function Utils.Percent(value)
	value = value or 0
	if value >= 10 then
		return format("%.0f%%", value)
	elseif value >= 0.1 then
		return format("%.1f%%", value)
	elseif value > 0 then
		return "<0.1%"
	end
	return "0%"
end

-- A duration: "45s", "2m 13s", "3h 2m".
function Utils.Duration(seconds)
	seconds = max(0, floor(seconds or 0))
	if seconds < 60 then
		return format(L["%ds"], seconds)
	elseif seconds < 3600 then
		return format(L["%dm %ds"], floor(seconds / 60), seconds % 60)
	end
	return format(L["%dh %dm"], floor(seconds / 3600), floor(seconds % 3600 / 60))
end

-- A moment (from time()): the clock today, the date and clock before that.
function Utils.Clock(epoch)
	if type(epoch) ~= "number" then
		return "?"
	end
	if date("%Y%m%d", epoch) == date("%Y%m%d") then
		return date("%H:%M:%S", epoch)
	end
	return date("%b %d %H:%M", epoch)
end

-- --- fonts --------------------------------------------------------------------------------------

-- The addon's fonts: Blizzard's, at their size plus the text size offset from the settings. Each is
-- a family with one font per alphabet, so addon titles in any script show (as Blizzard's do).
local FONT_TEMPLATES = {
	Highlight = { template = "GameFontHighlight" },
	Normal = { template = "GameFontNormal" },
	HighlightSmall = { template = "GameFontHighlightSmall" },
	NormalSmall = { template = "GameFontNormalSmall" },
	HighlightLarge = { template = "GameFontHighlightLarge" },
	Disable = { template = "GameFontDisableSmall" },
	-- The on-screen stats: outlined so they read over the world. It has its own size setting.
	Overlay = { template = "GameFontHighlight", flags = "OUTLINE", fixed = true },
}
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local fonts, fontMembers = {}, {}

function Utils.FontOffset()
	local value = ns.db and ns.db.fontSize
	if type(value) ~= "number" then
		return 0
	end
	return max(-3, min(5, floor(value + 0.5)))
end

local function TemplateMembers(template, flags)
	local members = {}
	for _, alphabet in ipairs(ALPHABETS) do
		local source = template
		if type(template.GetFontObjectForAlphabet) == "function" then
			source = template:GetFontObjectForAlphabet(alphabet) or template
		end
		local file, height, ownFlags
		if type(source.GetFont) == "function" then
			file, height, ownFlags = source:GetFont()
		end
		if file and height then
			members[#members + 1] = { alphabet = alphabet, file = file, height = height, flags = flags or ownFlags or "", source = source }
		end
	end
	return members
end

local function CreateAddonFont(key, spec)
	local template = _G[spec.template]
	if not template then
		return nil
	end
	local name = "LaggyAddonDetectorFont" .. key
	local members = TemplateMembers(template, spec.flags)
	if type(CreateFontFamily) == "function" and #members > 0 then
		local definition = {}
		for index, member in ipairs(members) do
			definition[index] = { alphabet = member.alphabet, file = member.file, height = member.height, flags = member.flags }
		end
		local ok, font = pcall(CreateFontFamily, name, definition)
		if ok and font then
			for _, member in ipairs(members) do
				local target = font:GetFontObjectForAlphabet(member.alphabet)
				if target then
					target:SetTextColor(member.source:GetTextColor())
					target:SetShadowColor(member.source:GetShadowColor())
					target:SetShadowOffset(member.source:GetShadowOffset())
				end
			end
			fontMembers[key] = members
			return font
		end
	end
	if type(CreateFont) ~= "function" then
		return nil
	end
	local font = CreateFont(name)
	font:CopyFontObject(template)
	local file, height, flags = font:GetFont()
	fontMembers[key] = { { file = file, height = height, flags = spec.flags or flags or "" } }
	return font
end

function Utils.Font(key)
	return fonts[key] or _G[FONT_TEMPLATES[key] and FONT_TEMPLATES[key].template or "GameFontHighlight"] or GameFontHighlight
end

function Utils.FontString(parent, key, layer)
	local text = parent:CreateFontString(nil, layer or "OVERLAY")
	text:SetFontObject(Utils.Font(key))
	text:SetWordWrap(false)
	return text
end

function Utils.ApplyFontSize()
	local offset = Utils.FontOffset()
	for key, spec in pairs(FONT_TEMPLATES) do
		local font = fonts[key]
		if not font then
			font = CreateAddonFont(key, spec)
			fonts[key] = font
		end
		for _, member in ipairs(font and fontMembers[key] or {}) do
			local target = font
			if member.alphabet and type(font.GetFontObjectForAlphabet) == "function" then
				target = font:GetFontObjectForAlphabet(member.alphabet) or font
			end
			target:SetFont(member.file, max(6, member.height + (spec.fixed and 0 or offset)), member.flags)
		end
	end
end

-- The height of one line of `key` text now, for laying rows out at any text size.
function Utils.FontHeight(key)
	local font = Utils.Font(key)
	local _, height = font:GetFont()
	return height or 12
end

-- --- flat widgets -------------------------------------------------------------------------------

function Utils.Pixel(parent, layer, color, alpha)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
	return texture
end

-- A 1px border around `target` (default `parent`), drawn on `parent`.
function Utils.Border(parent, color, target)
	target = target or parent
	local edges = {}
	local function Edge(from, to, horizontal)
		local line = Utils.Pixel(parent, "BORDER", color)
		line:SetPoint(from, target, from, 0, 0)
		line:SetPoint(to, target, to, 0, 0)
		if horizontal then
			line:SetHeight(1)
		else
			line:SetWidth(1)
		end
		edges[#edges + 1] = line
	end
	Edge("TOPLEFT", "TOPRIGHT", true)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
	Edge("TOPLEFT", "BOTTOMLEFT", false)
	Edge("TOPRIGHT", "BOTTOMRIGHT", false)
	return edges
end

-- A window body: a soft shadow, the dark fill and a 1px border.
function Utils.Panel(frame)
	for step, alpha in ipairs({ 0.22, 0.14, 0.07 }) do
		local shadow = Utils.Pixel(frame, "BACKGROUND", { 0, 0, 0 }, alpha)
		shadow:SetDrawLayer("BACKGROUND", -8)
		shadow:SetPoint("TOPLEFT", -2 * step, 2 * step)
		shadow:SetPoint("BOTTOMRIGHT", 2 * step, -2 * step)
	end
	local body = Utils.Pixel(frame, "BACKGROUND", C.body)
	body:SetDrawLayer("BACKGROUND", -7)
	body:SetAllPoints()
	Utils.Border(frame, C.line)
end

-- A flat button: dark fill, 1px border, a soft glow on hover. :SetText / :GetText / :GetFontString
-- work as on Blizzard's buttons.
function Utils.Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width or 100, height or 22)
	local back = Utils.Pixel(button, "BACKGROUND", C.cell)
	back:SetAllPoints()
	Utils.Border(button, C.line)
	local glow = Utils.Pixel(button, "HIGHLIGHT", { 1, 1, 1 }, 0.07)
	glow:SetAllPoints()
	local label = Utils.FontString(button, "HighlightSmall")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", -8, 0)
	label:SetJustifyH("CENTER")
	function button:SetText(value)
		label:SetText(value)
	end
	function button:GetText()
		return label:GetText()
	end
	function button:GetFontString()
		return label
	end
	-- Wide enough for its label, at least `minimum`.
	function button:FitWidth(minimum)
		self:SetWidth(max(minimum or 0, math.ceil(label:GetStringWidth() + 20)))
	end
	button:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			label:SetPoint("LEFT", 8, -1)
			label:SetPoint("RIGHT", -8, -1)
		end
	end)
	button:SetScript("OnMouseUp", function()
		label:SetPoint("LEFT", 8, 0)
		label:SetPoint("RIGHT", -8, 0)
	end)
	button:SetText(text or "")
	return button
end

-- A flat checkbox with its label: the box fills when on. `getter` / `setter` keep it in sync.
function Utils.Checkbox(parent, text, getter, setter)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(20)
	local box = Utils.Pixel(row, "BACKGROUND", C.cell)
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 0, 0)
	Utils.Border(row, C.line, box)
	local fill = Utils.Pixel(row, "ARTWORK", C.text)
	fill:SetSize(8, 8)
	fill:SetPoint("CENTER", box, "CENTER", 0, 0)
	local label = Utils.FontString(row, "HighlightSmall")
	label:SetPoint("LEFT", box, "RIGHT", 7, 0)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	row.label = label
	function row:Refresh()
		fill:SetShown(getter() and true or false)
		self:SetWidth(label:GetStringWidth() + 24)
	end
	row:SetScript("OnClick", function(self)
		setter(not getter())
		self:Refresh()
	end)
	row:Refresh()
	return row
end

-- A small × button.
function Utils.CloseButton(parent, size)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size or 20, size or 20)
	local lines = {}
	for _, angle in ipairs({ 45, -45 }) do
		local line = Utils.Pixel(button, "ARTWORK", C.dim)
		line:SetSize((size or 20) * 0.55, 1.5)
		line:SetPoint("CENTER")
		line:SetRotation(math.rad(angle))
		lines[#lines + 1] = line
	end
	local glow = Utils.Pixel(button, "HIGHLIGHT", { 1, 1, 1 }, 0.08)
	glow:SetAllPoints()
	return button
end

-- A dropdown-style menu at `anchor` (MenuUtil). Returns false when the client has none.
function Utils.Menu(anchor, build)
	if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
		return false
	end
	MenuUtil.CreateContextMenu(anchor, function(_, root)
		build(root)
	end)
	return true
end

-- A plain tooltip: a title and wrapped lines.
function Utils.Tooltip(owner, anchor, title, ...)
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, C.heading[1], C.heading[2], C.heading[3])
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line then
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

-- Puts `text` in the chat box: into the one being typed in, or a fresh one.
function Utils.InsertInChat(text)
	local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
	if type(insert) == "function" and insert(text) then
		return
	end
	local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
	if type(open) == "function" then
		open(text)
	end
end

-- --- addon list ---------------------------------------------------------------------------------

Utils.GetNumAddOns = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
Utils.GetAddOnInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
Utils.IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
Utils.IsAddOnLoadOnDemand = C_AddOns and C_AddOns.IsAddOnLoadOnDemand or IsAddOnLoadOnDemand
Utils.GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

function Utils.Metadata(name, field)
	local value = Utils.Call(Utils.GetAddOnMetadata, name, field)
	if type(value) == "string" then
		value = Utils.StripCodes(value)
		if value ~= "" then
			return value
		end
	end
end

Utils.ApplyFontSize()
