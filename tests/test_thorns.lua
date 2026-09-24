------------------------------------------------------------
-- test_thorns.lua - who the Thorns row covers.
--
-- Thorns is why LibGroupBuffs has membersFor: the engine asks Wildly once per
-- row which members it covers, and uses that list for the stats, the target,
-- the popover and the clicks. These pin the five modes, and the two traps the
-- TBC code fell into: `unit == "player"` (in a raid you are raidN) and the
-- main tank matched by name (first names are not unique on Forever).
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_thorns.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local THORNS, MARK
for _, d in ipairs(T.DEFS) do
    if d.id == "thorns" then THORNS = d end
    if d.id == "mark" then MARK = d end
end

local function setup(mode)
    WoW.reset()
    WildlyDB = nil
    Wildly_EnsureDefaults()
    if mode then WildlyDB.thornsMode = mode end
    H.TeachSpells({ "MARK_SINGLE", "THORNS" })
    T.RefreshSpellData()
    T.ForgetTanks()
end

-- Roles here are set directly on the stub, which fires no event, so the
-- group's tank set is forgotten by hand - what a roster or role event does.
local function rolesChanged() T.ForgetTanks() end

local function units(list)
    local out = {}
    for _, m in ipairs(list) do out[#out + 1] = m.unit end
    table.sort(out)
    return table.concat(out, ",")
end

-- A party: you, a warrior who has set the tank role, a mage, and a pet.
local function party()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "DRUID" })
    WoW.SetUnit("party1", { name = "Sten Thornbeard", guid = "P1", class = "WARRIOR", role = "TANK" })
    WoW.SetUnit("party2", { name = "Mirel Dawnsong", guid = "P2", class = "MAGE" })
    WoW.SetUnit("partypet2", { name = "Water Elemental", guid = "PET2" })
    WoW.groupMembers = 3
    return {
        { unit = "player", name = "Karuzo Elegia" },
        { unit = "party1", name = "Sten Thornbeard" },
        { unit = "party2", name = "Mirel Dawnsong" },
        -- The engine tags a pet with a PET class; that is how Thorns knows.
        { unit = "partypet2", name = "Water Elemental", class = "PET_MAGE" },
    }
end

-- A raid where you are raid3, two raiders share the first name "Karuzo", and
-- the main tank is the SECOND Karuzo. No LFG roles at all.
local function raid()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "DRUID" })
    WoW.inRaid = true
    WoW.groupMembers = 4
    WoW.SetUnit("raid1", { name = "Karuzo Vale", guid = "R1", class = "WARRIOR" })
    WoW.SetUnit("raid2", { name = "Karuzo Stone", guid = "R2", class = "WARRIOR" })
    WoW.SetUnit("raid3", { name = "Karuzo Elegia", guid = "P0", class = "DRUID" })   -- you
    WoW.SetUnit("raid4", { name = "Mirel Dawnsong", guid = "R4", class = "MAGE" })
    WoW.SetUnit("raidpet4", { name = "Water Elemental", guid = "PET4" })
    WoW.raidRoster = {
        { name = "Karuzo", subgroup = 1 },
        { name = "Karuzo", subgroup = 1, role = "MAINTANK" },
        { name = "Karuzo", subgroup = 1 },
        { name = "Mirel", subgroup = 1 },
    }
    return {
        { unit = "raid1", name = "Karuzo Vale" },
        { unit = "raid2", name = "Karuzo Stone" },
        { unit = "raid3", name = "Karuzo Elegia" },
        { unit = "raid4", name = "Mirel Dawnsong" },
        { unit = "raidpet4", name = "Water Elemental", class = "PET_MAGE" },
    }
end

------------------------------------------------------------
-- Every other buff is untouched
------------------------------------------------------------

setup("self")
local members = party()
H.eq(T.MembersFor(MARK, members), members, "Mark of the Wild covers the whole group, pets included")

------------------------------------------------------------
-- Party, mode by mode
------------------------------------------------------------

setup("everyone")
members = party()
H.eq(units(T.MembersFor(THORNS, members)), "party1,party2,player", "everyone: every player, no pet")

setup("self")
members = party()
H.eq(units(T.MembersFor(THORNS, members)), "player", "self: only you")

setup("tanks")
members = party()
H.eq(units(T.MembersFor(THORNS, members)), "party1", "tanks: the member with the tank role")

setup("default")
members = party()
H.eq(units(T.MembersFor(THORNS, members)), "party1", "default in a group: the tanks")

-- "disabled" never reaches the filter: the row is dropped before it, by
-- Wildly_IsBuffEnabled, the one place that rule lives.
setup("disabled")
members = party()
local defs = {}
for _, d in ipairs(T.ActiveDefs({}, {})) do defs[#defs + 1] = d.id end
H.eq(table.concat(defs, ","), "mark", "disabled: no Thorns row at all")

-- A party where nobody set a role - likely on a client with no LFG, which is
-- not yet measured. "tanks" is strict and covers nobody; "default" falls back
-- to you rather than losing the row.
setup("default")
members = party()
WoW.units.party1.role = nil
rolesChanged()
H.eq(units(T.MembersFor(THORNS, members)), "player", "no roles set: default covers you")
H.eq(T.EffectiveMode(), "self", "because the group has no tank")
WildlyDB.thornsMode = "tanks"
H.eq(#T.MembersFor(THORNS, members), 0, "while 'tanks' stays strict: nobody, no row")

------------------------------------------------------------
-- Solo
------------------------------------------------------------

setup("default")
WoW.groupMembers = 0
local solo = { { unit = "player", name = "Karuzo Elegia" }, { unit = "pet", name = "Treant", class = "PET" } }
H.eq(units(T.MembersFor(THORNS, solo)), "player", "default alone: yourself")
WildlyDB.thornsMode = "tanks"
H.eq(#T.MembersFor(THORNS, solo), 0, "tanks alone: nobody, you have no tank role")
WildlyDB.thornsMode = "everyone"
H.eq(units(T.MembersFor(THORNS, solo)), "player", "everyone alone: you, never your pet")

------------------------------------------------------------
-- Raid: the two TBC traps
------------------------------------------------------------

setup("self")
members = raid()
H.eq(units(T.MembersFor(THORNS, members)), "raid3",
    "self in a raid finds you as raid3 - `unit == \"player\"` never matched here")

setup("tanks")
members = raid()
H.eq(units(T.MembersFor(THORNS, members)), "raid2",
    "the main tank is raid2, by roster index - not raid1 or you, who share the first name")

setup("default")
members = raid()
H.eq(units(T.MembersFor(THORNS, members)), "raid2",
    "default in a raid: the main tank - and not you as well, though you are no tank")

-- Decided over the whole group, not per subgroup: a subgroup without the
-- tank does not fall back to you when the raid has one.
local otherGroup = { { unit = "raid3", name = "Karuzo Elegia" }, { unit = "raid4", name = "Mirel Dawnsong" } }
H.eq(#T.MembersFor(THORNS, otherGroup), 0, "your subgroup, which lacks the tank, gets no Thorns row")

-- A role set on a raider counts too, alongside the main tank.
WoW.units.raid4.role = "TANK"
rolesChanged()
H.eq(units(T.MembersFor(THORNS, members)), "raid2,raid4", "and anyone with the tank role")

-- A raid with no main tank and no roles falls back to you, like a party.
setup("default")
members = raid()
WoW.raidRoster[2].role = nil
rolesChanged()
H.eq(units(T.MembersFor(THORNS, members)), "raid3", "a raid without tanks: default covers you")

setup("everyone")
members = raid()
H.eq(units(T.MembersFor(THORNS, members)), "raid1,raid2,raid3,raid4", "everyone: all raiders, no pet")

-- The raid roster's MAINTANK belongs to "raid"..index, and only in a raid.
-- Here roster entry 1 is the main tank: a party unit numbered 1, or raid1
-- outside a raid, must not pick that up.
setup("tanks")
party()
WoW.units.party1.role = nil
WoW.raidRoster = { { name = "Sten", subgroup = 1, role = "MAINTANK" } }
WoW.SetUnit("raid1", { name = "Sten Thornbeard", guid = "P1" })
rolesChanged()
H.eq(T.IsTank("party1"), false, "party1 is never matched against raid roster entry 1")
H.eq(T.IsTank("raid1"), false, "and neither is raid1 while not in a raid")
WoW.inRaid = true
rolesChanged()
H.eq(T.IsTank("raid1"), true, "in a raid, raid1 is roster entry 1's main tank")

-- Pets by the engine's tag, not their unit tokens.
H.eq(T.IsPet({ unit = "raidpet4", class = "PET_MAGE" }), true, "a PET_ class is a pet")
H.eq(T.IsPet({ unit = "pet", class = "PET" }), true, "so is a plain PET")
H.eq(T.IsPet({ unit = "raid4", class = "MAGE" }), false, "a player class is not")
H.eq(T.IsPet({ unit = "raid4" }), false, "nor is a member with no class reported")

------------------------------------------------------------
-- The window follows the filtered list
--
-- The engine calls membersFor once per row and uses that list everywhere, so
-- the row's target and its popover can only ever name covered members.
------------------------------------------------------------

-- The rows drawn, as "group:buff", group 99 up being the pet buckets.
local function drawn()
    local out = {}
    for _, r in ipairs(T.rows()) do
        if r._active then out[#out + 1] = r._gNum .. ":" .. r._def.id end
    end
    return table.concat(out, ",")
end

setup("tanks")
party()
T.UpdateUI()
H.eq(drawn(), "1:mark,1:thorns,99:mark",
    "the pet bucket gets a Mark row and no Thorns row - Thorns never covers a pet")
local thornsRow, markRow
for _, r in ipairs(T.rows()) do
    if r._active and r._gNum == 1 and r._def.id == "thorns" then thornsRow = r end
    if r._active and r._gNum == 1 and r._def.id == "mark" then markRow = r end
end
H.check(thornsRow ~= nil, "a party with a tank has a Thorns row")
H.eq(thornsRow and thornsRow:GetAttribute("unit2"), "party1", "whose click lands on the tank")
H.eq(thornsRow and thornsRow:GetAttribute("unit1"), "party1", "on both buttons")
H.eq(thornsRow and units(thornsRow._members), "party1", "and whose popover lists only the tank")
H.check(markRow ~= nil and #markRow._members == 3, "while the Mark row still covers all three players")

-- Buffing the tank satisfies the row, even though nobody else has Thorns.
WoW.SetAura("party1", "Thorns", 600, 500)
T.UpdateUI()
local st = T.engine:GroupStat(thornsRow._members, THORNS)
H.eq(st.nMiss, 0, "the tank having Thorns means nobody on the row is missing it")

-- No tank in the group: no Thorns row at all, the Mark row stays.
setup("tanks")
party()
WoW.units.party1.role = nil
T.UpdateUI()
H.eq(drawn(), "1:mark,99:mark", "a tankless group gets no Thorns row, and keeps Mark")

-- Changing the mode in the panel reaches the window through the rebuild.
WildlyDB.thornsMode = "everyone"
T.UpdateUI()
H.eq(drawn(), "1:mark,1:thorns,99:mark", "switching to everyone brings the Thorns row back")

------------------------------------------------------------
-- A role change reaches the window
------------------------------------------------------------

setup("tanks")
party()
WoW.units.party1.role = nil
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()
T.UpdateUI()
H.eq(drawn(), "1:mark,99:mark", "no tank yet: no Thorns row")
WoW.units.party1.role = "TANK"            -- the warrior sets the tank role
for _, event in ipairs({ "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }) do
    WoW.dispatch(event)
    WoW.flushTimers()
    WoW.flushTimers()
    H.eq(drawn(), "1:mark,1:thorns,99:mark", event .. " rebuilds with the new tank")
    WoW.units.party1.role = nil
    WoW.dispatch(event)
    WoW.flushTimers()
    WoW.flushTimers()
    H.eq(drawn(), "1:mark,99:mark", event .. " also drops a tank who unsets the role")
    WoW.units.party1.role = "TANK"
end

------------------------------------------------------------
-- A window that closed itself for want of rows comes back from the panel
------------------------------------------------------------

setup("tanks")
party()
WoW.units.party1.role = nil
WoW.units.partypet2 = nil
WildlyDB.trackMark = false                  -- only Thorns, and nobody to cover
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()
WoW.flushTimers()
H.check(not T.ui:IsVisible(), "with no rows the window closes itself")
H.eq(WildlyDB.visible, true, "which is not the player closing it")
Wildly_SetConfig("thornsMode", "everyone")  -- what the radio does, then:
Wildly_ForceRebuild()
WoW.flushTimers()
H.check(T.ui:IsVisible(), "picking a mode that gives it rows brings it back")
H.eq(drawn(), "1:thorns", "with the Thorns row")

-- The same, but the mode is picked mid-fight: the window cannot be built
-- then, and must not be forgotten either.
setup("tanks")
party()
WoW.units.party1.role = nil
WoW.units.partypet2 = nil
WildlyDB.trackMark = false
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()
WoW.flushTimers()
H.check(not T.ui:IsVisible(), "closed itself again")
WoW.inCombat = true
Wildly_SetConfig("thornsMode", "everyone")
Wildly_ForceRebuild()
WoW.flushTimers()
H.check(not T.ui:IsVisible(), "nothing is built during the fight")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.flushTimers()
WoW.flushTimers()
H.check(T.ui:IsVisible(), "and the window opens when the fight ends")
H.eq(drawn(), "1:thorns", "with the Thorns row the new mode gives it")

-- A deliberate close picked up mid-fight is still never undone.
T.CloseUI(true)
WoW.inCombat = true
Wildly_ForceRebuild()
WoW.flushTimers()
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.flushTimers()
WoW.flushTimers()
H.check(not T.ui:IsVisible(), "a window closed on purpose stays closed after the fight")

H.done("test_thorns")
