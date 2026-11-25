------------------------------------------------------------
-- test_refusal.lua - refusal memory (LibGroupBuffs r39, #97).
--
-- The client can refuse a buff with "A more powerful spell is already
-- active": a top-up on a member whose Mark of the Wild is a higher rank from
-- another druid, say, or whatever Camp Benefits blocks. The library learns that
-- from the client's own events, which Wildly forwards from a frame of its own,
-- and the row's click-time pick then skips that member for up to 30 s. The
-- sequence is the one the library measured: SENT, FAILED with its castGUID,
-- then UI error 57 with SPELL_FAILED_AURA_BOUNCED. No click is tracked, so a
-- cast from the window, an action bar or a macro teaches it alike.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_refusal.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local BOUNCED = "A more powerful spell is already active"

local function setup(known)
    WoW.reset()
    WildlyDB = nil
    Wildly_EnsureDefaults()
    H.TeachSpells(known)
    T.RefreshSpellData()
    rawset(_G, "SPELL_FAILED_AURA_BOUNCED", BOUNCED)
    WoW.SetUnit("player", { name = "Druid", guid = "P0", class = "DRUID" })
    WoW.SetUnit("party1", { name = "Warrior", guid = "P1", class = "WARRIOR" })
    WoW.SetUnit("party2", { name = "Priest", guid = "P2", class = "PRIEST" })
    WoW.groupMembers = 3
    WoW.SetAura("player", H.NAME.MARK_SINGLE, 3600, 3000, H.SPELL.MARK_SINGLE)
end

local function markRow()
    T.UpdateUI()
    for _, row in ipairs(T.rows()) do
        if row._active and row._def.id == "mark" then return row end
    end
end

local cast = 0
local function refuse(target)
    cast = cast + 1
    local guid = "Cast-" .. cast
    WoW.dispatch("UNIT_SPELLCAST_SENT", "player", target, guid, H.SPELL.MARK_SINGLE)
    WoW.dispatch("UNIT_SPELLCAST_FAILED", "player", guid, H.SPELL.MARK_SINGLE)
    WoW.dispatch("UI_ERROR_MESSAGE", 57, BOUNCED)
end

H.check(T.ui.RefusalEvents ~= nil, "the library has refusal memory (r39)")

-- The single-target click is the one that skips: the left click without
-- Gift of the Wild, the right click with it.
for _, case in ipairs({
    { known = { "MARK_SINGLE" }, button = "LeftButton", attr = "unit1", label = "single only, left click" },
    { known = { "MARK_SINGLE", "MARK_GROUP" }, button = "RightButton", attr = "unit2", label = "with Gift, right click" },
}) do
    setup(case.known)
    local row = markRow()
    H.check(row ~= nil, case.label .. ": the Mark of the Wild row is shown")
    if row and T.ui.RefusalEvents then
        T.ui:RowPreClick(row, case.button)
        H.eq(row:GetAttribute(case.attr), "party1", case.label .. ": the click aims at the first member missing it")
        refuse("Warrior")
        H.check(T.engine:RefusalOf("party1", row._def) ~= nil,
            case.label .. ": Wildly's forwarded events teach the library the refusal")
        -- The next click, more than a second later: only its PreClick pick
        -- skips the refused member, so the attribute is read straight after it.
        WoW.now = WoW.now + 2
        T.ui:RowPreClick(row, case.button)
        H.eq(row:GetAttribute(case.attr), "party2", case.label .. ": the next click aims past the refused member")
        H.eq(T.engine:GroupStat(row._members, row._def).nMiss, 2,
            case.label .. ": the refused member still counts as missing")
        -- Combat clears every refusal (a click in combat uses the aim wired
        -- before it). Wildly forwards the combat events too.
        WoW.dispatch("PLAYER_REGEN_DISABLED")
        H.eq(T.engine:RefusalOf("party1", row._def), nil, case.label .. ": entering combat forgets the refusal")
        WoW.dispatch("PLAYER_REGEN_ENABLED")
    end
end

-- A pet coming or going prunes the engine: routine cache upkeep (r39 records
-- no refusal for a pet: its name isn't unique).
-- Wildly's handler acts only once PLAYER_LOGIN found a Druid.
do
    WoW.dispatch("PLAYER_LOGIN")
    local pruned, real = 0, T.engine.PruneCache
    T.engine.PruneCache = function(...) pruned = pruned + 1; return real(...) end
    WoW.dispatch("UNIT_PET", "party1")
    T.engine.PruneCache = real
    H.eq(pruned, 1, "UNIT_PET prunes the engine")
end

-- Players only: a refused cast on a pet (Thorns on Everyone, pets tracked)
-- isn't recorded, since a pet's name doesn't pin the cast on it.
do
    setup({ "MARK_SINGLE" })
    WoW.SetUnit("partypet1", { name = "Wolfie", guid = "Pet-1", class = "PET" })
    local row = markRow()
    if row then
        refuse("Wolfie")
        H.eq(T.engine:RefusalOf("partypet1", row._def), nil, "a refusal on a pet isn't recorded")
    end
end

H.done("test_refusal")
