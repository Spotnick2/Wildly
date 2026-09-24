------------------------------------------------------------
-- test_host.lua - the parts of the window that are Wildly's own: the
-- reagent footer, the spec icon and the colours.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_host.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(known, ranks)
    WoW.reset()
    WildlyDB = nil
    Wildly_EnsureDefaults()
    H.TeachSpells(known, ranks)
    T.RefreshSpellData()
end

------------------------------------------------------------
-- The reagent follows the Gift rank the druid knows
------------------------------------------------------------

setup({ "MARK_SINGLE" })
H.eq(T.GetGiftRank(), 0, "no Gift known: rank 0")
H.eq(#T.FooterItems(), 0, "and no reagent to show")

setup({ "MARK_SINGLE", "MARK_GROUP" }, { MARK_GROUP = "Rank 1" })
H.eq(T.GetGiftRank(), 1, "rank 1 read from the spellbook")
local items = T.FooterItems()
H.eq(#items, 1, "one reagent")
H.eq(items[1].itemID, 17021, "Wild Berries for rank 1")
H.eq(items[1].usedBy, "Gift of the Wild", "used by Gift of the Wild, by its client name")

setup({ "MARK_SINGLE", "MARK_GROUP" }, { MARK_GROUP = "Rank 2" })
items = T.FooterItems()
H.eq(items[1] and items[1].itemID, 17026, "Wild Thornroot for rank 2")

-- Rank 3 is TBC's, at level 70, reagent Wild Quillvine. Forever caps at 60, so
-- a rank this table does not know shows nothing rather than a guess.
setup({ "MARK_SINGLE", "MARK_GROUP" }, { MARK_GROUP = "Rank 3" })
H.eq(#T.FooterItems(), 0, "an unknown rank shows no reagent")
for _, id in pairs(T.GIFT_REAGENTS) do
    H.check(id ~= 22148, "Wild Quillvine is not in the table")
end

-- Knowing Thorns never adds a reagent: it has none.
setup({ "THORNS" })
H.eq(#T.FooterItems(), 0, "Thorns alone shows no reagent")

-- The count colour: plenty, running low, nearly out.
setup({ "MARK_SINGLE", "MARK_GROUP" }, { MARK_GROUP = "Rank 1" })
local color = T.FooterItems()[1].color
H.eq(select(2, color(60)), 1.00, "50 or more is green")
H.eq(select(1, color(30)), 1.00, "25 to 49 is yellow (red channel full)")
H.eq(select(2, color(30)), 0.88, "(and green nearly full)")
H.eq(select(2, color(3)), 0.22, "fewer is red")

-- ...and what the window draws: the button for the reagent, with its count.
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
WoW.itemCounts[17021] = 40
T.UpdateUI()
local btn = T.footerButton(17021)
H.check(btn ~= nil, "the window shows the Wild Berries button")
H.eq(btn and btn.countTxt._text, 40, "with the count from the bags")

-- Learning rank 2 swaps the reagent once the spells are re-read, which is
-- what SPELLS_CHANGED runs (test_visibility drives that event).
WoW.Know(H.SPELL.MARK_GROUP, H.NAME.MARK_GROUP, "Rank 2")
T.UpdateUI()
H.check(T.footerButton(17021) ~= nil, "a rebuild alone keeps the rank it last read")
T.RefreshSpellData()
T.UpdateUI()
H.check(T.footerButton(17026) ~= nil, "after re-reading spells the footer shows Wild Thornroot")
H.eq(T.footerButton(17021), nil, "and no longer Wild Berries")

-- Untracking Mark hides its reagent: no row, nothing to count.
Wildly_SetConfig("trackMark", false)
H.eq(#T.FooterItems(), 0, "with Mark untracked there is no reagent")
Wildly_SetConfig("trackMark", true)
H.eq(#T.FooterItems(), 1, "and it comes back with the row")

------------------------------------------------------------
-- The spellbook is read when spells change, not on every rebuild
--
-- The window asks for the reagent and the icon on each rebuild - in a raid,
-- each aura burst - and working out the rank walks the whole spellbook.
------------------------------------------------------------

local walks = 0
local realRank = Wildly.API.GetSpellRank
Wildly.API.GetSpellRank = function(...) walks = walks + 1 return realRank(...) end
for _ = 1, 5 do T.UpdateUI() end
H.eq(walks, 0, "five rebuilds read the spellbook no times")
T.RefreshSpellData()
H.eq(walks, 1, "re-reading spells reads it once")
Wildly.API.GetSpellRank = realRank

------------------------------------------------------------
-- The spec icon, from spells only one tree teaches
------------------------------------------------------------

setup({ "MARK_SINGLE" })
H.eq(T.GetSpecIcon(), T.DRUID_ICON, "no spec spell: the druid class icon")
for _, spec in ipairs(T.SPEC_ICON_SPELLS) do
    setup({ "MARK_SINGLE" })
    WoW.Know(spec.id, "Spec " .. spec.id)
    T.RefreshSpellData()
    H.eq(T.GetSpecIcon(), spec.icon, "spell " .. spec.id .. " picks its tree's icon")
end
local ids = {}
for _, spec in ipairs(T.SPEC_ICON_SPELLS) do ids[#ids + 1] = spec.id end
H.eq(table.concat(ids, ","), "24858,18562,17007",
    "Moonkin Form, Swiftmend and Leader of the Pack - Vanilla's 31-point talents, not TBC's")

------------------------------------------------------------
-- The colours reach the window
------------------------------------------------------------

setup({ "MARK_SINGLE" })
local look = T.Appearance()
H.eq(look.border[1], 1.00, "an orange border")
H.eq(look.border[2], 0.49, "(#ff7c0a)")
H.eq(look.popDivider[1], 0.95, "and an orange popover divider, the key r11 added")
H.eq(look.icon, T.DRUID_ICON, "with the spec icon")

WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
T.UpdateUI()
local ui = T.ui
local merged = ui:Appearance()
H.eq(merged.headerLine[1], 1.00, "the window merges Wildly's header line over the defaults")
H.eq(merged.mainBg[1], 0.04, "and keeps the library's background")
H.eq(ui.main.hdrLine._colorTexture and ui.main.hdrLine._colorTexture[2], 0.49,
    "the drawn header line is orange")
H.eq(ui.pop._hdiv and ui.pop._hdiv._colorTexture and ui.pop._hdiv._colorTexture[1], 0.95,
    "and so is the drawn popover divider")
H.eq(ui.main.specIcon._texture, T.DRUID_ICON, "the header shows the spec icon")

H.done("test_host")
