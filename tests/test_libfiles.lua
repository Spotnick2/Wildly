------------------------------------------------------------
-- test_libfiles.lua - the one reader of the library's XML.
--
-- Its name is part of the test: libfiles.lua has a script mode, and it once
-- decided it was being run as a script whenever the running file's name
-- ENDED in "libfiles.lua" - which this file's does. It then printed its usage
-- and exited before any test ran. Reaching H.done at all is the first check.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_libfiles.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local L = dofile("tests/libfiles.lua")

H.check(type(L.resolve) == "function", "loaded as a module, not run as a script")

local load, ship = L.resolve(H.libraryRoot())
local loads = {}
for i, file in ipairs(load) do loads[file] = i end
H.eq(load[1], "LibStub/LibStub.lua", "LibStub loads first")
for _, file in ipairs({ "Compat.lua", "Settings.lua", "Engine.lua", "UI.lua" }) do
    H.check(loads[file] ~= nil, "the library loads " .. file)
end
H.check((loads["Compat.lua"] or 99) < (loads["UI.lua"] or 0), "Compat before UI")

local shipped = {}
for _, file in ipairs(ship) do shipped[file] = true end
H.check(shipped["LibGroupBuffs-1.0.xml"], "the entry XML itself ships")
for _, file in ipairs(load) do
    H.check(shipped[file], file .. " is loaded, so it ships")
end

-- A missing file is an error naming it, never a shorter list.
local ok, err = pcall(L.resolve, "tests/no-such-library")
H.check(not ok and tostring(err):find("not found", 1, true), "a missing library is an error: " .. tostring(err))

-- The library itself loads through the harness from here, too.
H.loadLibrary()
H.check(LibStub("LibGroupBuffs-1.0", true) ~= nil, "and the harness loads it from this file")

H.done("test_libfiles")
