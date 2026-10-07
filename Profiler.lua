local addonName, ns = ...

-- Everything the game's addon profiler (C_AddOnProfiler) says about each loaded addon, kept in one
-- table per addon that lives as long as the session: a sample overwrites numbers in place and makes
-- no garbage. The profiler measures only user-installed addons, and resets on every reload.

local Utils = ns.Utils
local P = {}
ns.Profiler = P

local profiler = C_AddOnProfiler
local GetAddOnMetric = profiler and profiler.GetAddOnMetric
local GetOverallMetric = profiler and profiler.GetOverallMetric
local GetApplicationMetric = profiler and profiler.GetApplicationMetric
local GetTopK = profiler and profiler.GetTopKAddOnsForMetric
local GetFramerate, GetTime, debugprofilestop = GetFramerate, GetTime, debugprofilestop
local wipe, sort = table.wipe or wipe, table.sort

local Metric = (Enum and Enum.AddOnProfilerMetric) or {
	SessionAverageTime = 0,
	RecentAverageTime = 1,
	EncounterAverageTime = 2,
	LastTime = 3,
	PeakTime = 4,
	CountTimeOver1Ms = 5,
	CountTimeOver5Ms = 6,
	CountTimeOver10Ms = 7,
	CountTimeOver50Ms = 8,
	CountTimeOver100Ms = 9,
	CountTimeOver500Ms = 10,
	CountTimeOver1000Ms = 11,
}
P.Metric = Metric
local RECENT, PEAK = Metric.RecentAverageTime, Metric.PeakTime

-- The frame times the profiler counts, in ms, and the metric counting frames over each.
P.THRESHOLDS = { 1, 5, 10, 50, 100, 500, 1000 }
P.COUNT = {
	[1] = Metric.CountTimeOver1Ms,
	[5] = Metric.CountTimeOver5Ms,
	[10] = Metric.CountTimeOver10Ms,
	[50] = Metric.CountTimeOver50Ms,
	[100] = Metric.CountTimeOver100Ms,
	[500] = Metric.CountTimeOver500Ms,
	[1000] = Metric.CountTimeOver1000Ms,
}

-- The fields a sample can fill, and the metric behind each. `now` and `slow` are always read.
P.FIELD_METRIC = {
	now = RECENT,
	avg = Metric.SessionAverageTime,
	boss = Metric.EncounterAverageTime,
	last = Metric.LastTime,
	peak = PEAK,
}
-- Every field, for the one addon a tooltip or the detail pane shows.
P.ALL_FIELDS = { "now", "avg", "boss", "last", "peak" }

P.list = {} -- every addon the profiler can measure, in load order
P.byName = {}
P.view = {} -- P.list as the window shows it: filtered and sorted
P.totals = { now = 0, app = 0, share = 0, slow = 0, fps = 0 }
P.spikeMs = 50
P.available = false

local list, byName, totals = P.list, P.byName, P.totals
local slowMetric = P.COUNT[50]

function P.Enabled()
	if not (GetAddOnMetric and GetOverallMetric) then
		return false
	end
	return not profiler.IsEnabled or profiler.IsEnabled() == true
end

-- --- the addon list -----------------------------------------------------------------------------

local function Loaded(indexOrName)
	local loaded = Utils.IsAddOnLoaded(indexOrName)
	return loaded and loaded ~= 0
end

-- Adds a loaded addon (by index or folder name) unless it's Blizzard's or the profiler refuses it.
function P.Add(indexOrName)
	local name, title, notes, _, _, security = Utils.GetAddOnInfo(indexOrName)
	if type(name) ~= "string" or byName[name] or security == "SECURE" or name:find("^Blizzard_") then
		return
	end
	if not Loaded(name) then
		return
	end
	if GetAddOnMetric and not pcall(GetAddOnMetric, name, RECENT) then
		return
	end
	title = Utils.StripCodes(title or name)
	if title == "" then
		title = name
	end
	local entry = {
		name = name,
		nameLower = name:lower(),
		title = title,
		titleLower = title:lower(),
		notes = Utils.StripCodes(notes),
		version = Utils.Metadata(name, "Version"),
		author = Utils.Metadata(name, "Author"),
		lod = Utils.Call(Utils.IsAddOnLoadOnDemand, name) and true or false,
		self = name == addonName,
		now = 0, avg = 0, boss = 0, last = 0, peak = 0, slow = 0,
		memory = 0, growth = 0,
	}
	list[#list + 1] = entry
	byName[name] = entry
	ns.Fire("ADDON_ADDED", entry)
	return entry
end

function P.Build()
	local count = Utils.GetNumAddOns() or 0
	for index = 1, count do
		P.Add(index)
	end
	P.built = true
end

-- A load-on-demand addon loaded after login.
function P.OnAddonLoaded(name)
	if P.built then
		P.Add(name)
	end
end

-- --- the measuring period -----------------------------------------------------------------------

-- Slow frame counts are shown from a starting point: the end of the login loading screen (so an
-- addon's start-up work doesn't count as lag), or the moment the player picked with "Measure from
-- now". Each start keeps every addon's counts at that moment, for every threshold.
P.start = nil -- { kind = "login" | "mark", at = GetTime(), clock = time(), overall = { [ms] = n } }
local loginStart, markStart

local function TakeStart(kind)
	local start = { kind = kind, at = GetTime(), clock = time(), overall = {} }
	local field = kind == "login" and "baseLogin" or "baseMark"
	if P.Enabled() then
		for _, ms in ipairs(P.THRESHOLDS) do
			start.overall[ms] = Utils.Number(GetOverallMetric(P.COUNT[ms])) or 0
		end
		for i = 1, #list do
			local entry = list[i]
			local base = entry[field] or {}
			for _, ms in ipairs(P.THRESHOLDS) do
				base[ms] = GetAddOnMetric(entry.name, P.COUNT[ms]) or 0
			end
			entry[field] = base
		end
	end
	return start
end

function P.StartLogin()
	if loginStart then
		return
	end
	loginStart = TakeStart("login")
	if not markStart then
		P.start = loginStart
	end
end

function P.Mark()
	for i = 1, #list do
		list[i].baseMark = nil
	end
	markStart = TakeStart("mark")
	P.start = markStart
	ns.Fire("PERIOD_CHANGED")
end

function P.ClearMark()
	markStart = nil
	P.start = loginStart
	ns.Fire("PERIOD_CHANGED")
end

function P.Marked()
	return markStart ~= nil
end

-- An addon's count at the start of the period. An addon loaded after it has none: all its frames
-- are in the period.
local function Base(entry, ms)
	local base = markStart and entry.baseMark or (loginStart and entry.baseLogin)
	return base and base[ms] or 0
end

local function OverallBase(ms)
	local start = P.start
	return start and start.overall[ms] or 0
end

-- "since login" / "since 21:04:13 (2m 13s)".
function P.PeriodText()
	local L = ns.L
	if markStart then
		return string.format(L["since %s (%s)"], date("%H:%M:%S", markStart.clock), Utils.Duration(GetTime() - markStart.at))
	end
	return L["since login"]
end

function P.SetThreshold(ms)
	if not P.COUNT[ms] then
		ms = 50
	end
	P.spikeMs = ms
	slowMetric = P.COUNT[ms]
end

-- --- sampling -----------------------------------------------------------------------------------

-- The totals: frame rate, all addons' CPU time a frame and their share of it, and slow frames in the
-- period. Three profiler reads.
function P.SampleTotals()
	totals.fps = GetFramerate() or 0
	if not P.Enabled() then
		P.available = false
		return false
	end
	local now = Utils.Number(GetOverallMetric(RECENT))
	local app = Utils.Number(GetApplicationMetric and GetApplicationMetric(RECENT))
	local slow = Utils.Number(GetOverallMetric(slowMetric))
	if not (now and slow) then
		P.available = false
		return false
	end
	totals.now, totals.app = now, app or 0
	totals.share = totals.app > 0 and now / totals.app * 100 or 0
	totals.slow = slow - OverallBase(P.spikeMs)
	P.available = true
	return true
end

-- Reads every addon's current CPU and slow frame count, plus `fields` (P.FIELD_METRIC keys) for
-- every addon. The window asks only for its sort column here; the other columns are read for the
-- rows on screen (P.Fill).
function P.Sample(fields)
	local started = debugprofilestop()
	if not P.SampleTotals() then
		return false
	end
	local spikeMs = P.spikeMs
	local count = fields and #fields or 0
	for i = 1, #list do
		local entry = list[i]
		local name = entry.name
		entry.now = GetAddOnMetric(name, RECENT)
		entry.slow = GetAddOnMetric(name, slowMetric) - Base(entry, spikeMs)
		for f = 1, count do
			local field = fields[f]
			entry[field] = GetAddOnMetric(name, P.FIELD_METRIC[field])
		end
	end
	P.lastSampleMs = debugprofilestop() - started
	P.sampledAt = GetTime()
	return true
end

-- Reads `fields` for one addon.
function P.Fill(entry, fields)
	if not P.available then
		return
	end
	local name = entry.name
	for f = 1, #fields do
		local field = fields[f]
		entry[field] = GetAddOnMetric(name, P.FIELD_METRIC[field])
	end
end

-- Every threshold's count in the period for one addon, into `out` (indexed like P.THRESHOLDS).
function P.Counts(entry, out)
	for i, ms in ipairs(P.THRESHOLDS) do
		out[i] = P.available and (GetAddOnMetric(entry.name, P.COUNT[ms]) - Base(entry, ms)) or 0
	end
	return out
end

-- Every addon's count of frames over the threshold right now, by folder name, into `out`.
function P.SnapshotSlow(out)
	if P.Enabled() then
		for i = 1, #list do
			local entry = list[i]
			out[entry.name] = GetAddOnMetric(entry.name, slowMetric) or 0
		end
	end
	return out
end

-- An addon's frames over the threshold since a P.SnapshotSlow (all of them if it loaded after).
function P.SlowSince(entry, snapshot)
	if not (snapshot and P.Enabled()) then
		return 0
	end
	return (GetAddOnMetric(entry.name, slowMetric) or 0) - (snapshot[entry.name] or 0)
end

-- An addon's share of frame time, worked out as the game's AddOns list does: its time over the time
-- the game would spend with this addon as the only one running.
function P.Share(entry)
	local whole = totals.app - totals.now + entry.now
	return whole > 0 and entry.now / whole * 100 or 0
end

-- The `k` busiest addons right now, from the profiler's own ranking (one call), in a reused list.
local top = {}

function P.Top(k)
	wipe(top)
	if not P.Enabled() then
		return top
	end
	if GetTopK then
		local ok, results = pcall(GetTopK, RECENT, k)
		if ok and type(results) == "table" then
			for i = 1, #results do
				local result = results[i]
				local entry = byName[result.addOnName]
				if entry and Utils.Number(result.metricValue) then
					entry.now = result.metricValue
					top[#top + 1] = entry
				end
			end
			return top
		end
	end
	-- No ranking from the game: read everyone and keep the top k.
	for i = 1, #list do
		local entry = list[i]
		entry.now = GetAddOnMetric(entry.name, RECENT)
		local at = #top + 1
		while at > 1 and top[at - 1].now < entry.now do
			at = at - 1
		end
		if at <= k then
			table.insert(top, at, entry)
			top[k + 1] = nil
		end
	end
	return top
end

-- --- problems, filtering and sorting ------------------------------------------------------------

-- Busy (CPU over the threshold), caused slow frames in the period, or memory growing fast. Memory
-- size alone is never a problem: a big addon that sits still costs nothing a frame.
function P.IsProblem(entry)
	local db = ns.db
	return entry.now >= db.cpuWarn or entry.slow > 0 or entry.growth >= db.growthWarn
end

local comparators = {}

local function ByTitle(a, b)
	if a.titleLower == b.titleLower then
		return a.nameLower < b.nameLower
	end
	return a.titleLower < b.titleLower
end

local function ByTitleDesc(a, b)
	return ByTitle(b, a)
end

comparators.name = { [true] = ByTitle, [false] = ByTitleDesc }

for _, key in ipairs({ "now", "avg", "boss", "last", "peak", "slow", "memory", "growth" }) do
	comparators[key] = {
		[true] = function(a, b)
			local x, y = a[key], b[key]
			if x == y then
				return ByTitle(a, b)
			end
			return x < y
		end,
		[false] = function(a, b)
			local x, y = a[key], b[key]
			if x == y then
				return ByTitle(a, b)
			end
			return x > y
		end,
	}
end
-- Share follows CPU now one for one.
comparators.share = comparators.now

-- Fills P.view from P.list: matching `search` (lowercase, plain text) and, with `onlyProblems`, only
-- problem addons; sorted by `key`.
function P.BuildView(search, onlyProblems, key, ascending)
	local view = P.view
	wipe(view)
	local searching = search and search ~= ""
	for i = 1, #list do
		local entry = list[i]
		if (not searching or entry.titleLower:find(search, 1, true) or entry.nameLower:find(search, 1, true))
			and (not onlyProblems or P.IsProblem(entry)) then
			view[#view + 1] = entry
		end
	end
	local comparator = comparators[key] or comparators.now
	sort(view, comparator[ascending and true or false])
	return view
end

-- How many addons are problems right now (P.IsProblem).
function P.ProblemCount()
	local count = 0
	for i = 1, #list do
		if P.IsProblem(list[i]) then
			count = count + 1
		end
	end
	return count
end
