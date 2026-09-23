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

-- An older copy that loaded completely but predates Settings (r3) or Engine
-- (r4): refused at the door, not as a nil call when Wildly builds them.
local r3Shaped = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end } }
end })
loaded, err, chat = loadWithout(r3Shaped)
H.check(not loaded, "a library without Settings is refused")
H.check(chat:find("completely", 1, true), "with the same message: " .. chat)

local r4Shaped = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end },
             Settings = { New = function() end } }
end })
loaded, err, chat = loadWithout(r4Shaped)
H.check(not loaded, "a library without Engine is refused")
H.check(chat:find("completely", 1, true), "with the same message: " .. chat)

-- Engine.lua threw after defining Engine.New but before its methods, so its
-- last line - the engineMinor marker - never ran. Accepting it would fail
-- later as "attempt to call method 'GroupStat' (a nil value)" mid-refresh.
local halfEngine = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end },
             Settings = { New = function() end }, settingsMinor = 5,
             Engine = { New = function() end } }
end })
loaded, err, chat = loadWithout(halfEngine)
H.check(not loaded, "an Engine.lua that did not load to the end is refused")
H.check(chat:find("completely", 1, true), "with the same message: " .. chat)

local halfSettings = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end },
             Settings = { New = function() end },
             Engine = { New = function() end }, engineMinor = 5 }
end })
loaded, err, chat = loadWithout(halfSettings)
H.check(not loaded, "and so is a Settings.lua that did not")

-- A complete library, as LibStub reports it: its markers equal its MINOR.
local function shaped(minor, markers)
    local l = { API = { RegisterEventsReported = function() return true end,
                        ClickEdges = function() end },
                Settings = { New = function() end }, Engine = { New = function() end },
                UI = { New = function() end } }
    for k, v in pairs(markers) do l[k] = v end
    return setmetatable({}, { __call = function() return l, minor end })
end
local ALL11 = { compatMinor = 11, settingsMinor = 11, engineMinor = 11, uiMinor = 11 }
loaded = loadWithout(shaped(11, ALL11))
H.check(loaded, "a library whose every marker equals its MINOR is accepted")

-- A complete, self-consistent copy that is simply too old: one MINOR behind
-- what this build needs (NEEDS_MINOR). Behaviour is what separates them -
-- r11 lets Wildly colour the popover divider, which r10 would quietly draw
-- in Priestly's blue - and behaviour cannot be feature-detected, so the
-- floor is a version check.
loaded, err, chat = loadWithout(shaped(10,
    { compatMinor = 10, settingsMinor = 10, engineMinor = 10, uiMinor = 10 }))
H.check(not loaded, "a complete library older than the one this build needs is refused")
H.check(chat:find("completely", 1, true), "with the reinstall message: " .. chat)

-- Another addon loaded a newer copy first, and its UI.lua threw partway:
-- LibStub reports that newer MINOR, but uiMinor is still the older copy's,
-- over a half-replaced UI. Present is not enough - it has to be the ACTIVE
-- copy's.
-- These copies are newer than the floor, so the markers are the only thing
-- that can refuse them.
loaded, err, chat = loadWithout(shaped(12,
    { compatMinor = 12, settingsMinor = 12, engineMinor = 12, uiMinor = 11 }))
H.check(not loaded, "a marker left by an older copy is refused")
H.check(chat:find("completely", 1, true), "as a library that failed to load completely: " .. chat)
loaded = loadWithout(shaped(12, { compatMinor = 11, settingsMinor = 12, engineMinor = 12, uiMinor = 12 }))
H.check(not loaded, "including Compat.lua's own marker")
loaded = loadWithout(shaped(12, { settingsMinor = 12, engineMinor = 12, uiMinor = 12 }))
H.check(not loaded, "and a Compat.lua that never reached its last line")

LibStub, Wildly = savedLibStub, savedWildly

H.done("test_bridge")
