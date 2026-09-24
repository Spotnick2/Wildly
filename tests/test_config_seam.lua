------------------------------------------------------------
-- test_config_seam.lua - one write path for WildlyDB, and the two checks
-- that watch for the client being fixed or updated.
--
-- Nothing an addon writes survives a real restart on this build. Until
-- Blizzard fixes it, every settings change goes through Wildly_SetConfig so
-- the fix - or the migration it needs - lands in one place.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config_seam.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, TC = H.loadAddon()

-- Pinned here as LITERALS, not read from the source. Every check below takes
-- its builds from the constants, so a stale constant satisfies all of them
-- while the addon warns at every real login on the build people are actually
-- running - and, worse, treats that build as one where saved settings work,
-- so a relog to character select can announce a fix that never happened.
-- Moving the client forward has to be a two-file edit, and this is the file
-- that says so.
local MEASURED = "69977"
local BROKEN = "69977"
local FIXED = "70123"   -- any build other than the two above

H.eq(TC.MEASURED_ON_BUILD, MEASURED,
    "the source says Wildly was measured on the build these tests measure it on")
H.eq(TC.SV_BROKEN_ON_BUILD, BROKEN,
    "and on the build where saved settings are known not to come back")

------------------------------------------------------------
-- The setters
------------------------------------------------------------

WoW.reset()
WildlyDB = nil
Wildly_EnsureDefaults()

local changed = {}
local realHook = Wildly_OnConfigChanged
Wildly_OnConfigChanged = function(key) changed[#changed + 1] = key end

Wildly_SetConfig("frameAlpha", 0.5)
H.eq(WildlyDB.frameAlpha, 0.5, "SetConfig assigns")
H.eq(changed[#changed], "frameAlpha", "and reports the key")

-- Set first, so clearing it is an actual change the test can see fail.
Wildly_SetConfig("pos", { point = "RIGHT", x = 1, y = 2 })
H.check(WildlyDB.pos ~= nil, "a position is stored")
Wildly_SetConfig("pos", nil)
H.eq(WildlyDB.pos, nil, "SetConfig can clear a key that was set")
H.eq(changed[#changed], "pos", "and reports the clear")

-- An unchanged value is not a change. The window sets `visible` on every
-- refresh; without this the hook runs on the aura hot path.
local count = #changed
Wildly_SetConfig("frameAlpha", 0.5)
H.eq(#changed, count, "setting the same value again does not report")

-- The learned-duration cache. Reading never writes - the engine asks on the
-- aura hot path - so a table left by another build answers nothing and stays
-- as it is until something is learned on this one. Then it is replaced once,
-- and that one write is reported once.
local stale = { build = "old", ["Mark of the Wild"] = 1800 }
WildlyDB.learnedDurations = stale
count = #changed
H.eq(Wildly_GetLearnedDuration("Mark of the Wild"), nil, "another build's duration is not used")
H.eq(#changed, count, "and reading it reports nothing")
H.check(WildlyDB.learnedDurations == stale, "and writes nothing")
Wildly_LearnDuration("Mark of the Wild", 1200)
H.check(WildlyDB.learnedDurations ~= stale, "learning on this build replaces the table")
H.eq(#changed, count + 1, "reported exactly once for the replacement and the value together")
H.eq(changed[#changed], "learnedDurations", "under the table's key")
count = #changed
Wildly_LearnDuration("Mark of the Wild", 1200)
H.eq(#changed, count, "re-learning the same value is not a change")
Wildly_LearnDuration("Mark of the Wild", 900)
H.eq(#changed, count + 1, "a new value is")

-- EnsureDefaults' own writes reach the hook too: it is where the SavedVariables
-- fix or a migration lands, and a value it never heard about would never reach
-- a new store.
WildlyDB = {}
count = #changed
Wildly_EnsureDefaults()
local seeded = {}
for i = count + 1, #changed do seeded[changed[i]] = true end
for key in pairs(TC.DEFAULTS) do
    H.check(seeded[key], "seeding " .. key .. " is reported")
end
count = #changed
Wildly_EnsureDefaults()
H.eq(#changed, count, "a second run seeds nothing and reports nothing")
WildlyDB.thornsMode = "raid leaders"
Wildly_EnsureDefaults()
H.eq(changed[#changed], "thornsMode", "repairing an unknown Thorns mode is reported")
H.eq(#changed, count + 1, "and only that")

WildlyDB = nil
Wildly_SetConfig("lockFrame", true)
H.eq(WildlyDB and WildlyDB.lockFrame, true, "SetConfig survives a missing table")

Wildly_OnConfigChanged = realHook

------------------------------------------------------------
-- The source scan
--
-- A behavioural test cannot catch a new direct write: it works perfectly well.
-- So every file the TOC loads is read, and any assignment into Wildly's
-- saved tables outside a `config-owner` region fails the run.
--
-- The scanner is LibGroupBuffs' tests/config_scan.lua, loaded from the same
-- library checkout the rest of the suite runs against (CI clones the pinned
-- tag). Its own tests cover the shapes it must catch; the cases here only
-- prove it is wired to Wildly's names.
--
-- Files the port has not reached (H.NOT_YET_PORTED) are skipped: the TBC
-- Wildly.lua writes WildlyDB directly throughout, and slice 3 replaces it.
------------------------------------------------------------

local SAVED = { "WildlyDB", "WildlySVCheck" }
local CS = dofile(H.libraryRoot() .. "/tests/config_scan.lua")

H.eq(#CS.Scan("synthetic", "WildlyDB.lockFrame = true", SAVED), 1,
    "the scanner catches a direct WildlyDB write")
H.eq(#CS.Scan("synthetic", "WildlySVCheck.svLoadCheck = {}", SAVED), 1,
    "and a direct WildlySVCheck write")
H.eq(#CS.Scan("synthetic", "local p = WildlyDB.pos", SAVED), 0, "but not a read")

-- Every file the TOC loads, read from the TOC so a new one cannot be missed.
local files = {}
for _, path in ipairs(H.tocFiles()) do
    if not H.NOT_YET_PORTED[path] then files[#files + 1] = path end
end
H.check(#files >= 2, "the ported files are scanned: " .. table.concat(files, ", "))

-- Owner regions must stay few, or the scan stops meaning anything. Each file's
-- count is pinned, so adding one has to be done here on purpose.
local expectedRegions = { ["WildlyConfig.lua"] = 3 }
for _, path in ipairs(files) do
    local src = H.readFile(path)
    H.check(src ~= nil, path .. " is readable")
    local bad, regions = CS.Scan(path, src or "", SAVED)
    H.check(#bad == 0, path .. " writes its saved tables only through the setters: " ..
        table.concat(bad, " | "))
    H.eq(regions, expectedRegions[path] or 0, path .. " has the expected owner regions "
        .. "(WildlyConfig: the saved-table accessors, EnsureDefaults, the duration cache)")
end

------------------------------------------------------------
-- Wildly is class-specific
--
-- On any other class it registers no options page, creates no saved table and
-- says nothing in chat: a build notice from an addon that does nothing on this
-- character is noise.
------------------------------------------------------------

WoW.reset()
WoW.build = "70123"                 -- not the measured build: a Druid would be warned
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "MAGE" })
WildlyDB, WildlySVCheck = nil, nil
local panelFrame = _G["WildlyOptionsPanel"]
panelFrame._category = nil
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.eq(#WoW.messages, 0, "a Mage hears nothing from Wildly: " .. table.concat(WoW.messages, " | "))
H.eq(WildlyDB, nil, "gets no saved table")
H.eq(WildlySVCheck, nil, "in either scope")
H.eq(panelFrame._category, nil, "and no options page")
H.eq(Wildly_IsBuffEnabled("mark"), true, "while the accessors still answer without a table")

WoW.SetUnit("player", { name = "Karuzo Elegia", class = "DRUID" })
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(WildlyDB ~= nil, "a Druid gets the saved table")
H.check(panelFrame._category ~= nil, "and the options page")
H.check(table.concat(WoW.messages, " "):find("tested on", 1, true) ~= nil,
    "and the build notice on a build Wildly was not measured on")

------------------------------------------------------------
-- svLoadCheck: has Blizzard fixed it?
------------------------------------------------------------

H.eq(TC.DEFAULTS.svLoadCheck, nil,
    "svLoadCheck is NOT in DEFAULTS - if it were, EnsureDefaults would recreate it " ..
    "every session and the check could never tell a real load from a fresh start")

local function said(fromIndex)
    if #WoW.messages <= fromIndex then return "" end
    return table.concat(WoW.messages, " | ", fromIndex + 1, #WoW.messages)
end

local function freshSession(build)
    WoW.reset()
    WoW.build = build
    WildlyDB, WildlySVCheck = nil, nil
    Wildly_EnsureDefaults()
end

-- Today, broken build, nothing loaded: nothing announced, markers written.
freshSession(BROKEN)
local before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
H.eq(said(before), "", "no marker at login, nothing announced - today's state")
H.check(type(WildlyDB.svLoadCheck) == "table", "the per-character marker is written")
H.check(type(WildlySVCheck.svLoadCheck) == "table", "and the account-wide one")
H.eq(WildlyDB.svLoadCheck.build, BROKEN, "with the build it was written on")

-- The broken build, marker still in memory: that is a relog or a /reload
-- being served from the client's cache. Neither may announce.
before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
H.eq(said(before), "",
    "on the broken build a returning marker is the client's cache, not a fix")
Wildly_HandleEnteringWorld(false, true)
H.eq(said(before), "", "and a /reload never announces")

-- A zone change is neither, and must not touch the marker.
local marker = WildlyDB.svLoadCheck
Wildly_HandleEnteringWorld(false, false)
H.check(WildlyDB.svLoadCheck == marker, "a zone change leaves the marker alone")

-- The fix: a new build, and the marker came back on a real login.
WoW.build = FIXED
before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
local msg = said(before)
H.check(msg:find("came back", 1, true), "a real login on a new build announces it: " .. msg)
H.check(msg:find("fully exited", 1, true), "conditional on a full exit: " .. msg)
H.check(msg:find("proves nothing", 1, true), "and says a relog or /reload proves nothing: " .. msg)
H.check(msg:find("per-character", 1, true) and msg:find("account-wide", 1, true),
    "naming the scopes that came back: " .. msg)
H.check(msg:find(FIXED, 1, true), "and the build: " .. msg)

-- Once only: the latch persists by then, because the store works.
before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
H.check(not said(before):find("came back", 1, true), "it does not repeat at the next login")

-- Account-wide fixed on its own is worth knowing: it is where settings would
-- move back to.
freshSession(FIXED)
WildlySVCheck = { svLoadCheck = { stamp = "then", build = FIXED } }
before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find("account-wide", 1, true) and not msg:find("per-character", 1, true),
    "a fix to account-wide storage alone is reported as that: " .. msg)

-- Wired to the real event, not just callable.
freshSession(BROKEN)
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(type(WildlyDB.svLoadCheck) == "table", "PLAYER_ENTERING_WORLD drives the check")

------------------------------------------------------------
-- MEASURED_ON_BUILD: did the client update?
------------------------------------------------------------

freshSession(MEASURED)
before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
H.eq(said(before), "", "the measured build is silent")

freshSession(FIXED)
before = #WoW.messages
Wildly_HandleEnteringWorld(false, true)
H.check(not said(before):find("tested on", 1, true), "a /reload never shows the build warning")
before = #WoW.messages
WoW.dispatch("PLAYER_LOGIN")
H.check(not said(before):find("tested on", 1, true),
    "nor does PLAYER_LOGIN, which fires on /reload too")

before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find(FIXED, 1, true) and msg:find(MEASURED, 1, true),
    "a real login on a new build warns, naming both: " .. msg)
H.check(msg:find("report", 1, true), "worded for players: " .. msg)
H.check(not msg:find("MEASURED_ON_BUILD", 1, true),
    "with no developer instructions a player cannot act on: " .. msg)

-- Not latched: it repeats at every real login until MEASURED_ON_BUILD is
-- bumped. A notice shown once and missed would leave the addon running on
-- stale findings with nothing left to say so.
before = #WoW.messages
Wildly_HandleEnteringWorld(true, false)
H.check(said(before):find("tested on", 1, true),
    "it warns again at the next real login, until someone re-measures")
H.eq(WildlyDB.warnedBuild, nil, "and records nothing that could silence it")

H.done("test_config_seam")
