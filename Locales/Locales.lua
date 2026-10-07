local _, ns = ...

-- The first file the game loads (see the TOC): /lad perf times loading from here.
ns.loadStarted = type(debugprofilestop) == "function" and debugprofilestop() or nil

-- Translations. The addon's text is written in English and looked up through ns.L: L["Settings"] is
-- the game language's text, or the English itself when there is no translation for it. A language
-- file calls ns.Locale.Register("deDE", { ["Settings"] = "Einstellungen", ... }) and is listed in the
-- TOC after this file.
local active = {}

ns.L = setmetatable({}, {
	__index = function(_, text)
		return active[text] or text
	end,
})

ns.Locale = {}

local SAME_AS = { enGB = "enUS" }

function ns.Locale.Current()
	local code = type(GetLocale) == "function" and GetLocale() or "enUS"
	return SAME_AS[code] or code
end

function ns.Locale.Register(code, strings)
	if code == ns.Locale.Current() and type(strings) == "table" then
		active = strings
	end
end
