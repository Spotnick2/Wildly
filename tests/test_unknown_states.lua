-- Unknown range and localized buff state: distinguish the two '?' indicators without claiming a live BG repro.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

for _, locale in ipairs({ "enUS", "deDE" }) do
    for _, instanceType in ipairs({ "none", "pvp" }) do
        WoW.reset()
        WildlyDB = nil
        Wildly_EnsureDefaults()
        WoW.locale = locale
        WoW.instanceType = instanceType
        WoW.instanceName = instanceType == "pvp" and "Warsong Gulch" or "Elwynn Forest"
        local single = locale == "deDE" and "Mal der Wildnis" or "Mark of the Wild"
        local prayer = locale == "deDE" and "Gabe der Wildnis" or "Gift of the Wild"
        WoW.Know(1126, single)
        WoW.DefineSpell(21849, prayer) -- known by the client, not learned by this caster
        T.RefreshSpellData()
        WoW.groupMembers = 2
        WoW.SetUnit("player", { name = "Priest", guid = "P", class = "DRUID" })
        WoW.SetUnit("party1", { name = "Friend", guid = "F", class = "WARRIOR" })
        WoW.SetAura("party1", prayer, 3600, 3000)
        WoW.range.party1 = true
        T.UpdateUI()
        local row
        for _, r in ipairs(T.rows()) do
            if r._active and r._def.id == "mark" then row = r; break end
        end
        H.check(row ~= nil, "Mark of the Wild row exists in " .. locale .. "/" .. instanceType)
        T.UpdatePopover(row, row._members, row._def)
        local pop
        for _, pr in ipairs(T.popRows()) do
            if pr._active and pr._unit == "party1" then pop = pr; break end
        end
        H.check(pop ~= nil, "friend appears in popover")
        H.eq(pop:GetAttribute("spell1"), single, "secure click uses resolved localized name")
        H.eq(select(3, T.engine:BuffRem("party1", row._def)), T.states.HAS,
            "localized unlearned group buff aura is recognized")
        H.eq(pop.rangeTxt:GetText(), "R", "localized spell range resolves")
        H.check(pop.timeTxt:GetText() ~= "?" and pop.timeTxt:GetText() ~= "MISS",
            "readable localized aura produces a timer")

        WoW.range.party1 = nil
        T.ui:ApplyPopRowVisuals(pop)
        H.eq(pop.rangeTxt:GetText(), "?", "unknown range has its own indicator")
        H.check(pop.timeTxt:GetText() ~= "?", "unknown range does not hide a readable buff")

        -- Model blocked reads separately from locale and instance type. These
        -- flags simulate a possible client response, not measured BG policy.
        WoW.range.party1 = true
        WoW.secret = true
        WoW.auraReadsThrow = true
        T.ui:ApplyPopRowVisuals(pop)
        H.check(pop.timeTxt:GetText() ~= "?", "cached localized buff survives blocked reads")
        WoW.units.party1.guid = "NEW-FRIEND-" .. locale .. "-" .. instanceType
        T.ui:ApplyPopRowVisuals(pop)
        H.eq(pop.timeTxt:GetText(), "?", "new member with blocked reads has no cached state")
        H.eq(pop.rangeTxt:GetText(), "R", "blocked aura does not imply unknown range")
        WoW.secret = false
        WoW.auraReadsThrow = false
        T.ui:ApplyPopRowVisuals(pop)
        H.check(pop.timeTxt:GetText() ~= "?" and pop.timeTxt:GetText() ~= "MISS",
            "live localized aura recovers when reads resume")
    end
end

-- A failed lookup retains a previously resolved name, then recovers by ID.
local def = T.DEFS[1]
local single, group = def.sngl, def.grp
local spellName = Wildly.API.SpellName
Wildly.API.SpellName = function(id)
    if id == def.snglID or id == def.grpID then return nil end
    return spellName(id)
end
T.RefreshSpellData()
Wildly.API.SpellName = spellName
H.eq(def.sngl, single, "localized single name survives lookup failure")
H.eq(def.grp, group, "localized group name survives lookup failure")
H.eq(def.snglFrom, "remembered", "lookup failure has remembered provenance")
T.RefreshSpellData()
H.eq(def.snglFrom, "resolved", "single lookup recovers")
H.eq(def.grpFrom, "resolved", "unlearned group lookup recovers")
WoW.dispatch("PLAYER_LOGIN")
SlashCmdList.WILDLY("help")
local help = table.concat(WoW.messages, " ")
H.check(help:find("? beside the class icon = spell range unknown", 1, true), "help distinguishes range")
H.check(help:find("? instead of a timer = buff state unreadable", 1, true), "help distinguishes aura state")
H.done("test_unknown_states")
