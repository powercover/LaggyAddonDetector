local addonName, ns = ...

-- Saved settings, game events, chat commands, key bindings and the chat reports.

local Utils, L, P, M, S = ns.Utils, ns.L, ns.Profiler, ns.Memory, ns.SpikeWatch
local format = string.format

-- The login report looks at steady play only. Addons get this many seconds after the loading screen
-- for their start-up work (slow frames in them still show in the table, not in the report)...
local LOGIN_SETTLE = 8
-- ...then their CPU is read at these moments (seconds after the loading screen) and averaged, so a
-- brief burst doesn't count as busy. The report follows the last reading.
local LOGIN_READINGS = { 11, 15, 19, 23 }
-- If the loading screen never says it ended, the login period starts this long after entering the
-- world anyway.
local LOGIN_FALLBACK = 10

local DEFAULTS = {
	version = 2,
	refreshRate = 1,
	memoryInterval = 10,
	spikeMs = 50,
	cpuWarn = 1.0,
	growthWarn = 300,
	warnColor = true,
	sortKey = "now",
	sortAsc = false,
	onlyProblems = false,
	columns = {
		now = true, share = true, avg = true, boss = false, last = false,
		peak = true, slow = true, memory = true, growth = true,
	},
	window = {},
	spikeWatch = true,
	spikeSkipLoading = true,
	spikeChat = false,
	spikeKeep = 200,
	spikeLog = {},
	loginReport = "problems",
	overlay = {
		enabled = false, lock = true, background = true, layout = "stacked",
		point = "TOPLEFT", x = 6, y = -6, scale = 1, rate = 1,
		items = { fps = true, frametime = false, latency = true, addons = true, top = false, memory = false, slow = true },
	},
	minimap = { show = true, lock = false, angle = 215 },
	compartment = true,
	broker = true,
	fontSize = 0,
	debug = false,
}

local SORT_KEYS = { name = true, now = true, share = true, avg = true, boss = true, last = true, peak = true, slow = true, memory = true, growth = true }

local function CopyDefaults(target, defaults)
	if type(target) ~= "table" then
		target = {}
	end
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			target[key] = CopyDefaults(target[key], value)
		elseif target[key] == nil or type(target[key]) ~= type(value) then
			target[key] = value
		end
	end
	return target
end

-- 1.x kept the minimap angle, its hidden state and a sort key of its own.
local function Migrate(db)
	if db.version then
		return
	end
	db.minimap = type(db.minimap) == "table" and db.minimap or {}
	if type(db.minimapPos) == "number" then
		db.minimap.angle = db.minimapPos
	end
	if db.minimapHide then
		db.minimap.show = false
	end
	local sortKeys = { resources = "now", cpu = "now", peak = "peak", memory = "memory", name = "name" }
	db.sortKey = sortKeys[db.sortKey] or "now"
	db.minimapPos, db.minimapHide = nil, nil
	db.version = 2
end

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function SetupDB()
	local db = type(LaggyAddonDetectorDB) == "table" and LaggyAddonDetectorDB or {}
	Migrate(db)
	db = CopyDefaults(db, DEFAULTS)
	if not SORT_KEYS[db.sortKey] then
		db.sortKey = "now"
	end
	if not P.COUNT[db.spikeMs] or db.spikeMs == 1 or db.spikeMs == 5 or db.spikeMs == 1000 then
		db.spikeMs = 50
	end
	db.cpuWarn = Clamp(db.cpuWarn, 0.1, 5)
	db.growthWarn = Clamp(db.growthWarn, 50, 2000)
	db.refreshRate = Clamp(db.refreshRate, 0.5, 5)
	db.spikeKeep = Clamp(db.spikeKeep, 50, 500)
	db.overlay.scale = Clamp(db.overlay.scale, 0.6, 2)
	db.overlay.rate = Clamp(db.overlay.rate, 0.5, 2)
	if not ns.Overlay.IsValidAnchor(db.overlay.point) then
		db.overlay.point, db.overlay.x, db.overlay.y = "TOPLEFT", 6, -6
	end
	LaggyAddonDetectorDB = db
	ns.db = db
end

-- --- reports ------------------------------------------------------------------------------------

local function Joined(list, limit, describe)
	local parts = {}
	for i = 1, math.min(#list, limit) do
		parts[#parts + 1] = describe(list[i])
	end
	if #list > limit then
		parts[#parts + 1] = format(L["and %d more"], #list - limit)
	end
	return table.concat(parts, ", ")
end

local function Collect(test, key)
	local found = {}
	for _, entry in ipairs(P.list) do
		if test(entry) then
			found[#found + 1] = entry
		end
	end
	table.sort(found, function(a, b)
		return a[key] > b[key]
	end)
	return found
end

local function SlowList(entries)
	return Joined(entries, 6, function(entry)
		return format("%s %d", entry.title, entry.slow)
	end)
end

-- A summary in chat: the busiest addons, slow frames in the period and fast-growing memory.
function ns.Report()
	P.Sample(nil)
	M.SampleHeap()
	M.Scan()
	local t = P.totals
	if not P.available then
		Utils.Print(L["The game's addon profiler isn't answering, so there are no CPU figures."])
		return
	end
	Utils.Print(format(L["%d addons, %.0f fps, addons take %s a frame (%s of frame time), Lua memory %s"],
		#P.list, t.fps, Utils.Ms(t.now), Utils.Percent(t.share), Utils.Memory(M.heap)))
	local top = P.Top(5)
	local busiest = {}
	for i = 1, #top do
		if top[i].now >= 0.005 then
			busiest[#busiest + 1] = top[i]
		end
	end
	if #busiest > 0 then
		Utils.Line(L["Busiest now: "] .. Joined(busiest, 5, function(entry)
			return entry.title .. " " .. Utils.Ms(entry.now)
		end))
	end
	local slow = Collect(function(entry)
		return entry.slow > 0
	end, "slow")
	if t.slow > 0 then
		Utils.Line(format(L["Frames over %d ms %s: %d"], P.spikeMs, P.PeriodText(), t.slow)
			.. (#slow > 0 and (" (" .. SlowList(slow) .. ")") or ""))
	else
		Utils.Line(format(L["No frames over %d ms %s."], P.spikeMs, P.PeriodText()))
	end
	local growing = Collect(function(entry)
		return entry.growthKnown and entry.growth >= ns.db.growthWarn
	end, "growth")
	if #growing > 0 then
		Utils.Line(L["Fast-growing memory: "] .. Joined(growing, 5, function(entry)
			return entry.title .. " " .. Utils.Rate(entry.growth)
		end))
	end
end

-- The latest `count` slow frames in chat.
function ns.ReportSpikes(count)
	local log = ns.db.spikeLog
	if #log == 0 then
		Utils.Print(format(L["No slow frames over %d ms logged."], P.spikeMs))
		return
	end
	Utils.Print(format(L["The latest %d slow frames:"], math.min(count, #log)))
	for i = #log, math.max(1, #log - count + 1), -1 do
		local item = log[i]
		Utils.Line(Utils.Clock(item.t) .. "  " .. S.Describe(item))
	end
end

-- After login, from steady play only: addons whose CPU averaged over the threshold, and those that
-- made slow frames once start-up was over. With the default setting it says nothing at all unless
-- one of those turned up.
local login = { readings = 0 }

local function LoginReport()
	local mode = ns.db.loginReport
	if mode == "off" or login.readings == 0 then
		return
	end
	local busy = Collect(function(entry)
		entry.loginCpu = (entry.loginCpuSum or 0) / login.readings
		return entry.loginCpu >= ns.db.cpuWarn
	end, "loginCpu")
	local slow = Collect(function(entry)
		entry.loginSlow = P.SlowSince(entry, login.counts)
		return entry.loginSlow > 0
	end, "loginSlow")
	local t = P.totals
	if #busy == 0 and #slow == 0 then
		if mode == "always" then
			Utils.Print(format(L["%d addons, addons take %s a frame (%s). Nothing over your thresholds."], #P.list, Utils.Ms(t.now), Utils.Percent(t.share)))
		end
		return
	end
	Utils.Print(format(L["%d addons, addons take %s a frame (%s)."], #P.list, Utils.Ms(t.now), Utils.Percent(t.share)))
	if #busy > 0 then
		Utils.Line(format(L["Busy (%s a frame or more): "], Utils.Ms(ns.db.cpuWarn)) .. Joined(busy, 6, function(entry)
			return entry.title .. " " .. Utils.Ms(entry.loginCpu)
		end))
	end
	if #slow > 0 then
		Utils.Line(format(L["Made frames over %d ms after start-up: "], P.spikeMs) .. Joined(slow, 6, function(entry)
			return format("%s %d", entry.title, entry.loginSlow)
		end))
	end
	Utils.Line(L["Type /lad to see every addon."])
end

-- What this addon costs: the profiler's figures for it, its memory and its own timings.
function ns.PrintPerformance()
	Utils.Print(L["What this addon costs"])
	local get = C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric
	local metric = P.Metric
	if P.Enabled() and get then
		Utils.Line(format(L["CPU: %s a frame now, %s on average since reload, peak %s"],
			Utils.Ms(get(addonName, metric.RecentAverageTime)), Utils.Ms(get(addonName, metric.SessionAverageTime)), Utils.Ms(get(addonName, metric.PeakTime))))
		Utils.Line(format(L["Frames where it took over 5 ms since reload: %d"], get(addonName, metric.CountTimeOver5Ms)))
	else
		Utils.Line(L["No CPU figures: the game's addon profiler isn't answering."])
	end
	local memory = M.Of(addonName)
	if memory then
		Utils.Line(format(L["Memory: %s (the slow frame log is part of it)"], Utils.Memory(memory)))
	end
	if ns.loadFiles then
		local setup = ns.loadSetup or 0
		Utils.Line(format(L["Loading: %.1f ms (files %.1f ms, setup %.1f ms)"], ns.loadFiles + setup, ns.loadFiles, setup))
	end
	if P.lastSampleMs then
		Utils.Line(format(L["Last table sample: %.2f ms for %d addons"], P.lastSampleMs, #P.list))
	end
	if M.lastCost then
		Utils.Line(format(L["Last memory scan: %.1f ms (the game counting every addon)"], M.lastCost))
	end
	Utils.Line(format(L["Slow frame watch: %s"], S.Watching() and L["on, one read every 2 s"] or L["off"]))
	Utils.Line(format(L["On-screen stats: %s"], ns.db.overlay.enabled and format(L["on, every %s s"], tostring(ns.db.overlay.rate)) or L["off"]))
end

-- --- settings reset -----------------------------------------------------------------------------

-- Everything that follows the settings, applied again.
local function ApplyAll()
	Utils.ApplyFontSize()
	P.SetThreshold(ns.db.spikeMs)
	S.Apply()
	S.OnThresholdChanged()
	ns.Popup.Apply()
	ns.Popup.ApplyCompartment()
	ns.Popup.ApplyBroker()
	ns.Overlay.Apply()
	ns.Window.Refresh()
	ns.Settings.Refresh()
end

function ns.ResetSettings()
	local log = ns.db.spikeLog
	LaggyAddonDetectorDB = nil
	SetupDB()
	ns.db.spikeLog = log
	ns.Window.ResetGeometry()
	ApplyAll()
	Utils.Print(L["Settings reset. The slow frame log was kept."])
end

-- --- chat commands and key bindings -------------------------------------------------------------

local function PrintHelp()
	Utils.Print(format(L["Version %s. Commands:"], Utils.Metadata(addonName, "Version") or "?"))
	Utils.Line("/lad - " .. L["open or close the window"])
	Utils.Line("/lad report - " .. L["a summary in chat"])
	Utils.Line("/lad log - " .. L["the slow frame log"])
	Utils.Line("/lad spikes - " .. L["the latest 10 slow frames in chat"])
	Utils.Line("/lad mark - " .. L["count slow frames from now (again: back to since login)"])
	Utils.Line("/lad stats - " .. L["show or hide the on-screen stats"])
	Utils.Line("/lad stats move - " .. L["unlock the on-screen stats to drag them (right-click them to lock)"])
	Utils.Line("/lad mem - " .. L["scan memory now"])
	Utils.Line("/lad config - " .. L["settings"])
	Utils.Line("/lad perf - " .. L["what this addon costs"])
	Utils.Line("/lad debug - " .. L["debug mode, and the errors the addon caught"])
	Utils.Line("/lad reset - " .. L["reset settings (keeps the log)"])
end

local function ToggleMark()
	if P.Marked() then
		P.ClearMark()
		Utils.Print(L["Counting slow frames since login again."])
	else
		P.Mark()
		Utils.Print(L["Counting slow frames from now. /lad mark again to go back."])
	end
end

local function HandleSlash(message)
	local command = Utils.Trim(message):lower()
	if command == "" then
		ns.Window.Toggle()
	elseif command == "report" then
		ns.Report()
	elseif command == "log" then
		ns.Window.Show("log")
	elseif command == "spikes" then
		ns.ReportSpikes(10)
	elseif command == "mark" then
		ToggleMark()
	elseif command == "stats move" or command == "overlay move" then
		ns.Overlay.Move()
	elseif command == "stats lock" or command == "overlay lock" then
		ns.Overlay.Lock()
	elseif command == "stats" or command == "overlay" then
		ns.Overlay.Toggle()
		Utils.Print(ns.db.overlay.enabled and L["On-screen stats on."] or L["On-screen stats off."])
	elseif command == "mem" or command == "memory" then
		if M.Scan() then
			Utils.Print(format(L["Memory scanned in %.1f ms. Lua memory: %s."], M.lastCost, Utils.Memory(collectgarbage("count"))))
			ns.Window.Tick()
		else
			Utils.Print(L["Memory can't be scanned in combat."])
		end
	elseif command == "config" or command == "settings" or command == "options" then
		ns.Settings.Open()
	elseif command == "perf" then
		ns.PrintPerformance()
	elseif command == "debug" then
		ns.db.debug = not ns.db.debug
		Utils.Print(ns.db.debug and L["Debug on."] or L["Debug off."])
		if #ns.errors == 0 then
			Utils.Line(L["No errors caught."])
		end
		for _, caught in ipairs(ns.errors) do
			Utils.Line(format("%s (%s, x%d)", caught.message, caught.label, caught.count))
		end
	elseif command == "reset" then
		ns.ResetSettings()
	else
		PrintHelp()
	end
end

SLASH_LAGGYADDONDETECTOR1 = "/lad"
SLASH_LAGGYADDONDETECTOR2 = "/laggy"
SlashCmdList.LAGGYADDONDETECTOR = Utils.Protect("chat command", HandleSlash)

BINDING_HEADER_LAGGYADDONDETECTOR = Utils.TITLE
BINDING_NAME_LAGGYADDONDETECTOR_WINDOW = L["Open or close the window"]
BINDING_NAME_LAGGYADDONDETECTOR_STATS = L["Show or hide the on-screen stats"]
BINDING_NAME_LAGGYADDONDETECTOR_MARK = L["Measure from now / since login"]
BINDING_NAME_LAGGYADDONDETECTOR_REPORT = L["Report in chat"]

LaggyAddonDetector_OnBinding = Utils.Protect("key binding", function(action)
	if action == "window" then
		ns.Window.Toggle()
	elseif action == "stats" then
		ns.Overlay.Toggle()
	elseif action == "mark" then
		ToggleMark()
	elseif action == "report" then
		ns.Report()
	end
end)

-- --- events -------------------------------------------------------------------------------------

-- The addon loads during the loading screen.
S.context.loading = true

local loginSettled = false

-- The login loading screen is over: the measuring period starts, and the login report follows.
local function LoginSettled()
	if loginSettled then
		return
	end
	loginSettled = true
	S.context.loading = false
	S.context.loadingEnded = GetTime()
	P.StartLogin()
	if ns.db.loginReport == "off" then
		return
	end
	C_Timer.After(LOGIN_SETTLE, Utils.Protect("login report", function()
		login.counts = P.SnapshotSlow({})
	end))
	for index, at in ipairs(LOGIN_READINGS) do
		C_Timer.After(at, Utils.Protect("login report", function()
			if P.Sample(nil) then
				login.readings = login.readings + 1
				for _, entry in ipairs(P.list) do
					entry.loginCpuSum = (entry.loginCpuSum or 0) + entry.now
				end
			end
			if index == #LOGIN_READINGS then
				LoginReport()
			end
		end))
	end
end

local events = CreateFrame("Frame")

events:SetScript("OnEvent", Utils.Protect("event", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			local started = debugprofilestop()
			SetupDB()
			Utils.ApplyFontSize()
			P.SetThreshold(ns.db.spikeMs)
			ns.Settings.Register()
			ns.loadSetup = debugprofilestop() - started
		else
			P.OnAddonLoaded(arg1)
		end
	elseif event == "PLAYER_LOGIN" then
		P.Build()
		S.Apply()
		ns.Popup.Apply()
		ns.Popup.ApplyBroker()
		ns.Overlay.Apply()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- The compartment lists the addon on entering the world; take it out after if it's off.
		C_Timer.After(0, Utils.Protect("compartment", ns.Popup.ApplyCompartment))
		-- A data bar addon may have brought LibDataBroker after login.
		ns.Popup.ApplyBroker()
		if not loginSettled then
			C_Timer.After(LOGIN_FALLBACK, Utils.Protect("login", LoginSettled))
		end
	elseif event == "LOADING_SCREEN_ENABLED" then
		S.context.loading = true
	elseif event == "LOADING_SCREEN_DISABLED" then
		S.context.loading = false
		S.context.loadingEnded = GetTime()
		LoginSettled()
	elseif event == "PLAYER_REGEN_ENABLED" then
		S.context.combatEnded = GetTime()
	elseif event == "ENCOUNTER_START" then
		S.context.encounter = type(arg2) == "string" and not Utils.IsSecret(arg2) and arg2 or L["a boss"]
	elseif event == "ENCOUNTER_END" then
		S.context.encounter = nil
	end
end))

for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END",
}) do
	events:RegisterEvent(event)
end

-- The last file the game loads (see the TOC): how long loading the addon's files took.
if ns.loadStarted then
	ns.loadFiles = debugprofilestop() - ns.loadStarted
end
