------------------------------------------------------------
-- test_clicks.lua - what the secure buttons are actually wired to after a
-- rebuild.
--
-- This is the part that has to be right: a row whose spell1 attribute names
-- Gift of the Wild when the druid does not have it is a click that does
-- nothing, and the frame gives no hint of it. Asserting the attributes is the
-- closest we can get to clicking without a game client. The mechanics are the
-- library's and tested there; this pins Wildly's buffs onto them.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_clicks.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(known)
    WoW.reset()
    WildlyDB = nil
    Wildly_EnsureDefaults()
    H.TeachSpells(known)
    T.RefreshSpellData()

    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "DRUID" })
    WoW.SetUnit("party1", { name = "Sten Thornbeard", guid = "P1", class = "WARRIOR" })
    WoW.SetUnit("party2", { name = "Mirel Dawnsong", guid = "P2", class = "MAGE" })
    WoW.groupMembers = 3
    T.UpdateUI()
    return T.rows()
end

local function activeRows(rows)
    local out = {}
    for _, r in ipairs(rows) do
        if r._active then out[#out + 1] = r end
    end
    return out
end

local function rowFor(defId)
    for _, r in ipairs(activeRows(T.rows())) do
        if r._def and r._def.id == defId then return r end
    end
end

------------------------------------------------------------
-- Mark of the Wild without Gift
------------------------------------------------------------

local rows = setup({ "MARK_SINGLE" })
H.eq(#activeRows(rows), 1, "one row: the one buff this druid has")
local row = rowFor("mark")
H.eq(row:GetAttribute("type1"), "spell", "left-click casts a spell")
H.eq(row:GetAttribute("spell1"), "Mark of the Wild",
    "left-click falls back to the single-target spell, never a Gift that does not exist")
H.eq(row:GetAttribute("spell2"), "Mark of the Wild", "right-click likewise")
local u1 = row:GetAttribute("unit1")
H.check(u1 == "player" or u1 == "party1" or u1 == "party2",
    "aimed at a group member, got " .. tostring(u1))
H.eq(row:GetAttribute("typerelease"), nil,
    "no typerelease: the press-and-hold path would cast a second time")

------------------------------------------------------------
-- The target follows who is actually missing the buff
------------------------------------------------------------

setup({ "MARK_SINGLE" })
WoW.SetAura("player", "Mark of the Wild", 1800, 1500)
WoW.SetAura("party1", "Mark of the Wild", 1800, 1500)
T.UpdateUI()
row = rowFor("mark")
H.eq(row:GetAttribute("unit2"), "party2", "right-click aims at the one missing it")
H.eq(row:GetAttribute("unit1"), "party2", "and so does left-click while there is no Gift")

-- Gift of the Wild on someone counts as having the buff: one row, two auras.
setup({ "MARK_SINGLE" })
WoW.SetAura("player", "Mark of the Wild", 1800, 1500)
WoW.SetAura("party1", "Gift of the Wild", 3600, 3000)
T.UpdateUI()
row = rowFor("mark")
H.eq(row:GetAttribute("unit2"), "party2", "a Gift from another druid is not re-buffed with Mark")

------------------------------------------------------------
-- With Gift learned, left-click becomes the group cast
------------------------------------------------------------

setup({ "MARK_SINGLE", "MARK_GROUP" })
row = rowFor("mark")
H.eq(row:GetAttribute("spell1"), "Gift of the Wild", "left-click is Gift of the Wild")
H.eq(row:GetAttribute("spell2"), "Mark of the Wild", "right-click stays single-target")

------------------------------------------------------------
-- Thorns: the same spell on both buttons
------------------------------------------------------------

-- "everyone", because this is about how the row is wired; who it covers in
-- each mode is test_thorns'. In the default mode this tankless party has no
-- Thorns row at all.
setup({ "MARK_SINGLE", "MARK_GROUP", "THORNS" })
WildlyDB.thornsMode = "everyone"
T.UpdateUI()
H.eq(#activeRows(T.rows()), 2, "a row per buff")
row = rowFor("thorns")
H.check(row ~= nil, "Thorns has its own row")
H.eq(row:GetAttribute("spell1"), "Thorns", "left-click casts Thorns - never Gift of the Wild")
H.eq(row:GetAttribute("spell2"), "Thorns", "and so does right-click")

------------------------------------------------------------
-- Nobody valid to cast on: clear the spell rather than cast on a corpse
------------------------------------------------------------

setup({ "MARK_SINGLE" })
WoW.units.player.dead = true
WoW.units.party1.dead = true
WoW.units.party2.connected = false
T.UpdateUI()
row = rowFor("mark")
H.check(row:GetAttribute("spell1") == nil, "no valid target -> no spell on left-click")
H.check(row:GetAttribute("spell2") == nil, "same for right-click")

------------------------------------------------------------
-- PreClick re-picks the target at click time; combat leaves it alone
------------------------------------------------------------

setup({ "MARK_SINGLE" })
for _, u in ipairs({ "player", "party1", "party2" }) do WoW.SetAura(u, "Mark of the Wild", 1800, 1500) end
T.UpdateUI()
row = rowFor("mark")
WoW.ClearAuras("party1")
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "PreClick re-aims at whoever lost the buff")

WoW.inCombat = true
WoW.ClearAuras("party2")
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "in combat the wiring is left alone")
WoW.inCombat = false

------------------------------------------------------------
-- Popover rows
------------------------------------------------------------

setup({ "MARK_SINGLE", "MARK_GROUP" })
row = rowFor("mark")
T.UpdatePopover(row, {
    { unit = "player", name = "Karuzo Elegia",   class = "DRUID" },
    { unit = "party1", name = "Sten Thornbeard", class = "WARRIOR" },
}, row._def)
local prs = T.popRows()
H.eq(prs[1]:GetAttribute("unit1"), "player", "each popover row targets its own member")
H.eq(prs[2]:GetAttribute("unit1"), "party1", "...the second one too")
H.eq(prs[1]:GetAttribute("spell1"), "Gift of the Wild", "left-click in the popover is Gift")
H.eq(prs[1]:GetAttribute("spell2"), "Mark of the Wild", "right-click is Mark on that person")
H.check(prs[3]._active == false, "unused rows are released")

------------------------------------------------------------
-- Both mouse edges, on every button in both pools
--
-- The client's secure handler acts on exactly one edge, chosen by the
-- ActionButtonUseKeyDown CVar. One edge registered is a dead button for
-- anyone whose client acts on the other.
------------------------------------------------------------

setup({ "MARK_SINGLE" })
local function assertBothEdges(button, what)
    local set = {}
    for _, e in ipairs(button._clicks or {}) do set[e] = true end
    H.eq(#(button._clicks or {}), 4, what .. " registers four click events")
    for _, e in ipairs({ "LeftButtonDown", "RightButtonDown", "LeftButtonUp", "RightButtonUp" }) do
        H.check(set[e], what .. " registers " .. e)
    end
end
assertBothEdges(T.rows()[1], "the first row")
assertBothEdges(T.rows()[#T.rows()], "the last row in the pool")
assertBothEdges(T.popRows()[1], "the first popover row")
assertBothEdges(T.popRows()[#T.popRows()], "the last popover row")
H.check(WoW.events[T.eventFrame()].CVAR_UPDATE == nil,
    "no CVAR_UPDATE handler - the registration is unconditional")

------------------------------------------------------------
-- Click hints describe what the click will actually do
------------------------------------------------------------

local function hintFor(r)
    WoW.clearTooltip()
    r._scripts.OnEnter(r)
    return WoW.tooltipText()
end

setup({ "MARK_SINGLE", "THORNS" })
WildlyDB.thornsMode = "everyone"
T.UpdateUI()
local hint = hintFor(rowFor("mark"))
H.check(hint:find("Mark of the Wild"), "the hint names the spell: " .. hint)
H.check(not hint:find("Gift"), "and never a Gift this druid cannot cast: " .. hint)
hint = hintFor(rowFor("thorns"))
H.check(hint:find("Thorns"), "the Thorns row's hint names Thorns: " .. hint)
H.check(hint:find("Karuzo Elegia") or hint:find("Sten Thornbeard") or hint:find("Mirel Dawnsong"),
    "and who it lands on, since it is always single-target: " .. hint)
H.check(not hint:find("your party"), "never 'your party': Thorns has no group form: " .. hint)

setup({ "MARK_SINGLE", "MARK_GROUP" })
hint = hintFor(rowFor("mark"))
H.check(hint:find("Gift of the Wild") and hint:find("your party"),
    "with Gift known, left-click reads as the group cast: " .. hint)

WildlyDB.showClickHints = false
H.eq(hintFor(rowFor("mark")), "", "turning hints off shows nothing")

H.done("test_clicks")
