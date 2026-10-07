-- Drives the addon through a session against the model in wow.lua: login, slow frames, a boss
-- fight, a loading screen, memory scans, the window, the popup, the on-screen stats, the settings
-- page and every chat command. Run by run.py; SCENARIO picks which.

local checks, failures = 0, {}

local function check(condition, message)
	checks = checks + 1
	if not condition then
		failures[#failures + 1] = message
	end
end

local function eq(actual, expected, message)
	check(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local function near(actual, expected, tolerance, message)
	check(type(actual) == "number" and math.abs(actual - expected) <= tolerance,
		string.format("%s: expected ~%s, got %s", message, tostring(expected), tostring(actual)))
end

local function FindChild(widget, kind, test)
	for _, child in ipairs(widget.children) do
		if child.kind == kind and (not test or test(child)) then
			return child
		end
		local found = FindChild(child, kind, test)
		if found then
			return found
		end
	end
end

local function EachChild(widget, kind, fn)
	for _, child in ipairs(widget.children) do
		if child.kind == kind then
			fn(child)
		end
		EachChild(child, kind, fn)
	end
end

local function NoFormatLeftovers()
	for _, line in ipairs(WOW.chat) do
		if line:find("%%[sd]") then
			return false, line
		end
	end
	return true
end

local function Login(ns)
	WOW.Fire("ADDON_LOADED", "LaggyAddonDetector")
	WOW.Fire("ADDON_LOADED", "Plater")
	WOW.Fire("PLAYER_LOGIN")
	WOW.Fire("PLAYER_ENTERING_WORLD", true, false)
	WOW.Advance(0.1)
	WOW.Fire("LOADING_SCREEN_DISABLED")
end

local scenarios = {}

function scenarios.session()
	local M_RECENT, M_SESSION, M_PEAK, M_LAST, M_BOSS = 1, 0, 4, 3, 2
	local C50, C100 = 8, 9
	WOW.SetMetric("Plater", M_RECENT, 0.61)
	WOW.SetMetric("Plater", M_SESSION, 0.48)
	WOW.SetMetric("Plater", M_PEAK, 60)
	WOW.SetMetric("Plater", C50, 2)
	WOW.SetMetric("WeakAuras", M_RECENT, 0.33)
	WOW.SetMetric("WeakAuras", M_PEAK, 150)
	WOW.SetMetric("Details", M_RECENT, 1.4)
	WOW.SetMetric("Details", M_BOSS, 2.2)
	WOW.SetMetric("BigWigs", M_RECENT, 0.09)
	WOW.SetMetric("LaggyAddonDetector", M_RECENT, 0.01)
	WOW.memory = { Plater = 39000, WeakAuras = 62000, AllTheThings = 186000, Details = 25000, LaggyAddonDetector = 300 }
	WOW.overall[C50] = 3

	local ns = WOW.LoadAddon(ROOT)
	Login(ns)
	local P, S, M = ns.Profiler, ns.SpikeWatch, ns.Memory
	local log = ns.db.spikeLog

	-- The addon list.
	eq(#P.list, 6, "loaded, measurable addons listed")
	eq(P.byName.Plater.title, "Plater Nameplates", "colour codes stripped from titles")
	eq(P.byName.WeakAuras.title, "WeakAuras", "textures stripped from titles")
	check(P.byName.Blizzard_Foo == nil, "Blizzard's addons are left out")
	check(P.byName.NotLoaded == nil, "addons that aren't loaded are left out")
	eq(P.byName.Plater.version, "5.18", "version read")

	-- Slow frames from the login loading screen don't count.
	P.Sample(nil)
	eq(P.byName.Plater.slow, 0, "loading-screen slow frames left out of the table")
	eq(P.totals.slow, 0, "loading-screen slow frames left out of the total")
	near(P.totals.share, (0.61 + 0.33 + 1.4 + 0.09 + 0.01) / 8.3 * 100, 0.01, "addons' share of the frame")

	-- Past the few seconds after a loading screen that still count as part of it.
	WOW.Advance(4)

	-- A slow frame by one addon, with its exact length (its peak rose).
	WOW.AddMetric("Plater", C50, 1)
	WOW.SetMetric("Plater", M_PEAK, 112)
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	eq(#log, 1, "a slow frame is logged")
	eq(log[1] and log[1].addon, "Plater Nameplates", "the culprit is named")
	eq(log[1] and log[1].ms, 112, "its exact length comes from the peak")
	eq(log[1] and log[1].over, 50, "it is over the 50 ms threshold")
	eq(log[1] and log[1].zone, "Dornogal", "where it happened")

	-- Over a higher threshold, but the peak didn't move: the length is a range.
	WOW.AddMetric("WeakAuras", C50, 1)
	WOW.AddMetric("WeakAuras", C100, 1)
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	eq(log[2] and log[2].addon, "WeakAuras", "second culprit")
	eq(log[2] and log[2].over, 100, "the highest threshold crossed")
	check(log[2] and log[2].ms == nil, "no exact length without a new peak")

	-- A frame no single addon made slow.
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	eq(#log, 3, "a shared slow frame is logged")
	check(log[3] and log[3].addon == nil, "a shared slow frame has no single culprit")

	-- Loading screens are skipped.
	WOW.Fire("LOADING_SCREEN_ENABLED")
	WOW.AddMetric("Details", C50, 1)
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	eq(#log, 3, "slow frames in a loading screen are skipped")
	WOW.Fire("LOADING_SCREEN_DISABLED")
	WOW.Advance(5)

	-- In a boss fight.
	WOW.inCombat = true
	WOW.instance, WOW.instanceType, WOW.difficulty, WOW.difficultyName = "Nerub-ar Palace", "raid", 16, "Mythic"
	WOW.Fire("ENCOUNTER_START", 2922, "Queen Ansurek", 16, 20)
	WOW.AddMetric("Plater", C50, 1)
	WOW.SetMetric("Plater", M_PEAK, 140)
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	eq(log[4] and log[4].boss, "Queen Ansurek", "the boss is noted")
	check(log[4] and log[4].combat, "combat is noted")
	eq(log[4] and log[4].zone, "Nerub-ar Palace (Mythic)", "the instance and difficulty are noted")
	check(S.Describe(log[4]):find("Plater Nameplates", 1, true), "the chat line names the addon")
	check(not M.Scan(), "no memory scan in combat")
	WOW.Fire("ENCOUNTER_END", 2922, "Queen Ansurek", 16, 20, 1)
	WOW.inCombat = false
	WOW.Fire("PLAYER_REGEN_ENABLED")
	WOW.instance, WOW.instanceType, WOW.difficulty, WOW.difficultyName = nil, nil, nil, nil
	WOW.Advance(3)

	-- A key: keystone level instead of the difficulty name.
	WOW.instance, WOW.instanceType, WOW.difficulty, WOW.keystone = "Ara-Kara", "party", 8, 12
	WOW.AddMetric("Details", C50, 1)
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	eq(log[5] and log[5].zone, "Ara-Kara +12", "the keystone level is noted")
	WOW.instance, WOW.instanceType, WOW.difficulty, WOW.keystone = nil, nil, nil, nil

	-- The table's counts since login, and "Measure from now".
	P.Sample(nil)
	eq(P.byName.Plater.slow, 2, "Plater's slow frames since login")
	P.Mark()
	P.Sample(nil)
	eq(P.byName.Plater.slow, 0, "a mark starts the count over")
	WOW.AddMetric("Plater", C50, 1)
	WOW.AddOverall(C50, 1)
	P.Sample(nil)
	eq(P.byName.Plater.slow, 1, "counted from the mark")
	eq(P.totals.slow, 1, "total counted from the mark")
	check(P.PeriodText():find("since", 1, true), "the period is described")
	P.ClearMark()
	P.Sample(nil)
	eq(P.byName.Plater.slow, 3, "back to since login")
	WOW.Advance(2.1)

	-- Memory growth: a rise between scans counts, a drop (a collection) is skipped.
	check(M.Scan(), "memory scanned")
	WOW.memory.Plater = 40000
	WOW.Advance(10)
	M.Scan()
	near(P.byName.Plater.growth, 100, 0.01, "growth between scans")
	WOW.memory.Plater = 30000
	WOW.Advance(10)
	M.Scan()
	near(P.byName.Plater.growth, 100, 0.01, "a drop leaves the growth alone")
	check(P.byName.AllTheThings.memory == 186000 and not P.IsProblem(P.byName.AllTheThings), "a big addon that sits still is not a problem")

	-- Filtering and sorting.
	for _, key in ipairs({ "name", "now", "share", "avg", "boss", "last", "peak", "slow", "memory", "growth" }) do
		for _, ascending in ipairs({ true, false }) do
			local ok, err = pcall(P.BuildView, "", false, key, ascending)
			check(ok, "sorting by " .. key .. ": " .. tostring(err))
		end
	end
	P.BuildView("", false, "now", false)
	eq(P.view[1].name, "Details", "busiest first")
	check(P.view[1].now >= P.view[2].now and P.view[2].now >= P.view[3].now, "sorted by CPU now")
	eq(#P.BuildView("pla", false, "now", false), 1, "search by title")
	eq(#P.BuildView("allthe", false, "now", false), 1, "search by folder name")
	local problems = P.BuildView("", true, "now", false)
	local names = {}
	for _, entry in ipairs(problems) do
		names[entry.name] = true
	end
	check(names.Details and names.Plater and names.WeakAuras and not names.AllTheThings and not names.BigWigs, "only problems")

	-- The window.
	local W = ns.Window
	W.Toggle()
	check(W.IsShown(), "the window opens")
	local ui, rows, logRows, state, columns, layout = W.Internals()
	WOW.Advance(1.1)
	check(rows[1].shown and rows[1].entry, "rows painted")
	eq(rows[1].entry and rows[1].entry.name, "Details", "the busiest addon on top")
	check((rows[1].cells[2].text or ""):find("ms", 1, true), "CPU cell shows milliseconds")
	check(layout.visible > 5, "rows fill the list")
	for _, column in ipairs(columns) do
		if column.header.shown then
			WOW.Click(column.header)
			WOW.Click(column.header)
		end
	end
	WOW.Click(columns[1].header, "RightButton")
	WOW.Pick("Boss fights")
	check(ns.db.columns.boss, "a column turned on from the header menu")
	WOW.Advance(1.1)
	check(columns[5].shown, "the boss column shows")
	for _, column in ipairs(columns) do
		if column.key == "now" then
			WOW.Click(column.header)
		end
	end
	ui.search:SetText("details")
	eq(#ns.Profiler.view, 1, "searching from the window")
	ui.search:SetText("")
	WOW.Click(ui.problems)
	check(ns.db.onlyProblems, "only problems ticked")
	WOW.Click(ui.problems)

	rows[1]:Fire("OnEnter")
	check(GameTooltip:NumLines() > 6, "row tooltip")
	rows[1]:Fire("OnLeave")
	local first = rows[1].entry
	WOW.Click(rows[1])
	eq(state.selected, first, "a click selects")
	check(ui.detail.shown, "the detail pane opens")
	WOW.Advance(1.1)
	WOW.Click(ui.detail.toggle)
	eq(WOW.enableState[first.name], 0, "disable after reload")
	eq(WOW.popup and WOW.popup.which, "LAGGYADDONDETECTOR_RELOAD", "asks to reload")
	StaticPopupDialogs.LAGGYADDONDETECTOR_RELOAD.OnAccept()
	eq(WOW.reloads, 1, "reload accepted")
	WOW.Click(ui.detail.toggle)
	eq(WOW.enableState[first.name], 2, "enabled again")
	WOW.Click(ui.detail.chat)
	check((WOW.inserted or ""):find(first.title, 1, true), "detail into chat")
	WOW.Click(rows[1], "RightButton")
	WOW.Pick("Put in chat")
	WOW.shift = true
	WOW.inserted = nil
	WOW.Click(rows[2])
	check(WOW.inserted, "Shift-click into chat")
	WOW.shift = false
	ui.detail.close:Fire("OnClick")
	check(state.selected == nil and not ui.detail.shown, "the detail pane closes")

	WOW.Click(ui.markButton)
	check(P.Marked(), "Measure from now")
	WOW.Click(ui.markButton)
	check(not P.Marked(), "back to since login")
	local scans = WOW.memoryScans
	ui.toolbar.children[1].children[4]:Fire("OnClick")
	ui.frame:SetSize(1200, 700)
	check(layout.visible > 20, "a taller window shows more rows")
	ui.list:Fire("OnMouseWheel", -1)
	WOW.Advance(1.1)

	WOW.Click(ui.tabs[2])
	eq(state.tab, "log", "the log view")
	eq(logRows[1].item, log[#log], "newest slow frame first")
	logRows[1]:Fire("OnEnter")
	check(GameTooltip:NumLines() >= 4, "log tooltip")
	WOW.shift = true
	WOW.Click(logRows[1])
	WOW.shift = false
	check((WOW.inserted or ""):find("Slow frame", 1, true), "log entry into chat")
	ui.summary[4]:Fire("OnEnter")
	WOW.Advance(1.1)
	WOW.Click(ui.tabs[1])
	ui.frame:Hide()
	check(not W.IsShown(), "the window closes")

	-- The minimap button and its popup.
	local button = LaggyAddonDetectorMinimapButton
	check(button and button.shown, "the minimap button shows")
	button:Fire("OnEnter")
	local lines = table.concat(GameTooltip.lines, "\n")
	check(lines:find("Busiest right now", 1, true), "popup lists the busiest addons")
	check(lines:find("Details! Damage Meter", 1, true), "popup names them")
	local topCalls = WOW.topCalls
	WOW.Advance(1.1)
	check(WOW.topCalls > topCalls, "the popup refreshes while shown")
	button:Fire("OnLeave")
	WOW.Click(button, "LeftButton")
	check(W.IsShown(), "click opens the window")
	WOW.Click(button, "LeftButton")
	WOW.Click(button, "RightButton")
	check(LaggyAddonDetectorSettings and LaggyAddonDetectorSettings.shown, "right-click opens the settings")
	WOW.Click(button, "MiddleButton")
	check(ns.db.overlay.enabled, "middle-click shows the on-screen stats")
	WOW.Click(button, "MiddleButton")
	WOW.shift = true
	WOW.Click(button, "LeftButton")
	WOW.shift = false
	check(WOW.ChatContains("Busiest now:"), "shift-click reports")

	LaggyAddonDetector_OnCompartmentEnter("LaggyAddonDetector", button)
	check(GameTooltip:NumLines() > 3, "compartment popup")
	LaggyAddonDetector_OnCompartmentLeave("LaggyAddonDetector", button)
	ns.db.compartment = false
	ns.Popup.ApplyCompartment()
	eq(#AddonCompartmentFrame.registeredAddons, 1, "taken out of the compartment")
	ns.db.compartment = true
	ns.Popup.ApplyCompartment()
	eq(#AddonCompartmentFrame.registeredAddons, 2, "back in the compartment")

	WOW.Advance(2.1)
	local feed = WOW.broker.objects.LaggyAddonDetector
	check(feed and feed.text:find("fps", 1, true), "data bar feed")
	feed.OnTooltipShow(GameTooltip)

	-- On-screen stats: one line per item, growing away from the anchor.
	ns.db.overlay.enabled = true
	ns.Overlay.Apply()
	local overlay, overlayLines, overlayHint = ns.Overlay.Internals()
	local function Shown()
		local texts = {}
		for _, line in ipairs(overlayLines) do
			if line.shown then
				texts[#texts + 1] = line.text
			end
		end
		return texts
	end
	local shownLines = Shown()
	eq(#shownLines, 4, "one line per default item")
	local joined = table.concat(shownLines, "\n")
	check(joined:find("120 fps", 1, true), "stats show the frame rate")
	check(joined:find("Latency 24 / 31 ms", 1, true), "stats show latency")
	check(joined:find("Slow frames", 1, true), "stats show slow frames")
	check(not joined:find("Busiest", 1, true), "busiest addon off by default")
	check(overlay.height >= 4 * 12 + 3 * 2, "the frame is as tall as its lines: " .. overlay.height)
	local p1, rel1 = overlayLines[2]:GetPoint(1)
	check(p1 == "TOPLEFT" and rel1 == overlayLines[1], "each line under the one before")
	eq(overlay:GetPoint(1), "TOPLEFT", "hangs from the top left")
	check(not overlayHint.shown, "no hint while locked")
	for key in pairs(ns.db.overlay.items) do
		ns.db.overlay.items[key] = true
	end
	ns.Overlay.Apply()
	eq(#Shown(), 7, "every item on its own line")
	local tall = overlay.height
	ns.db.overlay.layout = "line"
	ns.Overlay.Apply()
	shownLines = Shown()
	eq(#shownLines, 1, "one line")
	check(shownLines[1]:find("Busiest: Details", 1, true) and shownLines[1]:find("Lua", 1, true), "every item on the line")
	check(overlay.height < tall, "a single line is shorter")
	ns.db.overlay.layout = "stacked"
	ns.Overlay.SetAnchor("BOTTOMLEFT")
	ns.Overlay.Apply()
	eq(overlay:GetPoint(1), "BOTTOMLEFT", "hangs from the bottom left, so it grows up")
	local lp, lrel, lrp = overlayLines[1]:GetPoint(1)
	check(lp == "TOPLEFT" and lrel == overlay and lrp == "TOPLEFT", "lines still read top to bottom")
	ns.Overlay.SetAnchor("TOPRIGHT")
	ns.Overlay.Apply()
	local rp = overlayLines[1]:GetPoint(1)
	eq(rp, "TOPRIGHT", "lines line up on the right under a right anchor")
	WOW.AddMetric("Plater", C50, 1)
	WOW.AddOverall(C50, 1)
	WOW.Advance(2.1)
	check(table.concat(Shown(), "\n"):find("|c", 1, true), "a fresh slow frame is tinted")

	-- Moving: dropped bottom centre, then top right.
	SlashCmdList.LAGGYADDONDETECTOR("stats move")
	check(not ns.db.overlay.lock and overlayHint.shown, "unlocked to move, with a hint")
	overlay.left, overlay.top = 900, 100
	overlay:Fire("OnDragStop")
	eq(ns.db.overlay.point, "BOTTOM", "dropped low in the middle: hangs from the bottom")
	near(ns.db.overlay.y, 100 - overlay.height, 0.01, "kept where it was dropped")
	overlay.left, overlay.top = 1700, 1000
	overlay:Fire("OnDragStop")
	eq(ns.db.overlay.point, "TOPRIGHT", "dropped top right")
	near(ns.db.overlay.x, 1700 + overlay.width - 1920, 0.01, "measured from the right edge")
	overlay:Fire("OnMouseUp", "RightButton")
	check(ns.db.overlay.lock and not overlayHint.shown, "right-click locks")
	SlashCmdList.LAGGYADDONDETECTOR("stats move")
	SlashCmdList.LAGGYADDONDETECTOR("stats lock")
	check(ns.db.overlay.lock, "/lad stats lock")

	-- The settings page: every checkbox, choice, slider and button.
	ns.Settings.Open()
	local panel = LaggyAddonDetectorSettings
	check(panel.built, "the settings page is built")
	local buttons, sliders = {}, {}
	EachChild(panel, "Button", function(widget)
		buttons[#buttons + 1] = widget
	end)
	EachChild(panel, "Slider", function(widget)
		sliders[#sliders + 1] = widget
	end)
	check(#buttons > 30, "settings widgets: " .. #buttons)
	for _, widget in ipairs(buttons) do
		if widget.scripts.OnClick then
			WOW.menu = nil
			local ok, err = pcall(WOW.Click, widget)
			check(ok, "settings click: " .. tostring(err))
			if WOW.menu then
				local entries = WOW.menu.entries
				local ok2, err2 = pcall(entries[#entries].b)
				check(ok2, "settings choice: " .. tostring(err2))
			end
		end
	end
	for _, slider in ipairs(sliders) do
		if slider.scripts.OnValueChanged then
			local low, high = slider:GetMinMaxValues()
			slider:SetValue(high)
			slider:SetValue(low)
		end
	end
	ns.Settings.Refresh()
	eq(ns.db.spikeMs, 500, "threshold picked in the settings")
	eq(P.spikeMs, 500, "threshold applied")
	eq(ns.db.fontSize, -3, "text size from the slider")
	WOW.Advance(3)

	-- A load-on-demand addon loading after login (with the watch on: the settings clicks above
	-- turned it off).
	ns.db.spikeWatch = true
	S.Apply()
	WOW.addons[9].loaded = true
	WOW.Fire("ADDON_LOADED", "LateLoad")
	check(P.byName.LateLoad, "late-loaded addon listed")
	check(P.byName.LateLoad.seen, "and watched")

	-- The profiler going quiet.
	WOW.profilerOn = false
	W.Show("addons")
	WOW.Advance(2.1)
	check(not P.available, "no profiler noticed")
	button:Fire("OnEnter")
	button:Fire("OnLeave")
	ns.Report()
	WOW.profilerOn = true
	WOW.Advance(1.1)
	ui.frame:Hide()

	-- Every chat command.
	for _, command in ipairs({ "", "", "report", "log", "spikes", "mark", "mark", "stats", "stats", "mem", "config",
		"perf", "debug", "debug", "help", "nonsense" }) do
		local ok, err = pcall(SlashCmdList.LAGGYADDONDETECTOR, command)
		check(ok, "/lad " .. command .. ": " .. tostring(err))
	end
	ui.frame:Hide()
	local kept = #ns.db.spikeLog
	SlashCmdList.LAGGYADDONDETECTOR("reset")
	eq(#ns.db.spikeLog, kept, "reset keeps the log")
	eq(ns.db.spikeMs, 50, "reset restores the threshold")
	eq(P.spikeMs, 50, "and applies it")
	LaggyAddonDetector_OnBinding("window")
	LaggyAddonDetector_OnBinding("window")
	LaggyAddonDetector_OnBinding("report")

	-- Login report (20 s after the loading screen): Details is busy.
	check(WOW.ChatContains("Busy ("), "login report names busy addons")
	local clean, leftover = NoFormatLeftovers()
	check(clean, "chat text fully formatted: " .. tostring(leftover))

	-- Nothing keeps running that shouldn't: the slow frame watch and the data bar feed only.
	GameTooltip:Hide()
	WOW.Advance(1.1)
	eq(WOW.ActiveTickers(), 2, "tickers left running")

	-- And no caught errors along the way.
	for _, caught in ipairs(ns.errors) do
		check(false, "caught error: " .. caught.label .. ": " .. caught.message)
	end
end

function scenarios.migration()
	LaggyAddonDetectorDB = { minimapPos = 100, minimapHide = true, sortKey = "resources", sortAsc = false }
	local ns = WOW.LoadAddon(ROOT)
	Login(ns)
	eq(ns.db.version, 2, "settings upgraded")
	eq(ns.db.minimap.angle, 100, "minimap position kept")
	eq(ns.db.minimap.show, false, "hidden minimap button stays hidden")
	eq(ns.db.sortKey, "now", "old sort key mapped")
	check(ns.db.minimapPos == nil, "old keys removed")
	check(LaggyAddonDetectorMinimapButton == nil, "no minimap button built while hidden")
	eq(ns.db.overlay.enabled, false, "on-screen stats off by default")
	for _, caught in ipairs(ns.errors) do
		check(false, "caught error: " .. caught.label .. ": " .. caught.message)
	end
end

function scenarios.badsettings()
	LaggyAddonDetectorDB = { version = 2, cpuWarn = 50, spikeMs = 7, overlay = "x", columns = { now = "yes" }, sortKey = "bogus", spikeKeep = 3 }
	local ns = WOW.LoadAddon(ROOT)
	Login(ns)
	eq(ns.db.cpuWarn, 5, "CPU threshold clamped")
	eq(ns.db.spikeMs, 50, "unknown threshold reset")
	eq(type(ns.db.overlay), "table", "broken overlay settings replaced")
	eq(ns.db.columns.now, true, "broken column setting replaced")
	eq(ns.db.sortKey, "now", "unknown sort key reset")
	eq(ns.db.spikeKeep, 50, "log size clamped")
	ns.Window.Toggle()
	WOW.Advance(1.1)
	for _, caught in ipairs(ns.errors) do
		check(false, "caught error: " .. caught.label .. ": " .. caught.message)
	end
end

function scenarios.noprofiler()
	C_AddOnProfiler = nil
	local ns = WOW.LoadAddon(ROOT)
	Login(ns)
	ns.Window.Toggle()
	WOW.Advance(2.1)
	LaggyAddonDetectorMinimapButton:Fire("OnEnter")
	ns.Report()
	ns.PrintPerformance()
	ns.db.overlay.enabled = true
	ns.Overlay.Apply()
	WOW.Advance(1.1)
	check(not ns.Profiler.available, "no profiler")
	check(not ns.SpikeWatch.Watching(), "no watch without a profiler")
	for _, caught in ipairs(ns.errors) do
		check(false, "caught error: " .. caught.label .. ": " .. caught.message)
	end
end

-- All is well at login: a start-up hitch and a brief burst don't make the report speak.
function scenarios.quietlogin()
	WOW.SetMetric("Plater", 1, 0.2)
	WOW.SetMetric("WeakAuras", 1, 0.3)
	local ns = WOW.LoadAddon(ROOT)
	Login(ns)
	WOW.Advance(3)
	WOW.AddMetric("Plater", 8, 1)
	WOW.AddOverall(8, 1)
	WOW.Advance(7.5)
	WOW.SetMetric("WeakAuras", 1, 3.0)
	WOW.Advance(1)
	WOW.SetMetric("WeakAuras", 1, 0.3)
	WOW.Advance(30)
	eq(#WOW.chat, 0, "nothing in chat when all is well (" .. tostring(WOW.chat[1]) .. ")")
	for _, caught in ipairs(ns.errors) do
		check(false, "caught error: " .. caught.label .. ": " .. caught.message)
	end
end

-- A slow frame in steady play, and an addon busy the whole time: the report says so.
function scenarios.problemlogin()
	WOW.SetMetric("Plater", 1, 0.2)
	WOW.SetMetric("WeakAuras", 1, 1.6)
	local ns = WOW.LoadAddon(ROOT)
	Login(ns)
	WOW.Advance(12)
	WOW.AddMetric("Plater", 8, 1)
	WOW.AddOverall(8, 1)
	WOW.Advance(20)
	check(WOW.ChatContains("after start-up: Plater Nameplates 1"), "the steady-play slow frame is reported")
	check(WOW.ChatContains("Busy (1.00 ms a frame or more): WeakAuras 1.60 ms"), "the busy addon is reported")
	for _, caught in ipairs(ns.errors) do
		check(false, "caught error: " .. caught.label .. ": " .. caught.message)
	end
end

local run = scenarios[SCENARIO]
assert(run, "no scenario " .. tostring(SCENARIO))
local ok, err = pcall(run)
if not ok then
	failures[#failures + 1] = "error: " .. tostring(err)
end
RESULT = { checks = checks, failures = failures }
