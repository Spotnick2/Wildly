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

-- What the bridge does with each answer.
--
-- Which copies are usable is the library's question now: lib.Status walks its
-- own list of files and says "ok", "incomplete" or "too-old", and the "complete
-- except one piece" cases are tested there (LibGroupBuffs r12). Wildly's job
-- is to react - refuse, and say the right thing to the player - and that is
-- all this file tests.
local FLOOR = tonumber((H.readFile("WildlyCompat.lua") or ""):match("NEEDS_MINOR%s*=%s*(%d+)"))
-- Every case below is relative to the floor, so without it there is nothing
-- to test - stop here rather than on arithmetic with nil.
if not FLOOR then error("test_bridge: no NEEDS_MINOR found in WildlyCompat.lua") end

-- A fake library whose Status gives a set answer. `status` may also be a
-- function, standing in for Status itself. Records the floor it was asked
-- about, in askedFloor.
local askedFloor
local function answering(status, minor)
    local l = { API = { RegisterEventsReported = function() return true end,
                        ClickEdges = function() end },
                Settings = { New = function() end }, Engine = { New = function() end },
                UI = { New = function() end } }
    if type(status) == "function" then
        l.Status = status
    elseif status then
        l.Status = function(needs) askedFloor = needs return status, minor end
    end
    return setmetatable({}, { __call = function() return l, minor end })
end

askedFloor = nil
loaded = loadWithout(answering("ok", FLOOR))
H.check(loaded, "a library that says it is ok is accepted")
-- Without the floor, Status never answers too-old, and the next bump of
-- NEEDS_MINOR would quietly accept an older copy.
H.eq(askedFloor, FLOOR, "and it was asked about this build's floor")

-- Status is library code on a shared table. If it throws, the player must
-- still be told, not left with an addon that silently does nothing.
loaded, err, chat = loadWithout(answering(function() error("half-built") end, FLOOR))
H.check(not loaded, "a library whose Status throws is refused")
H.check(chat:find("cannot start", 1, true) and chat:find("completely", 1, true),
    "and the player is told, as a failed load: " .. chat)

loaded, err, chat = loadWithout(answering("incomplete", FLOOR))
H.check(not loaded, "one that says it is incomplete is refused")
H.check(chat:find("completely", 1, true), "as a failed load: " .. chat)

-- Complete, just too old. Nothing crashed, so the message must not say it
-- did, and must name both versions.
loaded, err, chat = loadWithout(answering("too-old", FLOOR - 1))
H.check(not loaded, "and one that says it is too old")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and chat:find("r" .. FLOOR, 1, true),
    "naming the version in use and the one needed: " .. chat)
H.check(not chat:find("completely", 1, true), "without claiming a failed load: " .. chat)

-- A copy too old to have Status at all. Its absence is the answer, and which
-- answer depends on the version: behind the floor is too-old, at or above it
-- means the file that installs Status threw.
loaded, err, chat = loadWithout(answering(nil, FLOOR - 1))
H.check(not loaded, "a copy without Status, below the floor, is refused")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and not chat:find("completely", 1, true),
    "as too old rather than broken: " .. chat)

loaded, err, chat = loadWithout(answering(nil, FLOOR))
H.check(not loaded, "a copy without Status at the floor is refused too")
H.check(chat:find("completely", 1, true),
    "as a failed load, because the file that installs Status is the last one: " .. chat)

------------------------------------------------------------
-- The real load order: an older copy loaded first is UPGRADED, not refused
--
-- The fakes above call the bridge directly, which is not how the game gets
-- here. Wildly's TOC loads its own copy of the library BEFORE this file, so
-- another addon's older copy has already been upgraded by LibStub when the
-- bridge runs - and the real Status has to say "ok" over what the older copy
-- left on the shared table.
------------------------------------------------------------

do
    local root = H.libraryRoot()
    local older = {}
    for _, name in ipairs({ "Compat", "Settings", "Engine", "UI" }) do
        older[#older + 1] = root .. "/tests/fixtures/" .. name .. "-r" .. (FLOOR - 1) .. ".lua"
    end
    local haveFixtures = true
    for _, path in ipairs(older) do
        local f = io.open(path, "r")
        if f then f:close() else haveFixtures = false end
    end
    H.check(haveFixtures, "the library checkout carries its r" .. (FLOOR - 1) .. " fixtures to load first")

    if haveFixtures then
        Wildly = nil
        -- A LibStub with nothing registered, the way a session starts.
        local stub = loadfile(root .. "/LibStub/LibStub.lua")
        LibStub = nil
        stub()

        for _, path in ipairs(older) do loadfile(path)() end
        local _, before = LibStub:GetLibrary("LibGroupBuffs-1.0")
        H.eq(before, FLOOR - 1, "another addon's older copy registered first")

        -- Now Wildly's own, as its TOC does.
        local L = dofile("tests/libfiles.lua")
        for _, file in ipairs(L.resolve(root)) do loadfile(root .. "/" .. file)() end
        local _, after = LibStub:GetLibrary("LibGroupBuffs-1.0")
        H.check(after > before, "and Wildly's copy upgrades it to r" .. tostring(after))

        local said = #WoW.messages
        local ok, why = pcall(dofile, "WildlyCompat.lua")
        H.check(ok, "so the bridge accepts it, despite the older copy having loaded first: " .. tostring(why))
        H.eq(#WoW.messages, said, "and says nothing to the player")
        H.check(Wildly and Wildly.API ~= nil, "with the upgraded library in place")
    end

    LibStub, Wildly = savedLibStub, savedWildly
end

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
