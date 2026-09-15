local addonName, ns = ...

ns.addonName = addonName
ns.rows = {}
ns.listeners = {}
ns.memoryCache = {}

local TICK_SECONDS = 2
local IDLE_CPU_SECONDS = 8
local MEMORY_SECONDS = 15

local DB_DEFAULTS = {
	minimapPos = 215,
	minimapHide = false,
	sortKey = "resources",
	sortAsc = false,
}

local Metric = (Enum and Enum.AddOnProfilerMetric) or {
	SessionAverageTime = 0,
	RecentAverageTime = 1,
	LastTime = 3,
	PeakTime = 4,
	CountTimeOver10Ms = 7,
	CountTimeOver50Ms = 8,
}

-- CPU is milliseconds per frame. Memory is kilobytes.
ns.thresholds = {
	cpuGreen = 0.40,
	cpuYellow = 1.50,
	memGreen = 10 * 1024,
	memYellow = 40 * 1024,
}

local GetNumAddOns = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
local GetAddOnInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

local function CopyDefaults(src, dst)
	if type(dst) ~= "table" then
		dst = {}
	end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns.HasProfiler()
	return C_AddOnProfiler and (not C_AddOnProfiler.IsEnabled or C_AddOnProfiler.IsEnabled())
end

function ns.HasCPUSampling()
	return ns.HasProfiler() or (UpdateAddOnCPUUsage and GetAddOnCPUUsage)
end

local function SafeMetric(name, metric)
	if not ns.HasProfiler() then
		return 0
	end
	local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, name, metric)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

local function AddonLoaded(index)
	local loaded = IsAddOnLoaded(index)
	return loaded and loaded ~= 0
end

local function StripColors(text)
	if not text then
		return ""
	end
	return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function ns.Severity(cpu, memory)
	local cpuLevel = (cpu >= ns.thresholds.cpuYellow and 3) or (cpu >= ns.thresholds.cpuGreen and 2) or 1
	local memLevel = (memory >= ns.thresholds.memYellow and 3) or (memory >= ns.thresholds.memGreen and 2) or 1
	local level = math.max(cpuLevel, memLevel)
	if level >= 3 then
		return "red"
	elseif level == 2 then
		return "yellow"
	end
	return "green"
end

function ns.SeverityColor(severity)
	if severity == "red" then
		return 1.00, 0.20, 0.20, "ffff3333"
	elseif severity == "yellow" then
		return 1.00, 0.82, 0.20, "ffffd133"
	end
	return 0.30, 0.90, 0.35, "ff4ce65a"
end

function ns.ColoredName(title, severity)
	local _, _, _, hex = ns.SeverityColor(severity)
	return "|c" .. hex .. title .. "|r"
end

function ns.FormatCPU(ms)
	if not ms or ms <= 0 then
		return "0.00 ms"
	end
	if ms >= 100 then
		return string.format("%.1f ms", ms)
	end
	return string.format("%.2f ms", ms)
end

function ns.FormatMemory(kb)
	if not kb or kb <= 0 then
		return "0 KB"
	end
	if kb >= 1024 then
		return string.format("%.2f MB", kb / 1024)
	end
	return string.format("%.0f KB", kb)
end

function ns.LoadLabel(severity)
	if severity == "red" then
		return "Heavy"
	elseif severity == "yellow" then
		return "Moderate"
	end
	return "Light"
end

function ns.Score(cpuRecent, memory, peak)
	return (cpuRecent * 100) + ((memory or 0) / 1024) * 2 + math.max((peak or 0) - 16, 0) * 0.25
end

function ns.RegisterListener(fn)
	ns.listeners[#ns.listeners + 1] = fn
end

function ns.Notify()
	for i = 1, #ns.listeners do
		ns.listeners[i]()
	end
end

function ns.EnsureDB()
	LaggyAddonDetectorDB = CopyDefaults(DB_DEFAULTS, LaggyAddonDetectorDB)
	ns.db = LaggyAddonDetectorDB
	return ns.db
end

function ns.IsUiActive()
	if ns.frame and ns.frame:IsShown() then
		return true
	end
	if ns.minimapButton and GameTooltip:IsOwned(ns.minimapButton) then
		return true
	end
	return false
end

local function InCombat()
	return InCombatLockdown and InCombatLockdown()
end

local function ShouldRefreshMemory(opts)
	if opts and opts.memory == false then
		return false
	end
	if InCombat() then
		return false
	end
	if opts and opts.memory == true then
		return true
	end
	if not (ns.frame and ns.frame:IsShown()) then
		return false
	end
	return not ns.lastMemUpdate or (GetTime() - ns.lastMemUpdate) >= MEMORY_SECONDS
end

local function CollectCPU(name, index, now)
	if ns.HasProfiler() then
		return SafeMetric(name, Metric.RecentAverageTime),
			SafeMetric(name, Metric.SessionAverageTime),
			SafeMetric(name, Metric.PeakTime)
	end

	if not (UpdateAddOnCPUUsage and GetAddOnCPUUsage) then
		return 0, 0, 0
	end

	local ok, total = pcall(GetAddOnCPUUsage, index)
	if not ok or type(total) ~= "number" then
		ok, total = pcall(GetAddOnCPUUsage, name)
	end
	if not ok or type(total) ~= "number" then
		return 0, 0, 0
	end

	ns.prevCPU = ns.prevCPU or {}
	local prev = ns.prevCPU[name]
	local fps = math.max(GetFramerate() or 60, 1)
	local recent = 0
	if prev and ns.prevCPUTime and now > ns.prevCPUTime then
		recent = ((total - prev) / (now - ns.prevCPUTime)) / fps
		if recent < 0 then
			recent = 0
		end
	end

	local session = 0
	if ns.sessionStart and now > ns.sessionStart then
		session = (total / (now - ns.sessionStart)) / fps
	end

	ns.prevCPU[name] = total
	return recent, session, 0
end

function ns.Collect(opts)
	opts = opts or {}
	local now = GetTime()
	if not ns.HasProfiler() and UpdateAddOnCPUUsage then
		pcall(UpdateAddOnCPUUsage)
	end

	local refreshMemory = ShouldRefreshMemory(opts)
	if refreshMemory and UpdateAddOnMemoryUsage then
		pcall(UpdateAddOnMemoryUsage)
		ns.lastMemUpdate = now
	end

	local rows = {}
	local count = GetNumAddOns() or 0
	for i = 1, count do
		local name, title, _, _, _, security = GetAddOnInfo(i)
		if name and security ~= "SECURE" and not name:find("^Blizzard_") and AddonLoaded(i) then
			title = StripColors(title or name)
			local cpuRecent, cpuSession, peak = CollectCPU(name, i, now)
			local memory = ns.memoryCache[name] or 0
			if refreshMemory and GetAddOnMemoryUsage then
				local ok, value = pcall(GetAddOnMemoryUsage, i)
				if ok and type(value) == "number" then
					memory = value
					ns.memoryCache[name] = value
				end
			end
			local severity = ns.Severity(cpuRecent, memory)
			rows[#rows + 1] = {
				index = i,
				name = name,
				title = title,
				titleLower = title:lower(),
				cpuRecent = cpuRecent,
				cpuSession = cpuSession,
				peak = peak,
				memory = memory,
				severity = severity,
				score = ns.Score(cpuRecent, memory, peak),
			}
		end
	end

	ns.prevCPUTime = now
	ns.rows = rows
	ns.lastCollect = now
	ns.Sort()
	ns.Notify()
	return ns.rows
end

function ns.Sort()
	local db = ns.db or DB_DEFAULTS
	local key = db.sortKey or "resources"
	local asc = db.sortAsc

	table.sort(ns.rows, function(a, b)
		local va, vb
		if key == "name" then
			va, vb = a.titleLower, b.titleLower
		elseif key == "cpu" then
			va, vb = a.cpuRecent, b.cpuRecent
		elseif key == "peak" then
			va, vb = a.peak, b.peak
		elseif key == "memory" then
			va, vb = a.memory, b.memory
		else
			va, vb = a.score, b.score
		end

		if va == vb then
			return a.titleLower < b.titleLower
		end
		if asc then
			return va < vb
		end
		return va > vb
	end)
end

function ns.GetHeavyAddons()
	local heavy = {}
	for i = 1, #ns.rows do
		if ns.rows[i].severity == "red" then
			heavy[#heavy + 1] = ns.rows[i]
		end
	end
	table.sort(heavy, function(a, b)
		return a.score > b.score
	end)
	return heavy
end

function ns.Counts()
	local red, yellow, green = 0, 0, 0
	for i = 1, #ns.rows do
		local severity = ns.rows[i].severity
		if severity == "red" then
			red = red + 1
		elseif severity == "yellow" then
			yellow = yellow + 1
		else
			green = green + 1
		end
	end
	return red, yellow, green
end

function ns.WorstSeverity()
	local red, yellow = ns.Counts()
	if red > 0 then
		return "red"
	elseif yellow > 0 then
		return "yellow"
	end
	return "green"
end

function ns.PrintSummary(reason)
	local red, yellow, green = ns.Counts()
	local prefix = "|cff33ccffLaggy Addon Detector|r"
	reason = reason or "after login/reload"
	print(string.format("%s scanned %d loaded addons %s.", prefix, #ns.rows, reason))

	local heavy = ns.GetHeavyAddons()
	if #heavy == 0 then
		print("|cff4ce65aNo addons are draining CPU or memory right now.|r")
	else
		print(string.format("|cffff3333%d heavy addon%s:|r", #heavy, #heavy == 1 and "" or "s"))
		local limit = math.min(#heavy, 8)
		for i = 1, limit do
			local row = heavy[i]
			print(string.format("  %s  %s CPU, %s",
				ns.ColoredName(row.title, "red"),
				ns.FormatCPU(row.cpuRecent),
				ns.FormatMemory(row.memory)))
		end
		if #heavy > limit then
			print(string.format("  |cffaaaaaa...and %d more. Click the minimap button for the full table.|r", #heavy - limit))
		end
	end

	print(string.format("|cffffd133%d moderate|r, |cff4ce65a%d light|r. Click the minimap clock to inspect all addons.", yellow, green))
end

function ns.ShowHeavyTooltip(owner)
	if not owner then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine("Laggy Addon Detector", 1, 0.85, 0.2)
	GameTooltip:AddLine("Click to open the live usage table.", 0.75, 0.75, 0.75)
	GameTooltip:AddLine("Drag to move this button.", 0.55, 0.55, 0.55)
	GameTooltip:AddLine(" ")

	local heavy = ns.GetHeavyAddons()
	if #heavy == 0 then
		GameTooltip:AddLine("No addons are draining resources.", 0.30, 0.90, 0.35)
	else
		GameTooltip:AddLine("Addons draining resources:", 1.00, 0.20, 0.20)
		local limit = math.min(#heavy, 12)
		for i = 1, limit do
			local row = heavy[i]
			GameTooltip:AddDoubleLine(
				ns.ColoredName(row.title, "red"),
				ns.FormatCPU(row.cpuRecent) .. "  " .. ns.FormatMemory(row.memory),
				1.00, 0.20, 0.20,
				1.00, 0.55, 0.55
			)
		end
		if #heavy > limit then
			GameTooltip:AddLine(string.format("...and %d more", #heavy - limit), 0.7, 0.7, 0.7)
		end
	end
	GameTooltip:Show()
end

local function StartTicker()
	if ns.ticker then
		return
	end
	ns.ticker = C_Timer.NewTicker(TICK_SECONDS, function()
		if ns.frame and ns.frame:IsShown() then
			ns.Collect()
			return
		end
		if ns.IsUiActive() then
			ns.Collect({ memory = false })
			return
		end
		if not ns.lastCollect or (GetTime() - ns.lastCollect) >= IDLE_CPU_SECONDS then
			ns.Collect({ memory = false })
		end
	end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		ns.EnsureDB()
		ns.sessionStart = GetTime()
		if not ns.HasProfiler() and GetCVar and GetCVar("scriptProfile") ~= "1" then
			ns.needScriptProfile = true
		end
	elseif event == "PLAYER_LOGIN" then
		ns.EnsureDB()
		ns.sessionStart = ns.sessionStart or GetTime()
		if ns.CreateMinimapButton then
			ns.CreateMinimapButton()
		end
		StartTicker()
		C_Timer.After(2, function()
			ns.Collect({ memory = false })
		end)
		C_Timer.After(8, function()
			ns.Collect({ memory = true })
			ns.PrintSummary("after login/reload")
			if ns.needScriptProfile then
				print("|cff33ccffLaggy Addon Detector|r: CPU timings need |cffffd133/console scriptProfile 1|r then a reload on this client. Memory tracking is already live.")
			end
		end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(3, function()
			if ns.lastCollect and (GetTime() - ns.lastCollect) < 10 then
				return
			end
			ns.Collect({ memory = false })
		end)
	end
end)

SLASH_LAGGYADDONDETECTOR1 = "/lad"
SLASH_LAGGYADDONDETECTOR2 = "/laggy"
SLASH_LAGGYADDONDETECTOR3 = "/laggydetector"
SlashCmdList.LAGGYADDONDETECTOR = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "report" or msg == "scan" then
		ns.Collect({ memory = true })
		ns.PrintSummary("on demand")
		return
	end
	if ns.ToggleFrame then
		ns.ToggleFrame()
	end
end

function LaggyAddonDetector_OnCompartmentClick()
	if ns.ToggleFrame then
		ns.ToggleFrame()
	end
end

function LaggyAddonDetector_OnCompartmentEnter(addon, menuButton)
	ns.Collect({ memory = false })
	ns.ShowHeavyTooltip(menuButton or addon)
end

function LaggyAddonDetector_OnCompartmentLeave()
	GameTooltip:Hide()
end
