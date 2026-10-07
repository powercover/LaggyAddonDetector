local _, ns = ...

-- Memory: each addon's share, read with UpdateAddOnMemoryUsage, and the whole Lua heap.
--
-- UpdateAddOnMemoryUsage pauses the game while it counts, longer the more addons and memory there
-- are. So it runs only while the window is open, never in combat, and no more often than the
-- settings say; each scan is timed, and a slow one makes the next wait longer.
--
-- Growth is what makes the garbage collector run, and a collector step is what stutters, so growth
-- is shown rather than size alone. An addon's growth is the rise between two scans; when its memory
-- dropped instead, the collector ran in between and that interval says nothing, so it's skipped.

local Utils = ns.Utils
local M = {}
ns.Memory = M

local GetTime, debugprofilestop, InCombatLockdown = GetTime, debugprofilestop, InCombatLockdown
local UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = UpdateAddOnMemoryUsage, GetAddOnMemoryUsage
local collectgarbage = collectgarbage

M.backoff = 1 -- times the chosen interval
M.heap, M.heapGrowth, M.collections = 0, 0, 0

local SLOW_SCAN_MS, FAST_SCAN_MS, MAX_BACKOFF = 50, 20, 4

function M.Supported()
	return type(UpdateAddOnMemoryUsage) == "function" and type(GetAddOnMemoryUsage) == "function"
end

-- Scans every addon's memory now. Returns false when it can't (in combat, or no API).
function M.Scan()
	if not M.Supported() or InCombatLockdown() then
		return false
	end
	local started = debugprofilestop()
	UpdateAddOnMemoryUsage()
	local cost = debugprofilestop() - started
	local now = GetTime()
	local list = ns.Profiler.list
	for i = 1, #list do
		local entry = list[i]
		local kb = Utils.Number(GetAddOnMemoryUsage(entry.name)) or 0
		local at = entry.memoryAt
		if at and now > at then
			local delta = kb - entry.memory
			if delta >= 0 then
				local rate = delta / (now - at)
				entry.growth = entry.growthKnown and (entry.growth + rate) / 2 or rate
				entry.growthKnown = true
			end
		end
		entry.memory, entry.memoryAt = kb, now
	end
	M.lastCost, M.lastAt = cost, now
	if cost > SLOW_SCAN_MS then
		M.backoff = math.min(M.backoff * 2, MAX_BACKOFF)
	elseif cost < FAST_SCAN_MS then
		M.backoff = math.max(1, M.backoff / 2)
	end
	M.scans = (M.scans or 0) + 1
	return true
end

-- The interval between scans the window keeps to now, in seconds (nil: only when asked).
function M.Interval()
	local seconds = ns.db.memoryInterval
	if not seconds or seconds <= 0 then
		return nil
	end
	return seconds * M.backoff
end

-- Scans if the window's interval has passed.
function M.ScanIfDue()
	local interval = M.Interval()
	if interval and (not M.lastAt or GetTime() - M.lastAt >= interval) then
		return M.Scan()
	end
	return false
end

-- The whole Lua heap and how fast it grows: collectgarbage("count") is free, so this runs on every
-- tick of whatever is showing numbers. A drop is a finished collection, counted.
function M.SampleHeap()
	local kb = collectgarbage("count")
	local now = GetTime()
	local at = M.heapAt
	if not at then
		M.heap, M.heapAt = kb, now
		return
	end
	if now - at < 0.25 then
		return
	end
	local delta = kb - M.heap
	if delta >= 0 then
		local rate = delta / (now - at)
		M.heapGrowth = M.heapKnown and M.heapGrowth * 0.6 + rate * 0.4 or rate
		M.heapKnown = true
	else
		M.collections = M.collections + 1
		M.lastCollection = now
	end
	M.heap, M.heapAt = kb, now
end

-- An addon's memory after a fresh scan (the last known one in combat), for /lad perf.
function M.Of(name)
	M.Scan()
	local entry = ns.Profiler.byName[name]
	return entry and entry.memoryAt and entry.memory or nil
end
