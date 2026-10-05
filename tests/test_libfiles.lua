------------------------------------------------------------
-- test_libfiles.lua - the one reader of the embedded libraries' XML.
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

local glassRoot = H.libGlassRoot()

-- LibGroupBuffs is one runtime file since r26, after its LibStub.
local load, ship = L.resolve(H.libraryRoot(), nil, glassRoot)
H.eq(load[1], "LibStub/LibStub.lua", "LibStub loads first")
H.eq(load[2], "LibGroupBuffs.lua", "then the library's one runtime file")
H.eq(#load, 2, "and nothing else")

local shipped = {}
for _, file in ipairs(ship) do shipped[file] = true end
H.check(shipped["LibGroupBuffs-1.0.xml"], "the entry XML itself ships")
for _, file in ipairs(load) do
    H.check(shipped[file], file .. " is loaded, so it ships")
end
for file in pairs(shipped) do
    H.check(not file:find("^Media/"), "LibGroupBuffs ships no textures of its own: " .. file)
end

-- LibGlass: its XML and code, its LICENSE, and every texture its source draws.
local gload, gship = L.glass(glassRoot)
H.eq(gload[#gload], "LibGlass.lua", "LibGlass loads its one runtime file last")
local gshipped, textures = {}, 0
for _, file in ipairs(gship) do
    gshipped[file] = true
    if file:find("^Media/.+%.tga$") then textures = textures + 1 end
end
H.check(gshipped["LibGlass-1.0.xml"] and gshipped["LICENSE"], "and ships its XML and LICENSE")
H.check(textures >= 10, "and the textures it draws: " .. textures)

-- Every texture LibGroupBuffs names is LibGlass's to supply. Against a copy
-- of LibGlass with none, resolve fails, naming the texture: a hole in the
-- window draws no Lua error, so this is where it has to show.
local ok, err = pcall(L.resolve, H.libraryRoot(), nil, "tests/no-such-glass")
H.check(not ok and tostring(err):find("does not have", 1, true),
    "a texture the LibGlass checkout lacks is an error: " .. tostring(err))

-- A missing file is an error naming it, never a shorter list.
ok, err = pcall(L.resolve, "tests/no-such-library")
H.check(not ok and tostring(err):find("not found", 1, true), "a missing library is an error: " .. tostring(err))
ok, err = pcall(L.glass, "tests/no-such-glass")
H.check(not ok and tostring(err):find("not found", 1, true), "and so is a missing LibGlass: " .. tostring(err))

-- Both libraries load through the harness from here, too.
H.loadLibrary()
H.check(LibStub("LibGlass-1.0", true) ~= nil, "the harness loads LibGlass from this file")
H.check(LibStub("LibGroupBuffs-1.0", true) ~= nil, "and LibGroupBuffs")

H.done("test_libfiles")
