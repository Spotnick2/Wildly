------------------------------------------------------------
-- test_availability.lua - which buffs get a row, and what a click casts.
--
-- Gift of the Wild is not learnable at the beta's current cap, so for now a
-- druid knows Mark of the Wild and maybe Thorns. Wiring a row to a spell the
-- druid does not have is a dead click. The TBC code decided this with
-- per-def flags (always / needsKnown / optional / leftUsesSingle); the
-- library's availability and click mapping replace all four.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_availability.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function defById(id)
    for _, d in ipairs(T.DEFS) do
        if d.id == id then return d end
    end
end

local function ids(defs)
    local out = {}
    for _, d in ipairs(defs) do out[#out + 1] = d.id end
    return table.concat(out, ",")
end

local function setup(known)
    WoW.reset()
    WildlyDB = nil
    Wildly_EnsureDefaults()
    H.TeachSpells(known)
    T.RefreshSpellData()
end

------------------------------------------------------------
-- The definitions are the library's shape
------------------------------------------------------------

H.eq(#T.DEFS, 2, "two buffs: Mark of the Wild and Thorns")
local mark, thorns = defById("mark"), defById("thorns")
H.eq(mark.snglID, H.SPELL.MARK_SINGLE, "Mark by its spell ID")
H.eq(mark.grpID, H.SPELL.MARK_GROUP, "with Gift of the Wild as its group form")
H.eq(thorns.snglID, H.SPELL.THORNS, "Thorns by its spell ID")
H.eq(thorns.grpID, nil, "and no group form at all")
for _, d in ipairs(T.DEFS) do
    for _, old in ipairs({ "always", "needsKnown", "optional", "leftUsesSingle" }) do
        H.eq(d[old], nil, d.id .. " carries no TBC flag '" .. old .. "'")
    end
end

------------------------------------------------------------
-- Mark of the Wild only
------------------------------------------------------------

setup({ "MARK_SINGLE" })
mark = defById("mark")
H.check(mark.hasSingle == true, "Mark of the Wild is known")
H.check(mark.hasGroup == false, "Gift of the Wild is not")
H.eq(ids(T.ActiveDefs({}, {})), "mark", "only the buff we can actually cast gets a row")

local primary, secondary = T.ClickSpells(mark)
H.eq(primary, "Mark of the Wild",
    "left-click falls back to the single-target spell - never a dead primary click")
H.eq(secondary, "Mark of the Wild", "right-click is the same spell here")

------------------------------------------------------------
-- Gift learned: left-click becomes the group spell
------------------------------------------------------------

setup({ "MARK_SINGLE", "MARK_GROUP" })
primary, secondary = T.ClickSpells(defById("mark"))
H.eq(primary, "Gift of the Wild", "left-click prefers Gift of the Wild")
H.eq(secondary, "Mark of the Wild", "right-click stays single-target")

------------------------------------------------------------
-- Thorns: single-target on both clicks, which is what leftUsesSingle did
------------------------------------------------------------

setup({ "MARK_SINGLE", "MARK_GROUP", "THORNS" })
H.eq(ids(T.ActiveDefs({}, {})), "mark,thorns", "Thorns gets a row once known")
primary, secondary = T.ClickSpells(defById("thorns"))
H.eq(primary, "Thorns", "left-click casts Thorns")
H.eq(secondary, "Thorns", "and so does right-click - there is no group Thorns")

setup({ "THORNS" })
H.eq(ids(T.ActiveDefs({}, {})), "thorns", "Thorns alone is enough for a Thorns row")

------------------------------------------------------------
-- Knowing nothing means no row at all
------------------------------------------------------------

setup({})
H.eq(ids(T.ActiveDefs({}, {})), "", "a druid who knows neither gets no rows")

------------------------------------------------------------
-- The config layers on top of availability, not instead of it
------------------------------------------------------------

setup({ "MARK_SINGLE", "THORNS" })
WildlyDB.trackMark = false
H.eq(ids(T.ActiveDefs({}, {})), "thorns", "untracking Mark removes its row")
WildlyDB.trackMark = true
WildlyDB.thornsMode = "disabled"
H.eq(ids(T.ActiveDefs({}, {})), "mark", "Thorns set to Off removes its row")
for _, mode in ipairs({ "default", "tanks", "self", "everyone" }) do
    WildlyDB.thornsMode = mode
    H.eq(ids(T.ActiveDefs({}, {})), "mark,thorns", "Thorns in '" .. mode .. "' keeps its row")
end

setup({ "MARK_SINGLE" })
WildlyDB.thornsMode = "everyone"
H.eq(ids(T.ActiveDefs({}, {})), "mark",
    "no Thorns mode can conjure a row for a spell the druid does not have")

------------------------------------------------------------
-- Localized names come from the client, not from our literals
------------------------------------------------------------

WoW.reset()
WildlyDB = nil
Wildly_EnsureDefaults()
WoW.DefineSpell(1126, "Mal der Wildnis")
WoW.Know(1126, "Mal der Wildnis")
T.RefreshSpellData()
H.eq(defById("mark").sngl, "Mal der Wildnis", "the name is whatever the client says")
H.eq(defById("mark").names[1], "Mal der Wildnis", "and the aura lookup uses that name")

H.done("test_availability")
