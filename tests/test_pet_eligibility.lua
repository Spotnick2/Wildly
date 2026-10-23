-- Mark of the Wild must not ask for casts on Forever's ineligible stat-buff pets.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

for _, raid in ipairs({ false, true }) do
    for _, track in ipairs({ false, true }) do
        WoW.reset()
        WildlyDB = nil
        Wildly_EnsureDefaults()
        Wildly_SetConfig("trackPets", track)
        Wildly_SetConfig("thornsMode", "everyone")
        H.TeachSpells({ "MARK_SINGLE", "MARK_GROUP", "THORNS" })
        T.RefreshSpellData()
        WoW.inRaid = raid
        WoW.groupMembers = 4
        WoW.SetUnit("player", { name = "Priest", guid = "P", class = "DRUID" })
        local excluded = {}
        for i, class in ipairs({ "HUNTER", "WARLOCK", "MAGE" }) do
            local unit = (raid and "raid" or "party") .. i
            local pet = (raid and "raidpet" or "partypet") .. i
            WoW.SetUnit(unit, { name = class, guid = unit, class = class })
            WoW.SetUnit(pet, { name = "Pet " .. i, guid = pet })
            if raid then WoW.raidRoster[i] = { name = class, subgroup = 1 } end
            if class ~= "MAGE" then excluded[pet] = true end
        end
        if raid then
            WoW.SetUnit("raid4", { name = "Priest", guid = "P", class = "DRUID" })
            WoW.raidRoster[4] = { name = "Priest", subgroup = 1 }
        end
        T.UpdateUI()
        local totals = { mark = 0, thorns = 0 }
        for _, row in ipairs(T.rows()) do
            if row._active then
                local id = row._def.id
                local stats = T.engine:GroupStat(row._members, row._def)
                totals[id] = totals[id] + stats.nTotal
                H.eq(stats.nMiss, #row._members, "missing count uses eligible members")
                if id == "mark" then
                    for _, m in ipairs(row._members) do
                        H.check(not excluded[m.unit], "Mark of the Wild members exclude hunter/warlock pets")
                    end
                    H.check(not excluded[row:GetAttribute("unit1")], "primary target is eligible")
                    H.check(not excluded[row:GetAttribute("unit2")], "secondary target is eligible")
                    T.UpdatePopover(row, row._members, row._def)
                    for _, pr in ipairs(T.popRows()) do
                        if pr._active then
                            H.check(not excluded[pr:GetAttribute("unit1")], "popover target is eligible")
                        end
                    end
                end
            end
        end
        H.eq(totals.mark, track and 5 or 4, "Mark of the Wild keeps players and unverified pet types")
        H.eq(totals.thorns, track and 7 or 4, "Thorns includes tracked pets in everyone mode")
    end
end

-- Pet summon/despawn and every Thorns mode use the same eligibility contract.
for _, raid in ipairs({ false, true }) do
    for _, mode in ipairs({ "default", "self", "tanks", "everyone", "disabled" }) do
        WoW.reset()
        WildlyDB = nil
        Wildly_EnsureDefaults()
        Wildly_SetConfig("thornsMode", mode)
        H.TeachSpells({ "MARK_SINGLE", "THORNS" })
        T.RefreshSpellData()
        T.ForgetTanks()
        WoW.inRaid, WoW.groupMembers = raid, 2
        local owner, pet = raid and "raid2" or "party1", raid and "raidpet2" or "partypet1"
        WoW.SetUnit(owner, { name = "Hunter", class = "HUNTER", role = "TANK" })
        if raid then
            WoW.SetUnit("raid1", { name = "Druid", guid = WoW.units.player.guid, class = "DRUID" })
            WoW.raidRoster = { { name = "Druid", subgroup = 1 }, { name = "Hunter", subgroup = 1 } }
        end
        for _, summoned in ipairs({ true, false, true }) do
            if summoned then WoW.SetUnit(pet, { name = "Pet" }) else WoW.RemoveUnit(pet) end
            for _, track in ipairs({ true, false }) do
                Wildly_SetConfig("trackPets", track)
                T.UpdateUI()
                local seen = false
                for _, row in ipairs(T.rows()) do
                    if row._active then
                        for _, member in ipairs(row._members) do
                            if member.unit == pet then
                                seen = true
                                H.eq(row._def.id, "thorns", "pet never enters Mark row")
                                T.UpdatePopover(row, row._members, row._def)
                                local target
                                for _, pr in ipairs(T.popRows()) do
                                    if pr._active and pr._unit == pet then target = pr:GetAttribute("unit1") end
                                end
                                H.eq(target, pet, "eligible Thorns pet is a real popover target")
                            end
                        end
                    end
                end
                H.eq(seen, summoned and track and mode == "everyone", "Thorns mode and pet tracking agree")
            end
        end
    end
end
H.done("test_pet_eligibility")
