------------------------------------------------------------
-- test_stub.lua - the stub's own shapes, where Wildly depends on them.
--
-- The stub is the list of APIs the tests trust, so a stub that answers
-- differently from the client lets broken code pass. These pin the entries
-- Wildly added to the library's copy (marked "Wildly:" in wow_stubs.lua) to
-- the client's declared or observed shape.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_stub.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

------------------------------------------------------------
-- strsplit keeps empty fields, as the client does
------------------------------------------------------------

local a, b, c = strsplit(",", "a,,b")
H.eq(select("#", strsplit(",", "a,,b")), 3, "an empty field is still a field")
H.eq(a, "a", "first") H.eq(b, "", "the empty one") H.eq(c, "b", "last")
H.eq(select("#", strsplit(",", "")), 1, "an empty string is one empty field")
local x, y, z = strsplit(",;", "1;2,3")
H.eq(x .. y .. z, "123", "every character of the separator splits")

------------------------------------------------------------
-- UnitIsUnit: same character, whatever the token
--
-- The reason Wildly needs it: in a raid the roster calls you raidN, so
-- `unit == "player"` is false for yourself.
------------------------------------------------------------

WoW.reset()
local me = WoW.units.player
WoW.inRaid = true
WoW.groupMembers = 2
WoW.SetUnit("raid1", { name = "Other Person", guid = "G-OTHER" })
WoW.SetUnit("raid2", { name = me.name, guid = me.guid })
H.eq(UnitIsUnit("raid2", "player"), true, "raid2 is you when it names your character")
H.eq(UnitIsUnit("raid1", "player"), false, "raid1 is somebody else")
H.eq(UnitIsUnit("raid9", "player"), false, "a token naming nobody is nobody")

------------------------------------------------------------
-- GetRaidRosterInfo: the full tuple, role in the 10th place
------------------------------------------------------------

WoW.raidRoster = {
    { name = "Other Person", subgroup = 2, role = "MAINTANK" },
    { name = me.name, subgroup = 1 },
}
local ret = { GetRaidRosterInfo(1) }
H.eq(ret[1], "Other Person", "name first")
H.eq(ret[3], 2, "subgroup third")
H.eq(ret[10], "MAINTANK", "the raid role is the 10th value")
H.eq(select(10, GetRaidRosterInfo(2)), nil, "and nil for someone without one")
H.eq(GetRaidRosterInfo(3), nil, "past the roster there is nothing")

------------------------------------------------------------
-- UnitGroupRolesAssigned: "NONE" unless a role was set
------------------------------------------------------------

H.eq(UnitGroupRolesAssigned("raid1"), "NONE", "no role set reads as NONE")
WoW.SetUnit("raid1", { name = "Other Person", guid = "G-OTHER", role = "TANK" })
H.eq(UnitGroupRolesAssigned("raid1"), "TANK", "a set role is returned")
H.eq(UnitGroupRolesAssigned(), "NONE", "the unit is optional and means the player")

H.done("test_stub")
