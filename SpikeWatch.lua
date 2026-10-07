local _, ns = ...

-- The slow frame watch: finds the addon behind a stutter even with nothing open.
--
-- Every two seconds it reads one number: how many frames so far had addons take longer than the
-- threshold (the profiler's overall count). Only when that number moves does it go through the
-- addons, and the ones whose own count moved are the culprits. A frame no single addon made slow
-- (several shared it) is logged as such. Each entry keeps when and where it happened, so a stutter
-- in a boss fight can be looked up after the fight.

local Utils, L, P = ns.Utils, ns.L, ns.Profiler
local S = {}
ns.SpikeWatch = S

local INTERVAL = 2
-- A stutter this soon after a loading screen or combat still counts as part of it.
local LOADING_GRACE, COMBAT_GRACE = 3, INTERVAL

local profiler = C_AddOnProfiler
local GetAddOnMetric = profiler and profiler.GetAddOnMetric
local GetOverallMetric = profiler and profiler.GetOverallMetric
local GetTime, InCombatLockdown = GetTime, InCombatLockdown

S.context = { loading = false, loadingEnded = 0, combatEnded = 0, encounter = nil }
S.session = 0 -- entries logged since login
S.last = nil -- the latest entry

local ticker, seenOverall
local watched = {} -- the thresholds at and above the chosen one

local function Watched(ms)
	table.wipe(watched)
	for _, threshold in ipairs(P.THRESHOLDS) do
		if threshold >= ms then
			watched[#watched + 1] = threshold
		end
	end
end

-- Remembers an addon's counts as they are, so only what comes after is news.
function S.PrimeEntry(entry)
	if not P.Enabled() then
		return
	end
	local seen = entry.seen or {}
	for _, threshold in ipairs(watched) do
		seen[threshold] = GetAddOnMetric(entry.name, P.COUNT[threshold]) or 0
	end
	entry.seen = seen
	entry.seenPeak = GetAddOnMetric(entry.name, P.Metric.PeakTime) or 0
end

function S.Prime()
	Watched(P.spikeMs)
	seenOverall = P.Enabled() and Utils.Number(GetOverallMetric(P.COUNT[P.spikeMs])) or 0
	for _, entry in ipairs(P.list) do
		S.PrimeEntry(entry)
	end
end

ns.On("ADDON_ADDED", function(entry)
	if ticker then
		S.PrimeEntry(entry)
	end
end)

-- --- describing entries -------------------------------------------------------------------------

local function Zone()
	local name, instanceType, difficultyID, difficultyName = Utils.Call(GetInstanceInfo)
	if type(name) == "string" and instanceType and instanceType ~= "none" then
		if difficultyID == 8 and C_ChallengeMode then
			local level = Utils.Number(Utils.Call(C_ChallengeMode.GetActiveKeystoneInfo))
			if level and level > 0 then
				return string.format("%s +%d", name, level)
			end
		end
		if type(difficultyName) == "string" and difficultyName ~= "" then
			return string.format("%s (%s)", name, difficultyName)
		end
		return name
	end
	local zone = Utils.Call(GetRealZoneText)
	return type(zone) == "string" and zone ~= "" and zone or nil
end

function S.Who(item)
	return item.addon or L["Several addons together"]
end

-- "112 ms", or "over 50 ms" when only the bucket is known; "x3" when several frames.
function S.HowBad(item)
	local text = item.ms and Utils.Ms(item.ms) or string.format(L["over %d ms"], item.over or 50)
	if item.frames then
		text = text .. " x" .. item.frames
	end
	return text
end

function S.State(item)
	if item.loading then
		return L["Loading screen"]
	elseif item.boss then
		return string.format(L["Boss: %s"], item.boss)
	elseif item.combat then
		return L["In combat"]
	end
	return L["Out of combat"]
end

-- One line for chat.
function S.Describe(item)
	local where = item.zone and (", " .. item.zone) or ""
	return string.format(L["Slow frame: %s, %s (%s%s)"], S.Who(item), S.HowBad(item), S.State(item):lower(), where)
end

-- --- watching -----------------------------------------------------------------------------------

local function Record(entry, frames, worst, exact)
	local context = S.context
	local now = GetTime()
	local loading = context.loading or now - context.loadingEnded < LOADING_GRACE
	if loading and ns.db.spikeSkipLoading then
		return
	end
	local item = {
		t = time(),
		addon = entry and entry.title or nil,
		folder = entry and entry.name or nil,
		frames = frames > 1 and frames or nil,
		over = worst,
		ms = exact and math.floor(exact + 0.5) or nil,
		zone = Zone(),
		boss = context.encounter,
		combat = (InCombatLockdown() or now - context.combatEnded < COMBAT_GRACE) and true or nil,
		loading = loading or nil,
	}
	local log = ns.db.spikeLog
	log[#log + 1] = item
	while #log > ns.db.spikeKeep do
		table.remove(log, 1)
	end
	S.session = S.session + 1
	S.last = item
	if ns.db.spikeChat then
		Utils.Print(S.Describe(item))
	end
	ns.Fire("SPIKE", item)
end

-- The overall count moved: whose own count moved with it?
local function Attribute(frames)
	local ms = P.spikeMs
	local metric = P.COUNT[ms]
	local found = false
	local list = P.list
	for i = 1, #list do
		local entry = list[i]
		local seen = entry.seen
		if seen then
			local count = GetAddOnMetric(entry.name, metric)
			local before = seen[ms] or 0
			if count > before then
				seen[ms] = count
				-- How bad: the highest threshold it newly crossed, and its peak if that rose (then the
				-- peak is this stutter's exact length).
				local worst = ms
				for w = 2, #watched do
					local threshold = watched[w]
					local higher = GetAddOnMetric(entry.name, P.COUNT[threshold])
					if higher > (seen[threshold] or 0) then
						worst = threshold
					end
					seen[threshold] = higher
				end
				local peak = GetAddOnMetric(entry.name, P.Metric.PeakTime) or 0
				local exact = peak > (entry.seenPeak or 0) and peak or nil
				entry.seenPeak = peak
				Record(entry, count - before, worst, exact)
				found = true
			end
		end
	end
	if not found then
		Record(nil, frames, ms, nil)
	end
end

function S.Check()
	if not P.Enabled() then
		return
	end
	local overall = Utils.Number(GetOverallMetric(P.COUNT[P.spikeMs]))
	if not overall then
		return
	end
	if overall > seenOverall then
		local frames = overall - seenOverall
		seenOverall = overall
		Attribute(frames)
	else
		seenOverall = overall
	end
end

-- Starts or stops the watch as the settings say.
function S.Apply()
	if ns.db.spikeWatch and P.Enabled() then
		if not ticker then
			S.Prime()
			ticker = C_Timer.NewTicker(INTERVAL, Utils.Protect("slow frame watch", S.Check))
		end
	elseif ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function S.Watching()
	return ticker ~= nil
end

-- A new threshold: what counts as news starts over.
function S.OnThresholdChanged()
	if ticker then
		S.Prime()
	end
end

function S.Clear()
	table.wipe(ns.db.spikeLog)
	S.last = nil
	ns.Fire("SPIKE")
end

-- The latest entry (from this session or one before).
function S.Latest()
	local log = ns.db and ns.db.spikeLog
	return S.last or (log and log[#log])
end
