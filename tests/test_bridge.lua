------------------------------------------------------------
-- test_bridge.lua - Wildly on top of LibGroupBuffs-1.0.
--
-- The compat layer, the engine and the window live in the shared library,
-- with their own tests there. What is checked here is the join: that Wildly
-- really uses the library, refuses one that is missing, broken or too old,
-- and reports rejected events in chat, which is the one behaviour it owns.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bridge.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
H.loadLibrary()
dofile("WildlyCompat.lua")
local API = Wildly.API

------------------------------------------------------------
-- Wildly.API IS the library's API - not a copy of it
------------------------------------------------------------

local lib = LibStub("LibGroupBuffs-1.0")
H.check(lib ~= nil, "LibGroupBuffs-1.0 is loaded")
H.check(API == lib.API, "Wildly.API is the library's API table itself")
H.check(Wildly.Settings == lib.Settings, "and Wildly.Settings its Settings")
H.check(Wildly.Engine == lib.Engine, "and Wildly.Engine its Engine")
H.check(Wildly.UI == lib.UI, "and Wildly.UI its UI")

------------------------------------------------------------
-- The rules every ported file keeps, read from the source
--
-- Files the port has not reached yet are the TBC code and break these rules
-- by construction, so they are skipped: H.NOT_YET_PORTED, shared with
-- loadAddon. Each slice that ports a file removes it from that list; the
-- check below fails while an entry names a file that no longer carries TBC
-- code, so the list cannot quietly outlive the port.
------------------------------------------------------------

local NOT_YET_PORTED = H.NOT_YET_PORTED

local SOURCES = {}
for _, file in ipairs(H.tocFiles()) do
    local text = H.readFile(file)
    H.check(text ~= nil, "the TOC lists " .. file .. ", which exists")
    if NOT_YET_PORTED[file] then
        -- Still the TBC code if it has not started using the library: a
        -- ported file reads Wildly.API, even just to stop without it.
        H.check(text and not text:find("Wildly.API", 1, true),
            file .. " is listed as not yet ported (" .. NOT_YET_PORTED[file]
            .. ") and is still the TBC code - drop it from NOT_YET_PORTED once it is ported")
    else
        local code = {}
        for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
            code[#code + 1] = (line:gsub("%-%-.*$", ""))
        end
        SOURCES[file] = code
    end
end
H.check(SOURCES["WildlyCompat.lua"] ~= nil, "the bridge itself is scanned")

-- Every API function a ported file calls exists in the library: the point of
-- the library is one copy, and a missing one only fails in game.
for file, lines in pairs(SOURCES) do
    for _, code in ipairs(lines) do
        for name in code:gmatch("%f[%w_]API%.([%a_][%w_]*)") do
            local want = (name == "eventFailures" or name == "eventFailuresByOwner") and "table" or "function"
            H.check(type(API[name]) == want, file .. " uses API." .. name .. ", so the library must provide it")
        end
    end
end

-- No library function copied into a local. API is shared by every addon that
-- embeds the library, and a newer copy upgrades it in place: `local F = API.F`
-- taken at load time keeps running the old version. Call through API, or
-- wrap: `local function F(...) return API.F(...) end`.
local captures = {}
for file, lines in pairs(SOURCES) do
    for n, code in ipairs(lines) do
        -- Qualified too: `lib.API.F` and `Wildly.API.F` are the same copy.
        if code:find("=%s*[%w_%.]-%f[%w_]API%.[%a_][%w_]*%s*$")
            or code:find("=%s*[%w_%.]-%f[%w_]API%.[%a_][%w_]*%s*;") then
            captures[#captures + 1] = file .. ":" .. n .. "  " .. code
        end
    end
end
H.eq(#captures, 0, "no file copies a library function into a local: " .. table.concat(captures, " | "))

-- Events only through Wildly.RegisterEvents. A bare frame:RegisterEvent
-- throws on an unknown name or returns false, and the library's own
-- registration prints nothing, so either can leave a handler silently dead.
local direct = {}
for file, lines in pairs(SOURCES) do
    for n, code in ipairs(lines) do
        -- WildlyCompat.lua holds the wrapper itself, the one allowed caller.
        if file ~= "WildlyCompat.lua" and (code:find("%f[%w_]API%.RegisterEvents%w*%s*%(")
                                           or code:find(":RegisterEvent%s*%(")) then
            direct[#direct + 1] = file .. ":" .. n .. "  " .. code
        end
    end
end
H.eq(#direct, 0, "nothing registers events except through Wildly.RegisterEvents: " .. table.concat(direct, " | "))

------------------------------------------------------------
-- Rejected events are reported in chat
--
-- The library returns them instead of printing, because it must not write to
-- another addon's chat frame. A silently missing handler is worse than a
-- noisy one, so Wildly prints them.
------------------------------------------------------------

WoW.reset()
local f = CreateFrame("Frame")
local before = #WoW.messages
local ok, failed = Wildly.RegisterEvents(f, "PLAYER_LOGIN", "UNIT_AURA")
H.eq(ok, true, "known events register cleanly")
H.eq(#WoW.messages, before, "and print nothing")

WoW.badEvents.NOT_A_REAL_EVENT = true
before = #WoW.messages
ok, failed = Wildly.RegisterEvents(f, "UNIT_PET", "NOT_A_REAL_EVENT")
H.eq(ok, false, "a rejected event name is reported")
H.check(WoW.events[f].UNIT_PET == true, "the good event still registered")
H.eq(failed and failed[1], "NOT_A_REAL_EVENT", "the caller gets the rejected name")
local said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("NOT_A_REAL_EVENT", 1, true), "and it is printed, not silent: " .. said)
H.check(Wildly.eventFailures.NOT_A_REAL_EVENT ~= nil,
    "and recorded in Wildly's own table - the library's is shared by every addon")
H.check(API.eventFailuresByOwner.Wildly.NOT_A_REAL_EVENT ~= nil,
    "and in the library under Wildly's name")

-- The client can also refuse by returning false; that must be just as loud.
WoW.refusedEvents.REFUSED_EVENT = true
before = #WoW.messages
ok, failed = Wildly.RegisterEvents(f, "REFUSED_EVENT")
H.eq(ok, false, "a false return is a rejection too")
said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("REFUSED_EVENT", 1, true), "and it is printed: " .. said)

------------------------------------------------------------
-- A missing library stops loading, with a message that says why
--
-- No fallback copy: running on a stale duplicate is the drift this removes.
------------------------------------------------------------

local savedLibStub, savedWildly = LibStub, Wildly

local function loadWithout(libStubValue)
    LibStub = libStubValue
    Wildly = nil
    local before = #WoW.messages
    local loaded, err = pcall(dofile, "WildlyCompat.lua")
    local chat = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
    return loaded, tostring(err), chat
end

local loaded, err, chat = loadWithout(nil)
H.check(not loaded, "WildlyCompat refuses to load without the library")
H.check(err:find("Libs\\LibGroupBuffs-1.0", 1, true),
    "the error names the real folder, backslash intact: " .. err)
-- Lua errors are hidden by default on this client, so the error alone would
-- leave a player looking at an addon that silently does nothing.
H.check(chat:find("cannot start", 1, true) and chat:find("missing", 1, true),
    "and a player is told in chat, where they will see it: " .. chat)

-- A library that threw partway through its compat layer: registered, but
-- without the functions defined after the error.
local halfLoaded = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end } }
end })
loaded, err, chat = loadWithout(halfLoaded)
H.check(not loaded, "a library that failed to load completely is refused too")
H.check(chat:find("completely", 1, true), "and reported as that, not as missing: " .. chat)

-- Each case below is a library that is complete except for ONE piece, and
-- newer than the floor, so that piece is the only reason it can be refused.
-- (A fake with no MINOR at all is refused by the first check whatever else is
-- wrong with it, and proves nothing about the rest.)
local function shaped(minor, markers, drop)
    local l = { API = { RegisterEventsReported = function() return true end,
                        ClickEdges = function() end },
                Settings = { New = function() end }, Engine = { New = function() end },
                UI = { New = function() end } }
    for k, v in pairs(markers) do l[k] = v end
    if drop then drop(l) end
    return setmetatable({}, { __call = function() return l, minor end })
end
local function markers(n)
    return { compatMinor = n, settingsMinor = n, engineMinor = n, uiMinor = n }
end

loaded = loadWithout(shaped(12, markers(12)))
H.check(loaded, "a complete library newer than the floor is accepted - the baseline for the cases below")

local MISSING_PIECES = {
    { "Settings",  function(l) l.Settings = nil end },
    { "Settings.New", function(l) l.Settings.New = nil end },
    { "Engine",    function(l) l.Engine = nil end },
    { "Engine.New", function(l) l.Engine.New = nil end },
    { "UI",        function(l) l.UI = nil end },
    { "UI.New",    function(l) l.UI.New = nil end },
    { "API.RegisterEventsReported", function(l) l.API.RegisterEventsReported = nil end },
    { "API.ClickEdges", function(l) l.API.ClickEdges = nil end },
    -- A file that threw before its last line: its marker never ran.
    { "compatMinor", function(l) l.compatMinor = nil end },
    { "settingsMinor", function(l) l.settingsMinor = nil end },
    { "engineMinor", function(l) l.engineMinor = nil end },
    { "uiMinor",   function(l) l.uiMinor = nil end },
}
for _, case in ipairs(MISSING_PIECES) do
    loaded, err, chat = loadWithout(shaped(12, markers(12), case[2]))
    H.check(not loaded, "a library without " .. case[1] .. " is refused")
    H.check(chat:find("completely", 1, true), "as one that failed to load completely: " .. chat)
end

-- Another addon loaded a newer copy first, and one of its files threw
-- partway: LibStub reports that newer MINOR, but that file's marker is still
-- the older copy's, over a half-replaced table. Present is not enough - it has
-- to be the ACTIVE copy's.
for _, key in ipairs({ "compatMinor", "settingsMinor", "engineMinor", "uiMinor" }) do
    local m = markers(12)
    m[key] = 11
    loaded, err, chat = loadWithout(shaped(12, m))
    H.check(not loaded, "an older copy's " .. key .. " under a newer MINOR is refused")
    H.check(chat:find("completely", 1, true), "as a library that failed to load completely: " .. chat)
end

-- A complete, self-consistent copy that is simply too old: one MINOR behind
-- what this build needs (NEEDS_MINOR). Behaviour is what separates them - r11
-- lets Wildly colour the popover divider, which r10 would quietly draw in
-- Priestly's blue - and behaviour cannot be feature-detected, so the floor is
-- a version check. Nothing crashed, so the message must not say it did.
loaded, err, chat = loadWithout(shaped(10, markers(10)))
H.check(not loaded, "a complete library older than the one this build needs is refused")
H.check(chat:find("r10", 1, true) and chat:find("r11", 1, true),
    "the message names the version in use and the one needed: " .. chat)
H.check(not chat:find("completely", 1, true), "and does not claim a failed load: " .. chat)
loaded = loadWithout(shaped(11, markers(11)))
H.check(loaded, "exactly the floor is enough")

-- The ported files stop before building anything when the bridge refused the
-- library, so a missing library is one message rather than a cascade of
-- errors and half-made frames.
Wildly = {}
local frames = 0
local realCreateFrame = CreateFrame
CreateFrame = function(...) frames = frames + 1 return realCreateFrame(...) end
local stopped = 0
for _, file in ipairs(H.tocFiles()) do
    if file ~= "WildlyCompat.lua" and not NOT_YET_PORTED[file] then
        local ok, why = pcall(dofile, file)
        H.check(ok, file .. " returns quietly when Wildly.API is missing: " .. tostring(why))
        stopped = stopped + 1
    end
end
H.check(stopped >= 1, "at least one ported file was checked")
H.eq(frames, 0, "and creates no frames")
CreateFrame = realCreateFrame

LibStub, Wildly = savedLibStub, savedWildly

H.done("test_bridge")
